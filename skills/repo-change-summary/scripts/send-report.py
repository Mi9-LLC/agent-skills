#!/usr/bin/env python3
"""Email a monthly repo-change summary with the HTML report attached as a PDF.

Renders the summary Markdown (produced by summary.sh / multi-summary.sh) into a
modern, email-safe HTML body, converts the HTML report to PDF with the locally
installed headless browser (Chrome preferred, Edge fallback), and either previews
everything (--dry-run) or sends it over SMTP (AWS SES). Recipients are literal
emails or names looked up in a .mailmap address book.

Usage:
  send-report.py --to "<LIST>" [--to ...] --summary-md FILE --attach REPORT.html
                 [--subject STR] [--title STR] [--search-dir DIR]... [--env-file PATH]
                 [--mailmap PATH] [--browser PATH] [--dry-run]

Exit codes: 0 ok · 2 bad input/args · 3 config/credentials/recipient resolution
            · 4 PDF generation · 5 SMTP send.

Python 3.9+, stdlib only. Secrets (EMAIL_PASSWORD) are never printed; EMAIL_USER
is masked in previews.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import smtplib
import ssl
import subprocess
import sys
import tempfile
from datetime import datetime
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path
from typing import NoReturn

# Palette mirrors the HTML report so the email and the attachment read as one thing.
INK = "#0f172a"
SUBTLE = "#334155"
MUTED = "#64748b"
BORDER = "#e2e8f0"
TH_BG = "#f1f5f9"
TOTAL_BG = "#eff6ff"
BRAND = "#2a78d6"
PAGE_BG = "#f1f5f9"
MONO = "Consolas,'Courier New',monospace"
SANS = "'Segoe UI',Arial,sans-serif"


def die(msg: str, code: int) -> NoReturn:
    """Print an error to stderr and exit with the given code."""
    print(msg, file=sys.stderr)
    sys.exit(code)


# ---- config files (.env, .mailmap) -----------------------------------------

def read_config_text(path: Path) -> str:
    """Read a config file as UTF-8, turning an unreadable or non-UTF-8 file into a
    clean exit 3 rather than an uncaught traceback (search_config only checks existence)."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        die(f"cannot read {path}: not valid UTF-8", 3)
    except OSError as exc:
        die(f"cannot read {path}: {exc}", 3)


def parse_env_file(path: Path) -> dict[str, str]:
    """Parse a KEY=VALUE .env file. Splits on the FIRST '=' only (SES passwords
    contain '='/'+'/'/'), keeps inline '#', strips only surrounding quotes."""
    values: dict[str, str] = {}
    for raw in read_config_text(path).splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "=" not in raw:
            continue
        key, val = raw.split("=", 1)
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        if key:
            values[key] = val
    return values


def search_config(explicit: str | None, search_dirs: list[str], names: list[str],
                  label: str) -> tuple[Path | None, list[Path]]:
    """Locate a config file. An explicit path wins (missing → fatal). Otherwise try each
    name — a whole name at a time — across every --search-dir then ~/.claude/, so a
    skill-specific name anywhere beats a generic fallback name anywhere (a project's own
    stray .env never shadows the skill's own ~/.claude file). Returns (found, searched)."""
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            die(f"{label}: no such file: {explicit}", 3)
        return p, [p]
    dirs = [Path(d) for d in search_dirs] + [Path.home() / ".claude"]
    searched: list[Path] = []
    for name in names:
        for d in dirs:
            p = d / name
            searched.append(p)
            if p.is_file():
                return p, searched
    return None, searched


def parse_mailmap(path: Path) -> list[tuple[str, str]]:
    """Parse a .mailmap into (name, email) identities. The FIRST '<...>' pair on a
    line is the canonical identity; lines without a non-empty name are skipped."""
    book: list[tuple[str, str]] = []
    for raw in read_config_text(path).splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = re.match(r"^\s*(.*?)\s*<([^>]+)>", raw)
        if m and m.group(1).strip():
            book.append((m.group(1).strip(), m.group(2).strip()))
    return book


# ---- recipient resolution ---------------------------------------------------

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def split_recipients(to_values: list[str]) -> list[str]:
    """Flatten repeated --to values, each splittable on ',' ';' or newlines."""
    tokens: list[str] = []
    for value in to_values:
        for tok in re.split(r"[,;\r\n]+", value):
            tok = tok.strip()
            if tok:
                tokens.append(tok)
    return tokens


