# Emailing the report

Optional delivery mode for `summary.sh` and `multi-summary.sh`: instead of (or as well
as) opening the HTML report in a browser, email it as a PDF attachment with a modern,
email-safe HTML body. Handled by the bundled `scripts/send-report.py` (Python 3.9+,
stdlib only). See `SKILL.md` for the short version of the flags and workflow — this
file is the detail.

## Default workflow: dry-run, then confirm, then send

By default, every email send is preceded by a preview:

1. Run with `--email-dry-run` (plus whatever `--to`/`--subject` the user gave). This
   resolves every recipient, renders the HTML report to PDF, composes the full
   message, and prints a preview — `To:`, `Subject:`, the attachment name and size, and
   the on-disk paths of a body-preview HTML file and the generated PDF (both written to
   the system temp directory so they can be opened and checked). Nothing is sent, and
   no browser is opened even if `--no-open` wasn't given.
2. Show the user the resolved `To:` list, subject, and attachment from that preview.
   This is where a mistyped name or an unintended recipient surfaces, before anything
   leaves the machine.
3. Only on explicit user confirmation, re-run for real: the same flags, minus
   `--email-dry-run`. Add `--no-fetch` so the repo isn't fetched a second time. Note
   `--no-fetch` freezes only the *remote* pull, not local commits — if a while has passed
   since the preview, re-run the dry-run so the numbers still match what gets sent.

## Direct send (skip the preview)

When the user explicitly asks to skip the preview — "send it directly", "send right
away", "no dry-run", "skip the preview/confirm" — run `--email` in one step and report a
brief confirmation only; they'll read the report in the email. This is safe for
self-sends and known `.mailmap` recipients: `send-report.py` still resolves and validates
every recipient first, so an unknown name or malformed address fails (exit 3, nothing
sent). For a new address not yet in the `.mailmap`, still echo the resolved `To:` before
sending, even when asked to skip.

## Flags

On both `summary.sh` and `multi-summary.sh`:

- `--email` — turn emailing on.
- `--to LIST` — recipient(s); implies `--email`. See "Recipient syntax" below.
- `--subject STR` — email subject. Defaults to the generated report title
  (`Repository change summary — <repo|group> — <month>`).
- `--email-dry-run` — build everything but send nothing; implies `--email`.
- `--env-file PATH` — explicit path to the credentials file (default name `repo-change-summary.env`).
- `--mailmap PATH` — explicit path to the `.mailmap` address book.

`--email` or `--email-dry-run` given without `--to` fails at parse time (exit 2) —
there's no "email on, no recipients" state.

## `repo-change-summary.env` (SMTP credentials)

The credentials file is named **`repo-change-summary.env`** — skill-specific, so it won't
collide with any other tool's `.env` and a project's own stray `.env` can never shadow it.
A plain `.env` is still accepted as a fallback. Format: `KEY=VALUE`, one per line, blank
lines and `#`-comments ignored, surrounding quotes stripped. Splits only on the **first**
`=` (SES passwords routinely contain `=`, `+`, `/`). Required keys:

```
EMAIL_HOST=email-smtp.us-east-1.amazonaws.com
EMAIL_USER=<your-SES-SMTP-username>
EMAIL_PASSWORD=<your-SES-SMTP-password>
EMAIL_FROM=reports@example.invalid
```

Optional keys:

```
EMAIL_PORT=587
EMAIL_SECURE=true
EMAIL_FROM_NAME=Repo Change Summary
```

- `EMAIL_PORT` defaults to `587`. TLS mode is derived **purely from the port**: `465`
  or `2465` use implicit SSL, anything else uses STARTTLS.
- `EMAIL_SECURE` is accepted in the file but not read by `send-report.py` at all — it
  has no effect on which TLS mode is used. Keep it only as a human-readable note of
  intent, or drop it.
- `EMAIL_FROM_NAME`, if set, becomes the display name on the `From:` header
  (`"Name <email>"`); otherwise `From:` is the bare `EMAIL_FROM` address.
- `EMAIL_PASSWORD` is never printed anywhere, including dry-run previews.
  `EMAIL_USER` is masked in previews (first 4 characters + `…`).
