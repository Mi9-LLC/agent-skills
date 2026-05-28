# 04 — localStorage / sessionStorage Tokens

**Mapped OWASP:** A07:2025 (Authentication Failures), A01:2025 (Broken Access Control — session theft).
**External references:**
- https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html#local-storage
- https://datatracker.ietf.org/doc/html/rfc6265#section-4.1.2.6 — HttpOnly
- https://supabase.com/docs/guides/auth/sessions — Supabase token storage options

## Description

`localStorage` and `sessionStorage` are accessible to any JavaScript running on the origin. That includes first-party code, dependencies, and any successful XSS. The 2025 consensus is that session tokens belong in `HttpOnly; Secure; SameSite=Lax` cookies — invisible to JS, so an XSS can't read them — while storage APIs are reserved for non-sensitive UI state (theme, last-viewed-page, cached non-PII data).

The SPA-with-JWT-in-localStorage pattern persists because tutorials popularized it before HttpOnly cookies were considered the safer default for browser auth, and because cookie-based auth requires a tiny bit of extra setup for cross-origin APIs (CORS + `credentials: include`). The trade is: any XSS anywhere on the origin — including in a transitive npm dependency — becomes session theft. With cookies + a CSRF mechanism, the same XSS can only act in-page and can't exfiltrate the session.

## What to check

### From the bundle (automated)

- `localStorage\.setItem\(['"]token` — explicit token write.
- `localStorage\.setItem\(['"](access|refresh|session|jwt|auth|id_token|bearer)` — common variants.
- `sessionStorage\.setItem\(['"](token|access|refresh|session|jwt|auth)` — same for sessionStorage.
- `JSON\.parse\(localStorage\.getItem\(['"](session|auth|user)` — structured token blob.
- `supabase\.auth.*localStorage` — Supabase's default `localStorage` persistence (can be overridden to cookies).
- `firebase.*setPersistence.*LOCAL` — Firebase persisting auth in IndexedDB / localStorage.
- `localStorage\[['"](email|name|phone|ssn|address|dob|credit)` — PII writes.

### From the running app (guided)

The static check covers most cases but the definitive answer is in the live storage. Ask the user to:

1. Open the live app in Chrome / Firefox.
2. Log in with a **test account**.
3. Open DevTools → Application → Storage → Local Storage → the app's origin.
4. Paste **only the keys** (not values), or screenshot redacted.
5. For any key that looks token-shaped, ask whether the value starts with `eyJ` (JWT) or is a JSON object with an `access_token` / `refresh_token` field.

Do the same for `sessionStorage` and `IndexedDB`. IndexedDB is the same XSS exposure but is often where Firebase / Dexie / Auth0 SDKs cache tokens.

## How to fix

- **Move auth tokens to cookies.** `HttpOnly; Secure; SameSite=Lax` (or `Strict`). Issue the cookie from the server on login; the browser sends it on every request without JS needing to touch it.
- **For SPAs hitting a different-origin API**, use the **BFF (backend-for-frontend) pattern**: the SPA talks to its own origin (`/api/*`), which holds the cookie and forwards to the real API server-to-server. The browser never sees the upstream token.
- **CSRF.** Cookie auth needs a CSRF mechanism. Use the framework default: Django CSRF token, Next.js `next-auth`, Express + `csurf` for double-submit. `SameSite=Lax` covers most navigation cases but doesn't cover same-origin XHR-driven flows.
- **For Supabase apps specifically**: use cookie storage with the `@supabase/ssr` helper. The default `@supabase/supabase-js` client persists to localStorage; explicitly construct it with a cookie-based `storage` adapter, or use the `auth-helpers`/`ssr` package which does this for you.
- **For OAuth flows that need the access token in JS** (e.g., for a third-party SDK that requires a Bearer header): hold the **refresh** token in an HttpOnly cookie and keep the short-lived access token in memory only (not localStorage). On reload, exchange the cookie for a fresh access token via your `/api/session` endpoint.
- **Don't put PII in storage.** Cache the user's display name and avatar URL if you must; do not cache email, phone, address, payment info.

If the codebase can't be changed in the short term, the best compensating control is a strict CSP that prevents inline + foreign-origin script execution. That doesn't eliminate the risk but raises the bar.

## Why it matters / attack scenario

**Scenario 1 — XSS via a transitive dependency.** A widget on the marketing site uses an analytics package that ships with a known XSS in its config-parsing path. The site escapes user input but not the analytics-package config. An attacker plants a payload in the affected field. The page runs `<script>` from the attacker. The script reads `localStorage.getItem('sb-access-token')`, base64-encodes it, and POSTs it to `attacker.example`. Done — full session for every user who loads that page. With HttpOnly cookies, the same XSS can still act in-page but cannot read or exfiltrate the cookie.

**Scenario 2 — Browser extension as adversary.** A user installs a sketchy extension. Extensions with the `<all_urls>` permission can read `localStorage` on any site. The token's lifetime is the extension's lifetime. Cookies marked `HttpOnly` are off-limits to extension content scripts; the only way to read them is via the `cookies` permission, which the browser surfaces clearly at install time.

**Scenario 3 — Refresh token with months of lifetime.** A long-lived refresh token in `localStorage` means a one-time XSS gives months of persistent access — the attacker quietly refreshes the short-lived access token forever from their server. Even rotating the user's password doesn't kill it unless the refresh token is also revoked. Cookie-bound refresh tokens, tied to a server-side session, can be revoked atomically.

**Scenario 4 — Shared computer.** A user logs in at a hotel business-center PC. They close the tab. `localStorage` persists. The next user opens DevTools (or any page that reads from the same origin) and lifts the token. `sessionStorage` would have died with the tab; an HttpOnly cookie with `Session` cookie semantics (no `Expires`) would die with the browser process.

## Mapped CWEs (selected)

- CWE-922 — Insecure Storage of Sensitive Information
- CWE-1004 — Sensitive Cookie Without 'HttpOnly' Flag
- CWE-79 — Improper Neutralization of Input During Web Page Generation (XSS as the delivery)
- CWE-200 — Exposure of Sensitive Information to an Unauthorized Actor
- CWE-359 — Exposure of Private Personal Information to an Unauthorized Actor
- CWE-256 — Plaintext Storage of a Password
- CWE-312 — Cleartext Storage of Sensitive Information
- CWE-539 — Use of Persistent Cookies Containing Sensitive Information
- CWE-613 — Insufficient Session Expiration