def lookup_name(tok: str, book: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Case-insensitive tiered name match: exact full-name, then word-boundary
    prefix, then substring. Returns the FIRST tier that yields any match."""
    low = tok.lower()
    tiers = [
        [(n, e) for n, e in book if n.lower() == low],
        [(n, e) for n, e in book if re.search(r"\b" + re.escape(low), n.lower())],
        [(n, e) for n, e in book if low in n.lower()],
    ]
    for tier in tiers:
        if tier:
            return tier
    return []


def resolve_recipients(to_values: list[str], book: list[tuple[str, str]],
                       have_mailmap: bool) -> list[tuple[str, str]]:
    """Resolve every --to token to (display_name, email), deduped on lower-cased
    email (first-seen order and display name kept). Any failure exits 3."""
    known = ", ".join(dict.fromkeys(n for n, _ in book)) or "(none)"
    resolved: list[tuple[str, str]] = []
    for tok in split_recipients(to_values):
        if "@" in tok:
            if not EMAIL_RE.match(tok):
                die(f"invalid email address '{tok}'", 3)
            resolved.append(("", tok))
            continue
        if not have_mailmap:
            die(f"cannot resolve name '{tok}': no .mailmap found (pass a literal "
                f"email, --mailmap PATH, or put a .mailmap in a --search-dir)", 3)
        matches = lookup_name(tok, book)
        # One person listed under several .mailmap aliases produces duplicate rows for
        # a single canonical email; collapse on the email so a multi-alias identity is
        # not a false "ambiguous". Genuinely different people keep distinct emails.
        uniq: dict[str, tuple[str, str]] = {}
        for n, e in matches:
            uniq.setdefault(e.lower(), (n, e))
        if len(uniq) > 1:
            names = ", ".join(n for n, _ in uniq.values())
            die(f"ambiguous name '{tok}': matches {names}", 3)
        if not uniq:
            die(f"unknown recipient '{tok}'; known names: {known}", 3)
        resolved.append(next(iter(uniq.values())))

    deduped: list[tuple[str, str]] = []
    seen: set[str] = set()
    for name, email in resolved:
        key = email.lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append((name, email))
    if not deduped:
        die("no recipients resolved from --to", 3)
    return deduped


# ---- HTML -> PDF via headless browser (mandatory) ---------------------------

def discover_browsers(override: str | None) -> list[str]:
    """Ordered list of usable browser executables. Chrome is preferred over Edge
    (an Oct-2025 Edge-141 --print-to-pdf regression makes Chrome the safer pick)."""
    if override:
        return [override]
    cands: list[str] = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    ]
    local = os.environ.get("LOCALAPPDATA")
    if local:
        cands.append(os.path.join(local, "Google", "Chrome", "Application", "chrome.exe"))
    cands.append("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    for name in ("chrome", "chromium", "chromium-browser", "google-chrome"):
        found = shutil.which(name)
        if found:
            cands.append(found)
    cands += [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    edge = shutil.which("msedge")
    if edge:
        cands.append(edge)

    ordered: list[str] = []
    seen: set[str] = set()
    for c in cands:
        p = Path(c)
        if not p.is_file():
            continue
        key = str(p.resolve()).lower()
        if key not in seen:
            seen.add(key)
            ordered.append(str(p))
    return ordered


def render_pdf(browser: str, file_uri: str, mode: str) -> tuple[bytes | None, str]:
    """One conversion attempt with a throwaway profile. Returns (pdf_bytes, "") on
    success or (None, stderr_tail). Success is judged by a non-empty output PDF."""
    user_data = tempfile.mkdtemp(prefix="rcs-udd-")
    out_dir = tempfile.mkdtemp(prefix="rcs-pdf-")
    out_pdf = Path(out_dir) / "report.pdf"
    cmd = [
        browser, f"--headless={mode}", "--disable-gpu", "--no-pdf-header-footer",
        "--print-to-pdf-no-header", f"--user-data-dir={user_data}",
        f"--print-to-pdf={out_pdf}", file_uri,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=120)
        tail = (proc.stderr or b"").decode("utf-8", "replace").strip()[-800:]
        if out_pdf.is_file() and out_pdf.stat().st_size > 0:
            return out_pdf.read_bytes(), ""
        return None, tail
    except FileNotFoundError as exc:
        return None, str(exc)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, str(exc)
    finally:
        shutil.rmtree(user_data, ignore_errors=True)
        shutil.rmtree(out_dir, ignore_errors=True)


def html_to_pdf(html_path: str, override: str | None) -> bytes:
    """Convert the HTML report to PDF bytes. Tries --headless=new then =old on each
    discovered browser in turn. All attempts failing exits 4."""
    browsers = discover_browsers(override)
    if not browsers:
        die("no headless browser found (Chrome or Edge); pass --browser PATH", 4)
    # as_uri() percent-escapes the space in paths like "Mi9 Artifacts".
    file_uri = Path(html_path).resolve().as_uri()
    last = ""
    for browser in browsers:
        for mode in ("new", "old"):
            data, tail = render_pdf(browser, file_uri, mode)
            if data is not None:
                return data
            last = f"{browser} (--headless={mode}): {tail or '(no output)'}"
    die(f"PDF generation failed on every browser. Last error: {last}", 4)


# ---- summary Markdown -> email HTML body ------------------------------------

def clean(text: str) -> str:
    """Unescape backslash-escaped markdown punctuation, then HTML-escape."""
    text = text.replace(r"\*", "*").replace(r"\_", "_")
    return html.escape(text)


def _strip_bold(cell: str) -> tuple[str, bool]:
    """Return (inner_text, is_bold) for a cell, unwrapping a **...** wrapper."""
    m = re.fullmatch(r"\*\*(.*)\*\*", cell.strip())
    return (m.group(1).strip(), True) if m else (cell, False)


def _is_numeric(text: str) -> bool:
    """True for a pure number-with-thousands-separators cell (e.g. '5,618')."""
    return bool(re.fullmatch(r"[\d,]+", text.strip()))


def render_table(run: list[str]) -> str:
    """Render a run of Markdown table lines into one inline-styled HTML table."""
    rows: list[list[str]] = []
    for line in run:
        s = line.strip()
        if s.startswith("|"):
            s = s[1:]
        if s.endswith("|"):
            s = s[:-1]
        rows.append([c.strip() for c in s.split("|")])

    def is_sep(cells: list[str]) -> bool:
        return bool(cells) and all(set(c) <= set("-: ") for c in cells) \
            and any("-" in c for c in cells)

    rows = [r for r in rows if not is_sep(r)]
    if not rows:
        return ""
    header = rows[0]
    body = rows[1:]
    ncol = len(header)

    numeric_col = [False] * ncol
    for c in range(ncol):
        cores = [_strip_bold(body[r][c])[0] for r in range(len(body)) if c < len(body[r])]
        numeric_col[c] = bool(cores) and all(_is_numeric(v) for v in cores)

    if ncol <= 1:
        widths = [100]
    else:
        # Wide rollup/activity tables (a repo or developer name alongside several
        # short numeric columns) give the name column more room so it doesn't have to
        # wrap — the 2-column metric table already has enough share at 40%.
        first = 40 if ncol == 2 else (36 if ncol >= 7 else 28)
        rest = round((100 - first) / (ncol - 1))
        widths = [first] + [rest] * (ncol - 1)

    out = [f'<table role="presentation" cellpadding="0" cellspacing="0" '
           f'style="border-collapse:collapse;width:100%;margin:14px 0;font-size:13.5px;'
           f'font-family:{SANS};">']

    th_cells = []
    for c, cell in enumerate(header):
        align = "right" if numeric_col[c] else "left"
        style = (f"border:1px solid {BORDER};padding:8px 12px;background:{TH_BG};"
                 f"color:{INK};font-weight:600;text-align:{align};width:{widths[c]}%;")
        th_cells.append(f'<th width="{widths[c]}%" style="{style}">{clean(cell)}</th>')
    out.append("  <tr>" + "".join(th_cells) + "</tr>")

    for row in body:
        is_total = any(_strip_bold(cell)[1] for cell in row)
        td_cells = []
        for c, cell in enumerate(row):
            inner, _ = _strip_bold(cell)
            width = widths[c] if c < ncol else round(100 / max(len(row), 1))
            align = "right" if (c < ncol and numeric_col[c]) else "left"
            style = (f"border:1px solid {BORDER};padding:8px 12px;text-align:{align};"
                     f"width:{width}%;")
            if ncol >= 7:
                # The percentage above is a layout hint, not a hard cap — a browser's
                # table auto-layout wraps any cell whose text has a space (a repo name,
                # or the TOTAL row's "N distinct") once its share runs out; a plain
                # number never wraps since it has no space to break at, so this is a
                # no-op there. nowrap forces every cell in these wide tables to stay on
                # one line; the wider card (see build_email_html) gives the long repo/
                # developer name column room to do that without squeezing the rest.
                style += "white-space:nowrap;"
            if align == "right":
                style += f"font-family:{MONO};"
            if is_total:
                style += f"background:{TOTAL_BG};color:{INK};font-weight:700;"
            else:
                style += f"color:{SUBTLE};"
            td_cells.append(f'<td width="{width}%" style="{style}">{clean(inner)}</td>')
        out.append("  <tr>" + "".join(td_cells) + "</tr>")

    out.append("</table>")
    return "\n".join(out)


def render_heading(text: str) -> str:
    return (f'<p style="font-size:17px;line-height:1.3;font-weight:700;color:{INK};'
            f'margin:24px 0 6px;font-family:{SANS};">{clean(text)}</p>')


def render_caption(text: str) -> str:
    return (f'<p style="font-size:12.5px;font-style:italic;color:{MUTED};'
            f'margin:4px 0 8px;font-family:{SANS};">{clean(text)}</p>')


def render_note(text: str) -> str:
    return (f'<p style="font-size:13px;color:{SUBTLE};margin:4px 0;'
            f'font-family:{SANS};">&#8226; {clean(text)}</p>')


def render_paragraph(text: str) -> str:
    return (f'<p style="font-size:13px;color:{SUBTLE};margin:8px 0;'
            f'font-family:{SANS};">{clean(text)}</p>')


def _is_table_line(line: str) -> bool:
    return bool(re.fullmatch(r"\s*\|.*\|\s*", line))


def _is_bold_only(stripped: str) -> bool:
    return bool(re.fullmatch(r"\*\*.+\*\*", stripped))


def _is_caption(stripped: str) -> bool:
    return bool(re.fullmatch(r"_.+_", stripped))


def render_summary_html(md_text: str) -> str:
    """Classify the summary Markdown line-by-line into inline-styled HTML. The
    table rule is checked before the bold-heading rule; the leading document-title
    heading is dropped (the email header band already shows it)."""
    lines = md_text.splitlines()
    first_idx = next((i for i, ln in enumerate(lines) if ln.strip()), None)
    skip_idx = first_idx if (first_idx is not None
                             and _is_bold_only(lines[first_idx].strip())) else None

    frags: list[str] = []
    i = 0
    n = len(lines)
    while i < n:
        if i == skip_idx:
            i += 1
            continue
        line = lines[i]
        if _is_table_line(line):
            j = i
            run: list[str] = []
            while j < n and _is_table_line(lines[j]):
                run.append(lines[j])
                j += 1
            frags.append(render_table(run))
            i = j
            continue
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        if _is_bold_only(stripped):
            frags.append(render_heading(stripped[2:-2].strip()))
        elif _is_caption(stripped):
            frags.append(render_caption(stripped[1:-1].strip()))
        elif re.match(r"^\s*-\s+", line):
            frags.append(render_note(re.sub(r"^\s*-\s+", "", line)))
        else:
            frags.append(render_paragraph(line))
        i += 1
    return "\n".join(frags)


def build_email_html(title: str, summary_html: str, pdf_name: str) -> str:
    """Wrap the rendered summary in a fluid (90% of the reading pane, capped at 1200px)
    table-layout, inline-styled card, so it uses the client's width instead of a fixed
    narrow column. Colors are inline (email clients strip <style> and dark-mode media)."""
    title_esc = clean(title)
    pdf_esc = clean(pdf_name)
    generated = datetime.now().strftime("%Y-%m-%d %H:%M")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>{title_esc}</title>
</head>
<body style="margin:0;padding:0;background:{PAGE_BG};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="{PAGE_BG}" style="width:100%;margin:0;padding:0;background:{PAGE_BG};">
<tr>
<td align="center" style="padding:24px 12px;">
<table role="presentation" width="90%" cellpadding="0" cellspacing="0" bgcolor="#ffffff" style="width:90%;max-width:1200px;background:#ffffff;border:1px solid {BORDER};border-radius:10px;overflow:hidden;">
<tr>
<td bgcolor="{BRAND}" style="background:{BRAND};padding:20px 28px;">
<div style="font-family:{SANS};font-size:20px;line-height:1.3;font-weight:700;color:#ffffff;">{title_esc}</div>
</td>
</tr>
<tr>
<td style="padding:22px 28px 6px;font-family:{SANS};color:{INK};">
{summary_html}
<p style="font-size:13px;color:{SUBTLE};margin:18px 0 4px;font-family:{SANS};">Full report attached as <span style="font-family:{MONO};font-size:12.5px;background:{TH_BG};padding:2px 5px;border-radius:4px;color:{INK};">{pdf_esc}</span>.</p>
</td>
</tr>
<tr>
<td style="padding:14px 28px 22px;border-top:1px solid {BORDER};font-family:{SANS};font-size:11.5px;color:#94a3b8;">
Generated {generated} &#183; Generated by repo-change-summary
</td>
</tr>
</table>
</td>
</tr>
</table>
</body>
</html>
"""


# ---- message assembly, send, preview ----------------------------------------

def build_message(from_display: str, recipients: list[tuple[str, str]], subject: str,
                  plain_text: str, html_body: str, pdf_bytes: bytes,
                  pdf_name: str) -> EmailMessage:
    """Assemble the multipart/alternative + PDF message. Header assignment is guarded
    against CR/LF injection (stdlib raises ValueError → clean error, exit 3)."""
    to_header = ", ".join(formataddr((name, email)) for name, email in recipients)
    msg = EmailMessage()
    try:
        msg["From"] = from_display
        msg["To"] = to_header
        msg["Subject"] = subject
    except ValueError as exc:
        die(f"invalid email header (control characters not allowed): {exc}", 3)
    msg.set_content(plain_text)
    msg.add_alternative(html_body, subtype="html")
    msg.add_attachment(pdf_bytes, maintype="application", subtype="pdf", filename=pdf_name)
    return msg


def tls_mode_for(port: int) -> str:
    """SES: implicit TLS on 465/2465, otherwise STARTTLS. EMAIL_SECURE is advisory
    only and deliberately not consulted here."""
    return "SSL (implicit)" if port in (465, 2465) else "STARTTLS"


def do_send(msg: EmailMessage, host: str, port: int, user: str, password: str,
            recipients: list[tuple[str, str]]) -> None:
    """Send over SMTP with certificate verification always on. Failure exits 5."""
    ctx = ssl.create_default_context()
    try:
        if port in (465, 2465):
            with smtplib.SMTP_SSL(host, port, context=ctx, timeout=60) as server:
                server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=60) as server:
                server.ehlo()
                server.starttls(context=ctx)
                server.ehlo()
                server.login(user, password)
                server.send_message(msg)
    except (smtplib.SMTPException, ssl.SSLError, OSError) as exc:
        die(f"SMTP send failed via {host}:{port}: {exc}", 5)
    print(f"Sent via {host}:{port} ({tls_mode_for(port)}) to:")
    for name, email in recipients:
        print(f"  - {formataddr((name, email))}")
    print("Email sent.")


