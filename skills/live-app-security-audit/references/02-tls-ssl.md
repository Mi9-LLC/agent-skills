# 02 — TLS / SSL

**Mapped OWASP:** A02:2025 (Security Misconfiguration), A04:2025 (Cryptographic Failures).
**External references:**
- https://www.ssllabs.com/projects/best-practices/
- https://wiki.mozilla.org/Security/Server_Side_TLS
- https://api.ssllabs.com/api/v3/analyze — JSON API for programmatic scans
- https://datatracker.ietf.org/doc/html/rfc8996 — TLS 1.0/1.1 deprecation

## Description

TLS is the perimeter for every request. Modern browsers refuse to connect over TLS 1.0/1.1 — but custom clients, mobile apps, and middleboxes still do. A site supporting weak protocols isn't usually exploited via the browser; it's exploited via lateral attackers on the same network downgrading non-browser clients (mobile push, CI calls, webhooks). Cert expiry is the other live failure mode: an expired cert breaks the app for everyone with no remediation faster than reissue, and a near-expiry cert (< 14 days) is a same-week incident waiting to happen.

The ssllabs.com SSL Server Test is the de-facto runtime check. Its JSON API gives the same grade and detail without scraping HTML. Grade A or better is the modern bar; A+ requires HSTS-preload + clean chain + perfect cipher list.

**API status (June 2026):** the SSL Labs **API v3 is deprecated** (since Jan 2024) but remains live and registration-free — it may be withdrawn without notice. **v4 requires registration** and an `email` request header (free-mail addresses rejected). Use the `/api/v3/analyze` endpoint while it lasts; if it disappears, fall back to a local scanner (`testssl.sh`, `sslyze`) against the reachable host.

**Certificate lifetimes are shrinking (CA/Browser Forum SC-081v3):** the max public-cert validity is **200 days since 2026-03-15**, stepping down to **100 days in 2027** and **47 days in 2029**. Manual renewals will no longer be viable at these intervals — **renewal automation (ACME / cert-manager) is mandatory**, not optional.

## What to check

- **Grade** from `https://api.ssllabs.com/api/v3/analyze?host=<host>&publish=off&fromCache=on`. Below A is a finding.
- **Protocols.** Any of `TLS 1.0`, `TLS 1.1`, `SSL 3.0` enabled → **High**. TLS 1.2 only is acceptable; TLS 1.2 + 1.3 is the modern default.
- **Certificate.**
  - Expiry in ≤ 14 days → **High**.
  - Subject mismatch with the hostname → **Critical**.
  - Self-signed in production → **Critical**.
  - Chain incomplete (missing intermediate) → **Medium**; many clients tolerate this but mobile / CI often won't.
- **Cipher suites.** Any of `RC4`, `3DES`, `DES`, `NULL`, `EXPORT`, `ECDHE+CBC` (legacy), `anon-` ciphers → **High**.
- **Known vulnerabilities** (ssllabs reports these as booleans):
  - `vulnBeast`, `heartbleed`, `poodle`, `poodleTls`, `freak`, `logjam`, `drownVulnerable` → all **Critical**.
  - `supportsRc4` → **High**.
- **HSTS.** ssllabs reports HSTS status; absence with HTTPS is **High** for auth sites. See `01-security-headers.md`.
- **HTTP → HTTPS redirect.** `curl -sI http://host/` must return `301`/`308` to `https://`. A `200` over plain HTTP is **High**.
- **OCSP stapling.** Not stapled → **Low** (latency, no security impact post-SHA-1).
- **Forward secrecy.** ECDHE / DHE present in cipher list. Absence → **Medium**.

## How to fix

- **Nginx** — `ssl_protocols TLSv1.2 TLSv1.3;` + Mozilla "intermediate" cipher list. Auto-renew certs via certbot or cert-manager.
- **Apache** — `SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1` + matching cipher list.
- **Caddy** — defaults are correct; just don't override.
- **Cloudflare** — set minimum TLS version to 1.2 in SSL/TLS → Edge Certificates. Toggle "Always Use HTTPS" on.
- **AWS ALB / CloudFront** — choose a security policy of `TLSv1.2_2021` or later.
- **Vercel / Netlify** — managed; verify in dashboard, not in code.
- **Cert rotation** — automate via Let's Encrypt + ACME. Manual renewals are a recurring outage source.
- **HSTS preload.** After confirming all subdomains are HTTPS-only, submit to `hstspreload.org` for browser-shipped preload.

## Why it matters / attack scenario

**Scenario 1 — Café Wi-Fi downgrade.** App supports TLS 1.0. A custom mobile client written a few years ago negotiates TLS 1.0 by default. An attacker on the café Wi-Fi forces a downgrade and uses POODLE/BEAST-class CBC attacks on the session — slower than 2014's headlines suggested, but still viable on long-lived mobile sessions. Forcing TLS 1.2 minimum closes the window entirely.

**Scenario 2 — Cert expired Friday night.** The cert renewed manually by an admin who left the company. On Friday night the cert expires; every browser blocks the site with a full-page warning; mobile push servers throw cert-chain errors and queue messages indefinitely. Automated renewal would have replaced the cert weeks earlier; alerting on `< 30 days to expiry` would have caught it days earlier.

**Scenario 3 — Internal API on plain HTTP.** Step 5 of this skill found `http://internal-api.example.com/orders` in the bundle. A user on hotel Wi-Fi triggers a checkout. The unencrypted request is captured by anyone on the network — full order body, including the bearer token in headers. Forcing HTTPS on every endpoint (HSTS + HTTP redirect on the API host) eliminates the leak.

**Scenario 4 — Subdomain takeover.** Wildcard cert covers `*.example.com`. A long-forgotten `legacy.example.com` CNAMEs to a defunct Heroku app. An attacker claims the Heroku name and now serves arbitrary content from a subdomain trusted by the user's browser — and shares any cookies scoped to `.example.com`. Auditing DNS + revoking unused subdomain CNAMEs is the fix; HSTS on the apex doesn't help here.

## Mapped CWEs (selected)

- CWE-326 — Inadequate Encryption Strength
- CWE-327 — Use of a Broken or Risky Cryptographic Algorithm
- CWE-295 — Improper Certificate Validation
- CWE-296 — Improper Following of a Certificate's Chain of Trust
- CWE-297 — Improper Validation of Certificate with Host Mismatch
- CWE-298 — Improper Validation of Certificate Expiration
- CWE-319 — Cleartext Transmission of Sensitive Information
- CWE-757 — Selection of Less-Secure Algorithm During Negotiation
- CWE-310 — Cryptographic Issues
- CWE-523 — Unprotected Transport of Credentials
