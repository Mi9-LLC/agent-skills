# 06 — Auth Rate Limiting

**Mapped OWASP:** A07:2025 (Authentication Failures), A06:2025 (Insecure Design — no abuse case).
**External references:**
- https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html#login-throttling
- https://datatracker.ietf.org/doc/html/rfc2606 — `.invalid` TLD reserved for testing
- https://haveibeenpwned.com/Passwords — credential-stuffing reality check

## Description

A login endpoint without rate limiting is an open invitation for credential stuffing. The attack premise: billions of email/password pairs have leaked over the years; many users reuse passwords; an attacker who can submit unlimited login attempts can replay those pairs against any new site. Even modest reuse rates (1–3%) yield real takeovers at scale.

The countermeasure is straightforward in principle — slow down or block attempts past a threshold — and surprisingly often absent in practice, because adding rate-limiting on a new login flow takes deliberate effort and the framework default is unlimited. The check is also genuinely runtime: a source review can confirm a middleware *exists*, but only a live probe confirms it *fires*.

This is an **active probe**. Step 0 must authorize it before this skill runs the test.

## What to check

The probe pattern is documented in SKILL.md Step 6 — 15 POSTs to the login endpoint with a clearly bogus email and varied bogus passwords, 200ms apart, with status code + timing recorded.

What to interpret from the results:

- **All 15 succeed in returning `401` with similar timing, no `Retry-After`, no `429`** → no detectable rate limit. **High** finding.
- **`429 Too Many Requests` (or `403`) after N attempts** → working rate limit. Record N and `Retry-After`. ✅
- **A measurable timing slowdown** (e.g., attempt 1 returns in 50ms, attempt 15 in 400ms) → exponential backoff. ✅
- **A CAPTCHA challenge appearing in the body after N attempts** → working anti-automation. ✅
- **A `423 Locked` or "account locked" body after N attempts on the same user** → account-level lockout. ✅ (but see lockout note below)
- **Endpoint starts returning `500` after N attempts** → rate limiter is crashing the app. **Medium**.

### Lockout vs throttling

Account lockout (lock after N failures *on the same account*) is **not** the right primary defense; it enables a denial-of-service against any user whose email an attacker knows. The right primary defense is *per-IP* throttling + global throttling + CAPTCHA escalation. Lockout is acceptable as a *secondary* defense after, say, 10 unique-IP failures in a short window.

### Distributed credential stuffing

A single-IP probe like this can't detect whether the app handles distributed attacks (one attempt per IP, thousands of IPs). The presence of basic per-IP throttling is necessary; detecting whether globally-distributed protection exists requires Cloudflare/AWS WAF / a bot-management product, not curl. Document the limit of the check.

## How to fix

- **Per-IP rate limit on the login route.** 5–10 attempts per IP per minute, 429 with `Retry-After`.
  - Express: `express-rate-limit` middleware on the login router.
  - FastAPI: `slowapi` or `fastapi-limiter` (Redis-backed).
  - Django: `django-ratelimit` or `django-axes`.
  - Next.js: `@upstash/ratelimit` is the common edge choice.
- **Global rate limit on `/api/auth/login`** as a second layer, sized to your peak legitimate traffic.
- **CAPTCHA escalation** after 3 failures from the same IP. Cloudflare Turnstile, hCaptcha, reCAPTCHA Enterprise.
- **Bot management** at the edge. Cloudflare Bot Fight Mode / AWS WAF Bot Control catches the distributed credential-stuffing case.
- **Don't lock accounts as primary defense.** It DoSes legitimate users when an attacker targets known emails.
- **Surface the limit in responses.** `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After` — helps legitimate clients back off.
- **Monitor and alert.** Log every 429. Spike in 429s on the login route is a credential-stuffing campaign in progress.
- **Bonus: breached-password check.** Use HIBP's k-anonymity API at signup/login to refuse known-compromised passwords. Drops the attack surface drastically.

## Why it matters / attack scenario

**Scenario 1 — Credential stuffing against a new SaaS.** A small B2B SaaS launches. The login route has no rate limit. An attacker rents a $30/month proxy pool and runs a 100M-pair list at 100 req/sec from many IPs. Successful pairs (about 1% in 2025 estimates) yield real takeovers. The first the team notices is when a CEO's account exfiltrates customer data. Adding per-IP throttling + CAPTCHA escalation + WAF would have made the attack uneconomical.

**Scenario 2 — Targeted brute force.** A startup's founder is the target. The attacker knows their email from LinkedIn. Without per-IP limits, the attacker runs a dictionary attack of 100k common passwords + the founder's known passwords from past leaks. With a per-IP limit of 5/min, the attack takes years instead of minutes. With CAPTCHA after 3 failures, it doesn't start.

**Scenario 3 — Account-lockout DoS.** App has aggressive per-account lockout — 3 failures locks the account for an hour. An attacker who knows employee emails can lock every employee out for hours by sending 3 bad passwords each. The "defense" is now the attack. Per-IP throttling is the right primary defense.

**Scenario 4 — Rate limit fails open.** A Redis-backed rate limiter crashes when Redis is unreachable. The naive implementation logs the error and lets the request through. An attacker who can cause Redis pressure (or who attacks during a Redis incident) bypasses the limiter entirely. Fail-closed (`429` on rate-limit-backend failure) is the right default for auth endpoints.

## Mapped CWEs (selected)

- CWE-307 — Improper Restriction of Excessive Authentication Attempts
- CWE-770 — Allocation of Resources Without Limits or Throttling
- CWE-799 — Improper Control of Interaction Frequency
- CWE-837 — Improper Enforcement of a Single, Unique Action
- CWE-636 — Not Failing Securely ('Failing Open') — applies when rate-limit backends fail
- CWE-693 — Protection Mechanism Failure
- CWE-1390 — Weak Authentication