def mask_user(user: str) -> str:
    """Mask an SMTP username for previews: first 4 chars + ellipsis."""
    if not user:
        return "…"
    return (user[:4] + "…") if len(user) > 4 else (user[:1] + "…")


def do_preview(host: str, port: int, user: str, from_display: str, subject: str,
               recipients: list[tuple[str, str]], html_body: str, pdf_bytes: bytes,
               pdf_name: str) -> None:
    """Report everything the send would use, but send nothing; write body + PDF
    previews to the temp dir. The message itself is composed (and header-validated)
    by the caller before this runs."""
    body_file = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="\n", delete=False,
        prefix="rcs-body-", suffix=".html")
    body_file.write(html_body)
    body_file.close()

    # A fresh 0700 mkdtemp dir gives an unpredictable path (no symlink pre-attack, no
    # collision between runs) while keeping the friendly report filename for the user.
    pdf_path = Path(tempfile.mkdtemp(prefix="rcs-pdf-")) / pdf_name
    pdf_path.write_bytes(pdf_bytes)

    size = len(pdf_bytes)
    print("DRY RUN — building the message, no email will be sent.")
    print(f"SMTP: {host}:{port}  (TLS: {tls_mode_for(port)})")
    print(f"SMTP user (masked): {mask_user(user)}")
    print(f"From: {from_display}")
    print("To:")
    for name, email in recipients:
        print(f"  - {formataddr((name, email))}")
    print(f"Subject: {subject}")
    print(f"Attachment: {pdf_name} ({size} bytes, {size / 1024:.1f} KB)")
    print(f"Body preview: {body_file.name}")
    print(f"PDF: {pdf_path}")
    print("DRY RUN — nothing sent.")