- Certificate verification is always on (`ssl.create_default_context()`, no override
  flag exists to weaken it).

**Never commit a real `repo-change-summary.env` (or `.env`).** Both are covered by this
repo's `.gitignore`; the example above uses placeholders only — never paste a real host,
username, or password into a doc, chat message, or log that leaves the machine.

## `.mailmap` (recipient address book)

Standard git-mailmap syntax. The emailer reads the **first `Name <email>` pair** on
each line (so it can reuse a `.mailmap` a repo already keeps for author-name
normalization); lines with no name before the first `<...>` are skipped.

```
Jordan Alvarez <jordan.alvarez@example.invalid>
Priya Nair <priya.nair@example.invalid> <priya.n@old-example.invalid>
```

Optional — only needed when a `--to` token is a name rather than a literal email.

## Config search order

Explicit `--env-file` / `--mailmap` always win and a missing explicit path is fatal.
Otherwise the credentials file and the `.mailmap` are searched across these locations. The
credentials file is looked up as `repo-change-summary.env` across **all** of them first,
then as a plain `.env` — so a project's stray `.env` never wins over your
`~/.claude/repo-change-summary.env`:

- **Single-repo (`summary.sh`)**: the target `--repo` directory, then the current
  directory, then `~/.claude/`.
- **Group (`multi-summary.sh`)**: the current directory, then `~/.claude/` (there's no
  single repo root to search across a group).

A missing credentials file is fatal (exit 3) — there's no sending without credentials. A missing
`.mailmap` is fine as long as every `--to` token is a literal email address.

## Team / multi-user setup

The skill is installed per-project with `npx skills add …` and run against each person's
own repos — nobody sits in this catalog repo — so **keep `repo-change-summary.env` and
`.mailmap` in `~/.claude/`**, the search order's final fallback. One copy there is found no matter which
repo or directory a teammate runs from, and it sits outside every git tree so it can't be
committed. (This mirrors where the group `.list` files already live —
`~/.claude/repo-change-summary-groups/`.) Never keep the real credentials file inside a
repo working tree: this catalog repo is public, and a `.gitignore` entry is one
`git add -f` away from leaking the SES password.

The two files need different handling:

- **`repo-change-summary.env` is a secret** (the SES SMTP password). There is no safe
  single shared copy — a plaintext secret on a shared drive is a leak waiting to happen.
  Distribute the credentials through your team's password manager / secret store (or AWS
  Secrets Manager), and each teammate pastes them into their own
  `~/.claude/repo-change-summary.env` once per machine.
- **`.mailmap` is a shared, low-sensitivity address book.** Keep the canonical copy
  somewhere internal (a team wiki, or a private repo) and have each teammate drop it into
  `~/.claude/.mailmap`.

If a team already has a secured shared mount, point `--env-file` / `--mailmap` at it
explicitly instead of relying on `~/.claude/`.

## Recipient syntax (`--to`)

`--to` is repeatable, and each value may hold several recipients separated by `,`,
`;`, or a newline. Every token is either:

- **A literal email** (`user@example.invalid`) — checked against a plain
  `local@domain.tld` shape; a malformed one fails immediately (exit 3).
- **A name**, looked up in the `.mailmap` book case-insensitively, in tiers — the
  **first tier with any match wins**:
  1. Exact full-name match.
  2. Word-boundary match — the token matches starting at a word boundary anywhere in
     the name (catches a first name, a last name, or a prefix of either).
  3. Substring match — the token appears anywhere in the name.

  A tier that matches **more than one person** is an error (`ambiguous name '<X>':
  matches A, B`) rather than guessing which one was meant. A name matching nobody at
  any tier is an error that lists every known name from the `.mailmap`.

Duplicate recipients (case-insensitive on the email address) are deduped, keeping the
first display name seen.

## PDF generation (mandatory)

The HTML report that `summary.sh`/`multi-summary.sh` just generated for this run
(charts included) is converted to PDF by the **locally-installed headless browser** —
no new dependency is installed for this. Discovery order: **Chrome first, Edge as
fallback**. Chrome is preferred because of a known Edge 141 regression (Oct 2025) where
headless `--print-to-pdf` can fail or hang; trying Chrome first sidesteps it on
machines that have both installed. Each browser is tried with `--headless=new` then
`--headless=old` before moving to the next. Override the browser entirely with
`--browser PATH` (a flag on `send-report.py`, not currently exposed as a shell-script
flag — pass it by calling `send-report.py` directly if a non-standard install needs
pointing to).

