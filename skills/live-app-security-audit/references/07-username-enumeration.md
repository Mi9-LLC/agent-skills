# 07 — Password-Reset / Login Username Enumeration

**Mapped OWASP:** A07:2025 (Authentication Failures), A09:2025 (Logging Failures — when only one path logs).
**External references:**
- https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
- https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html#authentication-and-error-messages
- https://owasp.org/www-community/attacks/Forced_browsing (related)

## Description

Username enumeration is the ability to determine, without authenticating, whether an email/username is registered on a system. Every authentication-adjacent endpoint — login, password reset, registration, MFA challenge, account recovery — has the temptation to return a different response for "user exists" vs "user does not exist" (different status, different body text, different cookies set, even different timing). Each such difference lets an attacker compile a list of valid accounts.

That list feeds three downstream attacks: targeted phishing (you know the user's real account exists), targeted credential stuffing (focus the leaked-password list on real accounts only), and targeted social engineering ("Hi, I'm from <Company> support, I see your account here…"). The cost of an enumeration finding isn't the leak itself — it's the multiplier on every other attack the user faces.

This is an **active probe**. Step 0 must authorize it before this skill runs the test.

## What to check

The probe pattern is documented in SKILL.md Step 7 — submit a known-not-registered email and (ideally) a known-registered email to the password-reset and login flows, then diff the responses along five axes.

### The five-axis diff

1. **Status code.** A `200` for existing-user vs `404` for not-existing is the most obvious leak. Even subtler: `400` vs `200`.
2. **Body content.** "If that email exists, we sent a link" (good — same body either way) vs "No account with that email" (bad — body branches on existence).
3. **Response time.** A consistent > 50ms gap is signal of a DB lookup gate ("if user not found, return early") vs full-flow processing for existing users. Run each probe 3 times and look at the median to filter network noise.
4. **`Set-Cookie` behavior.** Sometimes only the existing-user branch sets a session cookie or a CSRF cookie. Different cookie shapes between branches is a leak.
5. **Headers.** `X-RateLimit-Remaining` decremented only on one branch (because only one branch did the DB call) is a side-channel leak.

### Choosing emails

- **Email A — guaranteed not registered:** `live-audit-probe-not-registered-<timestamp>@example.invalid`. `example.invalid` is RFC-2606-reserved and never resolves to a real account.
- **Email B — guaranteed registered:** ideally a test account the user controls on the live app. If not available, use a second `.invalid` address (you'll only catch loose enumeration; document the limit).

### Endpoints to probe

- `/api/auth/forgot-password` (or framework equivalent: `/auth/reset`, `/password/email`, `/account/recover`).
- `/api/auth/login` (with deliberately wrong password — see Step 6 for rate-limit interaction).
- `/api/auth/register` if the user authorizes — registering an existing email often returns "already exists" verbatim.
- `/api/auth/mfa/challenge` if the app has it — the same enumeration surface often appears here.

### When the reset endpoint isn't externally discoverable (tRPC / GraphQL apps)

On apps using tRPC, GraphQL, or gRPC-Web for auth, the public forgot-password procedure is unlikely to surface as a literal `/api/auth/forgot-password` URL in the bundle. You may see candidate REST paths that all return `401 Unauthorized` with a `sub-status: invalidAuthHeader`-style header — meaning the path exists but is auth-gated, which is unusual for a forgot-password flow (a user who has forgotten their password by definition cannot authenticate).

The most likely explanations:

1. The actually-public endpoint is the RPC base (`/api/trpc/auth.forgotPassword`) and the procedure name was not located.
2. A bootstrap endpoint issues a short-lived CSRF / pre-session token first, which is required to call the reset procedure.
3. The reset flow lives on a different host or path that wasn't discovered from the bundle.

When this happens, **document it as a limit of the external audit** rather than asserting "no enumeration found." Recommend that the internal team confirm the public reset path and re-run the five-axis enumeration check from inside knowledge — or use a captured browser-driven flow (DevTools Network tab during a real "forgot password" flow) to identify the actual request shape.

### What to flag

- **High:** different status codes, or different body text, between exists and not-exists.
- **High:** different `Set-Cookie` behavior.
- **Medium:** consistent > 50ms timing gap that survives 3 probes (median).
- **Medium:** different rate-limit header decrement.
- **Low:** different content-length but same body text (often legitimate due to dynamic anti-CSRF tokens — verify before flagging).
- **✅** All five axes identical across multiple probes — record as "no enumeration detected on tested endpoints."

## How to fix

- **Single response for all branches.** Both branches return the same status code (200), the same body text, and the same headers. Recommended message: "If an account with that email exists, we've sent a password-reset link to it. Check your inbox."
- **Constant-time work.** Both branches do equivalent work before responding:
  - Both compute a hash (even if the user doesn't exist, do a dummy bcrypt to consume the time).
  - Both queue an email (the not-existing branch queues a no-op; the rate of emails to existing users is the same as to not-existing — defense against any out-of-band timing channel).
- **Throttle the endpoint.** Per-IP and per-email rate limit on `/forgot-password`. Without throttling, an attacker can enumerate at scale even if the responses are identical (network-level signals like the existence of a sent email become observable).
- **Avoid generating distinct verification tokens for non-users.** If the reset code is a database row keyed on user_id, only generate for existing users; the response should still be identical, but don't litter the DB with spurious rows.
- **Same CAPTCHA/bot challenge on both branches.** Don't escalate to CAPTCHA only on the existing branch.
- **Same email-or-no-email behavior.** Don't send a notification email only when the user exists. Either send "Someone tried to reset your password" to existing users, or send "Someone tried to reset a password for this email; we don't have an account for it" to not-existing users. Or — most operationally common — send to existing only, but make sure the response, cookies, headers, and timing are identical.
- **Login endpoint** — return generic "Invalid email or password" for both wrong-email and wrong-password cases. Same status code. Same body.
- **Registration endpoint** — when the email is already taken, don't say so immediately. Send "Check your inbox to confirm" and email the actual user "Someone tried to register again — if it was you, you already have an account." This is more friction but closes the registration-enumeration channel.

## Why it matters / attack scenario

**Scenario 1 — Reset-flow enumeration → targeted phishing.** Password reset returns "We've sent a link" for existing users and "No account with that email" for non-existing. Attacker enumerates a list of 100k leaked emails against the app, gets 8k confirmations. Sends a convincing "Your account requires verification" phishing email to those 8k. Click-through is far higher than untargeted phishing because the attacker only contacts users known to have an account.

**Scenario 2 — Timing-based enumeration.** Status and body are identical, but the existing-user branch does a bcrypt-against-stored-hash that takes 200ms; the non-existing branch returns in 5ms. Attacker times 100k email probes and statistically separates the two distributions. Even ~40ms median deltas are detectable with a few repeats per email. Fix: dummy bcrypt on the not-found branch.

**Scenario 3 — Set-Cookie enumeration.** Login sets a CSRF cookie only when the email is found (because the controller's "show the password form" branch fires for existing users, while the not-found branch returns early). Attacker doesn't need to time anything; just check whether `Set-Cookie` appears. Fix: set the same cookies on both branches.

**Scenario 4 — Registration enumeration.** Attacker hits `/register` with each leaked email. "Email already in use" → confirmed account. The downstream is the same as Scenario 1, but faster and without needing the reset flow. Fix: the verify-via-email pattern above.

## Mapped CWEs (selected)

- CWE-204 — Observable Response Discrepancy
- CWE-203 — Observable Discrepancy
- CWE-208 — Observable Timing Discrepancy
- CWE-200 — Exposure of Sensitive Information to an Unauthorized Actor
- CWE-359 — Exposure of Private Personal Information to an Unauthorized Actor
- CWE-307 — Improper Restriction of Excessive Authentication Attempts (related throttle)
- CWE-799 — Improper Control of Interaction Frequency
- CWE-693 — Protection Mechanism Failure