def main() -> None:
    # Emit UTF-8 with \n line endings — previews carry em dashes / middots / ellipses
    # that a Windows cp1252 console would otherwise choke on.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8", newline="\n")

    parser = argparse.ArgumentParser(description="Email a repo-change summary with a PDF attachment.")
    parser.add_argument("--to", action="append", required=True,
                        help="recipient(s); repeatable, each may hold several separated by , ; or newline")
    parser.add_argument("--subject", default=None, help="email subject (defaults to --title)")
    parser.add_argument("--title", default=None, help="document title shown in the email header band")
    parser.add_argument("--summary-md", default=None, help="path to the summary Markdown")
    parser.add_argument("--attach", default=None, help="path to the HTML report to convert to PDF")
    parser.add_argument("--search-dir", action="append", default=None,
                        help="dir to search for repo-change-summary.env/.mailmap (repeatable)")
    parser.add_argument("--env-file", default=None, help="explicit path to the credentials file")
    parser.add_argument("--mailmap", default=None, help="explicit .mailmap path")
    parser.add_argument("--browser", default=None, help="explicit browser executable")
    parser.add_argument("--dry-run", action="store_true", help="build + preview, do not send")
    args = parser.parse_args()

    subject = args.subject or args.title
    title = args.title or args.subject
    if not subject:
        die("need --subject or --title", 2)
    if not args.summary_md:
        die("--summary-md is required", 2)
    if not args.attach:
        die("--attach (HTML report to convert to PDF) is required", 2)

    summary_path = Path(args.summary_md)
    if not summary_path.is_file():
        die(f"--summary-md: no such file: {args.summary_md}", 2)
    if not Path(args.attach).is_file():
        die(f"--attach: no such file: {args.attach}", 2)

    search_dirs = args.search_dir or []

    # credentials file (required) — resolve before the dry-run branch so a missing config
    # fails the same way whether or not we would send.
    env_path, env_searched = search_config(
        args.env_file, search_dirs, ["repo-change-summary.env", ".env"], "--env-file")
    if env_path is None:
        listed = ", ".join(str(p) for p in env_searched)
        die(f"no repo-change-summary.env or .env found (searched: {listed})", 3)
    env = parse_env_file(env_path)
    missing = [k for k in ("EMAIL_HOST", "EMAIL_USER", "EMAIL_PASSWORD", "EMAIL_FROM")
               if not env.get(k)]
    if missing:
        die(f"{env_path.name} missing required key(s): {', '.join(missing)} (in {env_path})", 3)

    host = env["EMAIL_HOST"]
    user = env["EMAIL_USER"]
    password = env["EMAIL_PASSWORD"]
    email_from = env["EMAIL_FROM"]
    from_name = env.get("EMAIL_FROM_NAME")
    from_display = formataddr((from_name, email_from)) if from_name else email_from
    try:
        port = int(env.get("EMAIL_PORT", "587"))
    except ValueError:
        die(f"invalid EMAIL_PORT '{env.get('EMAIL_PORT')}' (expected an integer)", 3)

    # .mailmap (optional unless a name token needs resolving).
    mailmap_path, _ = search_config(args.mailmap, search_dirs, [".mailmap"], "--mailmap")
    book = parse_mailmap(mailmap_path) if mailmap_path else []
    recipients = resolve_recipients(args.to, book, mailmap_path is not None)

    # PDF is mandatory — generated in both dry-run and send paths.
    pdf_bytes = html_to_pdf(args.attach, args.browser)
    pdf_name = Path(args.attach).stem + ".pdf"

    summary_md = summary_path.read_text(encoding="utf-8")
    summary_html = render_summary_html(summary_md)
    html_body = build_email_html(title, summary_html, pdf_name)
    msg = build_message(from_display, recipients, subject, summary_md, html_body,
                        pdf_bytes, pdf_name)

    if args.dry_run:
        do_preview(host, port, user, from_display, subject, recipients,
                   html_body, pdf_bytes, pdf_name)
        sys.exit(0)

    do_send(msg, host, port, user, password, recipients)


if __name__ == "__main__":
    main()