The attachment filename mirrors the HTML report's name with a `.pdf` extension (e.g.
`2026-07-17-1512-repo-change-summary-2026-06.html` → `…-2026-06.pdf`).

PDF generation is **not optional** — if no working browser is found, or every attempt
on every discovered browser fails, the run errors out (exit 4) rather than sending an
email with no attachment.

## What gets sent

- **HTML body** — a modern, email-safe rendering of the same summary Markdown table
  (inline CSS only, table-based layout, no external stylesheet — Outlook and Gmail
  both strip `<style>` blocks and dark-mode media queries, so nothing relies on them).
  A fluid card — 90% of the reading pane, capped at 1200px (was fixed 600px, then 720px;
  made fluid 2026-07-21 to use the client's full width and leave a ~5% margin each side).
  Numeric columns are right-aligned in a monospace font; a bolded Markdown row (the
  totals row) is styled as a highlighted total row. A table with 7+ columns (the group
  rollup and per-developer tables) gives its first column — the repo or developer name —
  more width, and every cell in that table is forced to stay on one line
  (`white-space:nowrap`): an HTML table's automatic layout only wraps text that has a
  space to break at, so it's not just the name column at risk — a plain number never
  wraps (nothing to break on) but a short phrase like the TOTAL row's "N distinct" does,
  once its column's share runs out. The 2-column single-repo metric table is
  unaffected — its labels wrap the same as before.
- **Attachment** — the full HTML report, converted to PDF (see above).
- **Plain-text alternative** — the raw Markdown summary, unrendered, for mail clients
  that prefer text/plain.

## Exit codes (`send-report.py`)

| Code | Meaning |
|---|---|
| 0 | Sent successfully, or a dry run completed. |
| 2 | Bad input or arguments — e.g. `--email`/`--email-dry-run` given without `--to` (caught by the shell script before `send-report.py` even runs), or a missing `--subject`/`--title`, missing `--summary-md`/`--attach`, or a path that doesn't exist. |
| 3 | Config, credentials, or recipient problem — no credentials file found, a required key missing, an invalid/ambiguous/unknown recipient, or an invalid email header. |
| 4 | PDF generation failed — no headless browser found, or every browser attempt failed. |
| 5 | SMTP send failed. |

`summary.sh` / `multi-summary.sh` propagate `send-report.py`'s exit code as their own
when the email step fails. This always happens **after** the git-derived Markdown
table and the `HTML report:` line have already printed — a failed send never hides the
numbers the run produced.

## Troubleshooting

- **"no repo-change-summary.env or .env found (searched: ...)"** — put a
  `repo-change-summary.env` at one of the searched paths (see "Config search order"), or
  pass `--env-file PATH` explicitly.
- **"… missing required key(s): ..."** — add the missing key(s) to the credentials file;
  `EMAIL_HOST`, `EMAIL_USER`, `EMAIL_PASSWORD`, and `EMAIL_FROM` are all required.
- **"ambiguous name '<X>': matches A, B"** — the name matched more than one `.mailmap`
  entry at the same tier; use a more specific name or the literal email instead.
- **"unknown recipient '<X>'; known names: ..."** — the name matched nobody in the
  `.mailmap`; check spelling against the listed known names, or pass a literal email.
- **"no headless browser found (Chrome or Edge); pass --browser PATH"** (exit 4) —
  install Chrome or Edge, or point `--browser` at an existing install.
- **"PDF generation failed on every browser. Last error: ..."** (exit 4) — read the
  trailing browser stderr included in the message; a corporate policy blocking headless
  mode is a common cause. Try `--browser` pointed at a different install.
- **"SMTP send failed via host:port: ..."** (exit 5) — check `EMAIL_HOST`/`EMAIL_PORT`
  against the actual SES SMTP endpoint for the account's region, and confirm the credentials file
  holds SES **SMTP** credentials (not an AWS console password or an IAM access key).
