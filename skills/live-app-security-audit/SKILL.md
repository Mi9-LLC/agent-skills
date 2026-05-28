---
name: live-app-security-audit
description: Runtime security audit of any deployed, live web application. Use proactively and aggressively whenever the user asks to audit a live URL, scan a deployed app, check the production security posture of a running site, vet a "vibe-coded" app for common runtime mistakes, or inspect security headers / TLS / frontend bundles / localStorage / network traffic / login rate-limiting / username enumeration on a running target. Triggers on phrases like audit my live site, scan my deployed app, audit https://..., check the headers on my site, run an SSL Labs scan, inspect my JS bundle for secrets, are my API keys exposed, find leaked Supabase keys, check localStorage tokens, test rate limiting on login, password reset enumeration check, production security audit, live security audit, runtime security check. Active probes (rate-limit, enumeration) require explicit target-authorization at Step 0. Writes a structured report to audit/<YYYY-MM-DD>/live-audit.md in the project root. Complementary to security-vulnerability-scan (static source review) — run both for full coverage. If the user asks for a security review without naming a live URL or a source tree, ask which they mean and offer to run both.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Write
---

# live-app-security-audit

Runtime security audit of a **deployed, live web application** reachable over the network. Produces a persisted Markdown report under `audit/<YYYY-MM-DD>/live-audit.md` in the project root and echoes the path back to the user.

This skill is the runtime counterpart to `security-vulnerability-scan` (which is static-only on source code). The two are designed to be used together: this one finds what only a live target exposes — TLS posture, header gaps, secrets baked into the deployed JS bundle, tokens parked in `localStorage`, unauthenticated endpoints, missing login rate limits, account-enumeration on password reset. None of those are findable by reading the repo.

## When I Activate

Activate proactively on any of the following — do not wait for the literal phrase "use the live-app-security-audit skill":

- "audit my live site", "audit my deployed app", "audit https://…", "scan my production site"
- "is my app safe", "did I leave anything exposed", "vibe-coded app security check", "did Cursor leak my keys", "check this Lovable/v0/Bolt app I just deployed"
- "check my security headers", "what's my SSL Labs grade", "TLS check", "https grade", "are my headers OK"
- "inspect my JS bundle", "are my API keys in the frontend", "find leaked keys in my bundle", "Supabase anon key exposed", "VITE\_ env vars in production", "REACT\_APP\_ in bundle"
- "is the token in localStorage", "JWT in localStorage", "session token leak"
- "test my login rate limit", "brute-force protection check", "lockout testing", "is my login rate-limited"
- "password reset enumeration", "username enumeration", "does my reset flow leak existing accounts"
- "production security audit", "runtime security check", "live security audit", "deployed app pentest"

When the user says "audit my app" without naming a URL **or** a source tree, ask which they mean and offer to run this skill *and* `security-vulnerability-scan` for full coverage. When in doubt, **trigger**. The cost of overtriggering is a redundant report; the cost of missing a real runtime leak is shipped credentials.

## Read/Write Contract

- **Read** — the live target (URLs the user authorizes), plus its publicly fetchable JS bundles. Optionally read the local project tree if the user is running this skill from inside the deployed app's repo.
- **Write** — exactly one location: `<project root>/audit/<YYYY-MM-DD>/live-audit.md` (or a timestamped variant if it already exists).
- **Never modify** — the live application's data, the user's source tree, configs, `.env*`, `.gitignore`, or anything outside `audit/`.
- **Never send** — payloads beyond the documented probes. Rate-limit and enumeration probes use clearly synthetic credentials (`live-audit-probe-<ts>@example.invalid`) against the documented endpoints only.
- **Network required** — most steps need outbound HTTP(S). In strict sandboxes, mark affected steps "Skipped — sandbox" in the report and continue with what works.

## Step 0 — Target Authorization

**This step is non-negotiable. Do not run any probe before completing it.**

Before Claude touches the target, confirm three things with the user. Be explicit; do not paraphrase the user's authorization into existence.

1. **Target URL.** Ask the user for the exact URL (one origin per run; multi-origin scans are sequential reruns). Normalize: ensure scheme present, no trailing path unless the auth flow lives under it. Display the normalized URL back and ask for confirmation.
2. **Authorization to test.** Ask the user one of:
   - "Do you own this target, or are you authorized to security-test it?"
   - If unsure: ask whether the target is hosted by the user (own infra / own Vercel/Netlify/Cloudflare account / own VPS), or whether they are a contracted/employed tester for the owning party.
   - If neither: **stop**. Do not run any step. Explain to the user that even passive header checks can violate terms of service against third-party targets, and that the standard remedy is to either (a) get written authorization or (b) point the skill at the user's own staging copy.
3. **Active-probe authorization (Steps 6 & 7).** Steps 6 (rate-limit) and 7 (enumeration) send real traffic at login / password-reset endpoints. Ask the user explicitly: "May I send ~15 bogus-credential login attempts and 2–4 password-reset probes against this target?" Three outcomes:
   - **Yes** → record the consent verbatim in the report (`Authorization: granted by <user> at <timestamp>`) and run Steps 6 and 7.
   - **No** → run Steps 1–5 only; mark Steps 6 and 7 as `Skipped — user declined active probes` in the report.
   - **Unclear / hedged** ("I think so", "should be fine") → treat as **No**. Surface the hedge and re-ask. Do not infer consent.

A finer point worth being firm on: a previous session's authorization does not carry over. If this skill is being re-invoked on a new URL, redo Step 0.

## Step 1 — Security Headers

What you're looking for: the cluster of HTTP response headers that prevent the most common drive-by attacks against modern browsers — XSS injection, clickjacking, mixed-content downgrades, MIME-sniff confusion, referrer leakage, and over-permissive browser API exposure. Most "vibe-coded" deploys ship with the framework defaults, which means most of these headers are missing.

### Probe

```bash
# Bash — primary
curl -sI -L --max-time 15 "$URL"
curl -sI -L --max-time 15 "$URL/login"   # if a login route exists
```

```powershell
# PowerShell equivalent (Windows)
$resp = Invoke-WebRequest -Uri $URL -Method Head -MaximumRedirection 5 -UseBasicParsing
$resp.Headers | Format-List
```

### Cross-check via securityheaders.com

```
WebFetch  https://securityheaders.com/?q=<URL>&followRedirects=on&hide=on
```

Parse the grade and the list of missing headers from the response.

### What to flag

| Header | Expected | Severity if missing |
|---|---|---|
| `Strict-Transport-Security` | `max-age=15552000; includeSubDomains` (or longer) | **High** on auth-bearing sites |
| `Content-Security-Policy` | non-empty, no `unsafe-inline` for scripts in 2025 stacks | **High** (Medium if a default-src is present but loose) |
| `X-Frame-Options` or CSP `frame-ancestors` | `DENY` / `SAMEORIGIN` / specific origins | **Medium** (clickjacking) |
| `X-Content-Type-Options` | `nosniff` | **Medium** |
| `Referrer-Policy` | `strict-origin-when-cross-origin` or stricter | **Low / Medium** |
| `Permissions-Policy` | present, non-empty | **Low** |
| `Cache-Control` on authenticated responses | `no-store` | **Medium** if absent on auth pages |
| `Set-Cookie` flags on session cookies | `Secure; HttpOnly; SameSite=Lax` (or Strict) | **High** if missing on auth |

A securityheaders.com grade below **B** is a finding in itself.

> **For full guidance (description, fixes, attack scenarios, mapped CWEs) read `references/01-security-headers.md`.**

## Step 2 — TLS / SSL

What you're looking for: outdated TLS versions, weak ciphers, expired or about-to-expire certificates, missing OCSP stapling, sites that respond on HTTP without redirecting, and any non-HTTPS API endpoints discovered in Step 5.

### Probe

```
WebFetch  https://api.ssllabs.com/api/v3/analyze?host=<HOST>&publish=off&fromCache=on&maxAge=24
```

Parse the returned JSON. The interesting fields:

- `status` — `READY` means usable result; `IN_PROGRESS` means re-fetch in 60s. Up to ~2 minutes for cold scans.
- `endpoints[*].grade` — `A+` / `A` / `A-` / `B` / `C` / `D` / `F` / `T` (trust issue) / `M` (mismatch).
- `endpoints[*].details.cert.notAfter` — cert expiry; flag if within 14 days.
- `endpoints[*].details.protocols[]` — flag presence of `TLS 1.0` / `TLS 1.1` / `SSL 3`.
- `endpoints[*].details.supportsRc4` / `.vulnBeast` / `.heartbleed` / `.poodle` / `.freak` / `.logjam` — any `true` is a finding.

### Cross-check HTTP → HTTPS redirect

```bash
curl -sI --max-time 10 "http://${HOST}/"
```

Expected: a `301`/`308` to `https://`. A `200` over plain HTTP is a finding even if HTTPS also works.

### What to flag

- Grade below **A** → finding (severity scales: A- Low, B Medium, C+ High, F Critical).
- Any TLS 1.0/1.1 / SSLv3 → **High**.
- Cert expiring within 14 days → **High**.
- HTTP responding `200` without redirect → **High**.
- Any non-HTTPS API endpoint discovered later in Step 5 → **Critical** if it carries auth.

> **For full guidance read `references/02-tls-ssl.md`.**

## Step 3 — Frontend Bundle Secret Search

What you're looking for: API keys, tokens, and configuration values that ended up baked into the production JS bundle because a build tool inlined a `VITE_*` / `REACT_APP_*` / `NEXT_PUBLIC_*` / `PUBLIC_*` env var the developer thought was private. **This is the single highest-yield check** on "vibe-coded" deploys — empirically, around 7 of every 8 Supabase-backed SPAs ship the anon key plus the project URL, which is by design for Supabase, but the same bundle frequently also contains a leaked `service_role` or unrelated provider keys.

### Probe

```bash
# Fetch index, extract bundle URLs, fetch each bundle
INDEX=$(curl -sL --max-time 15 "$URL")
echo "$INDEX" | grep -oE 'src="[^"]+\.js[^"]*"' | sed 's/src="//;s/"//' > /tmp/bundles.txt
echo "$INDEX" | grep -oE 'href="[^"]+\.css[^"]*"' | sed 's/href="//;s/"//' >> /tmp/bundles.txt
while read b; do
  full=$(echo "$b" | grep -q '^http' && echo "$b" || echo "${URL%/}/${b#/}")
  curl -sL --max-time 30 "$full" -o "/tmp/bundle_$(echo $b | tr '/' '_').js"
done < /tmp/bundles.txt
```

### Grep targets

Run all of these across the downloaded bundle files. Each is a separate Grep call.

| Pattern | What it catches | Severity |
|---|---|---|
| `sk-[A-Za-z0-9]{20,}` | OpenAI / Anthropic / Stripe-style secret key | **Critical** |
| `sk_live_[A-Za-z0-9]{24,}` | Stripe live key | **Critical** |
| `rk_live_[A-Za-z0-9]{24,}` | Stripe restricted live key | **Critical** |
| `AKIA[0-9A-Z]{16}` | AWS access key ID | **Critical** |
| `ghp_[A-Za-z0-9]{36}` | GitHub PAT classic | **Critical** |
| `github_pat_[A-Za-z0-9_]{82}` | GitHub fine-grained PAT | **Critical** |
| `xox[abprs]-[A-Za-z0-9-]{10,}` | Slack token | **Critical** |
| `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | JWT | **Triage** — see below |
| `service_role` | Supabase service-role key marker | **Critical** |
| `supabase_admin` / `SUPABASE_SERVICE_ROLE_KEY` | Same | **Critical** |
| `anon` near a Supabase URL | Supabase anon key (designed-public, but flag for confirmation) | **Informational** |
| `VITE_[A-Z_]+\s*[:=]\s*["'][^"']+["']` | Inlined Vite env var | **Triage** — read the var name |
| `REACT_APP_[A-Z_]+\s*[:=]\s*["'][^"']+["']` | Inlined CRA env var | **Triage** |
| `NEXT_PUBLIC_[A-Z_]+\s*[:=]\s*["'][^"']+["']` | Inlined Next public env var | **Triage** |
| `Bearer\s+[A-Za-z0-9._-]{20,}` | Hard-coded bearer | **Critical** |
| `(?i)apikey\s*[:=]\s*["'][^"']{16,}["']` | Generic `apiKey` assignment | **Critical** |
| `-----BEGIN (RSA \|EC \|OPENSSH \|DSA \|)PRIVATE KEY-----` | Private key material | **Critical** |
| Connection strings `(postgres\|mysql\|mongodb\|redis)://[^@/]+:[^@/]+@` | DB URLs with creds | **Critical** |

**JWT triage:** a JWT in the bundle is usually one of three things — (a) a *test* token (decode the payload, look for `exp` in the past or `iss: "test"`), (b) a *public* anon JWT (Supabase's anon key is a JWT — check the `role: anon` claim), or (c) an actual leaked session token. Decode the payload with base64 and read it; report accordingly.

**Supabase special case.** If you find `https://<id>.supabase.co` plus a JWT with `role: anon`:
- That's the **anon key**, which is *intended* to be public. Mark **Informational**, but also check whether the project has Row-Level Security enabled (you can't tell from outside — note this in the finding and ask the user to confirm).
- If you also find a JWT with `role: service_role` — that's **Critical**, regardless of where it appears.

### What to flag

Every match is a finding. Redact the middle of each value in the report (`sk-…REDACTED…1234`) — never the full secret.

> **For full guidance read `references/03-frontend-bundle-secrets.md`.**

## Step 4 — localStorage / sessionStorage Tokens

What you're looking for: session tokens, JWTs, refresh tokens, or PII the SPA writes to `localStorage` or `sessionStorage`. The web platform exposes these to any JS running on the page, which means an XSS anywhere on the origin (yours or a dependency's) becomes session theft. The 2025 best practice for browser auth is `HttpOnly; Secure; SameSite=Lax` cookies; storage-based tokens are a regression.

### Automated half — static signals from the bundle

Grep the downloaded bundles (Step 3) for these patterns:

| Pattern | Signal |
|---|---|
| `localStorage\.setItem\(['"]token` | token written to localStorage |
| `localStorage\.setItem\(['"](access|refresh|session|jwt|auth)` | auth-token write |
| `sessionStorage\.setItem\(['"]token` | same, session storage |
| `JSON\.parse\(localStorage\.getItem` | structured token in localStorage |
| `supabase\.auth.*localStorage` | Supabase default uses localStorage — confirm; recommend cookie storage |
| `localStorage\[['"](email\|phone\|ssn\|user\|profile)` | PII written to localStorage |

### Guided half — only with user cooperation

The static half catches most cases, but the definitive check requires an authenticated browser session. Walk the user through:

1. Open the live app in Chrome / Firefox / Edge.
2. Log in with a test account.
3. Open DevTools → **Application** → **Storage** → **Local Storage** → the app's origin.
4. Ask them to paste the **keys** (not values) they see.
5. For any key matching token/auth/session/jwt/user, ask the user to confirm whether the value is a JWT (starts with `eyJ`) or a structured object. **Do not ask for full values.**

### What to flag

- Any auth token in `localStorage` or `sessionStorage` → **High** (XSS-to-session-theft).
- Refresh token in storage with a long expiry → **High → Critical** depending on lifetime.
- PII (`email`, `name`, `phone`, `ssn`, etc.) in storage → **Medium**.
- A Supabase app using the default localStorage persistence with no XSS mitigations (CSP from Step 1) → **High**.

> **For full guidance read `references/04-localstorage-tokens.md`.**

## Step 5 — Network / Endpoint Inspection

What you're looking for: API endpoints embedded in the JS bundle that respond `200` with real data when called **without** authentication. Common shapes: a hard-coded REST/GraphQL URL with `/api/users`, `/api/orders`, `/rest/v1/<table>` (Supabase), `/graphql` with introspection enabled, or an internal admin endpoint accidentally on the public origin.

### Extract candidate endpoints

```bash
# Pull URL-like strings from every downloaded bundle
for f in /tmp/bundle_*.js; do
  grep -oE '"https?://[^"]+"' "$f"
  grep -oE '"/[a-zA-Z0-9_/.-]{3,}"' "$f"
done | sort -u > /tmp/endpoints.txt
```

Filter `/tmp/endpoints.txt` to:
- Anything containing `/api/`, `/rest/`, `/graphql`, `/v1/`, `/v2/`, `/admin`, `/internal`, `/debug`.
- Any absolute URL pointing at an origin different from the app's (a Supabase/Hasura/PostgREST host, an AWS API Gateway, a Vercel/Netlify function host).

### Probe each candidate

```bash
while read ep; do
  url=$(echo "$ep" | tr -d '"')
  full=$(echo "$url" | grep -q '^http' && echo "$url" || echo "${URL%/}${url}")
  printf "%-60s " "$url"
  curl -s -o /tmp/body -w "%{http_code} %{size_download}\n" --max-time 10 "$full"
done < /tmp/endpoints.txt
```

Inspect the response **body** for each `200` and `401`. A `200` with a non-empty data payload (JSON array of users, orders, etc.) is the finding.

### Supabase REST special case

If you found a Supabase URL in Step 3, probe directly:

```bash
ANON="<anon-key-from-step-3>"
curl -s "${SUPABASE_URL}/rest/v1/<table>?select=*" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  --max-time 10
```

A `200` returning rows confirms that RLS is **disabled** for `<table>` — a Critical finding. A `401`/`403` or `200 []` (empty due to RLS filtering) means RLS is enforced. Probe a few candidate tables: `users`, `profiles`, `orders`, `posts`, `messages`, `payments`. Do not enumerate exhaustively.

### What to flag

- Any endpoint returning user data unauthenticated → **Critical**.
- GraphQL introspection (`POST /graphql` with `{__schema{types{name}}}`) succeeding without auth → **High**.
- Endpoints that return different bodies for `existing-id` vs `bogus-id` while both unauthenticated → IDOR surface — **High**.
- Verbose error responses (stack traces, framework version, DB error text) on `404`/`500` → **Medium**.

> **For full guidance read `references/05-network-inspection.md`.**

## Step 6 — Auth Rate Limiting (Active Probe — Gated)

**Run only if Step 0 authorized active probes.** Otherwise: write `LIVE-NNN — Step 6 skipped (user declined active probes)` in the report and proceed to Step 7's gate.

What you're looking for: whether the login endpoint will accept unlimited credential-stuffing attempts. The most common failure on small / "vibe-coded" deploys is no protection at all — 1000 attempts per second is accepted.

### Cheap pre-check — read what the gateway already tells you

Before sending 15 attempts, send **one** request to any API endpoint on the target and inspect headers:

```bash
curl -sI --max-time 10 "$URL/api/" | grep -iE 'x-ratelimit|x-rate-limit|ratelimit-|retry-after|cf-ray|x-amzn-ratelimit'
```

If you see `x-ratelimit-limit`, `x-ratelimit-remaining`, `Cf-Ray` (Cloudflare), or `x-amzn-ratelimit-*`, the target has *some* form of throttling — you can predict what the full probe will show and adjust expectations. Note this in the report but **still run the 15-attempt probe** to confirm the limit applies to the login route specifically (gateway-wide limits often have generous budgets that wouldn't stop credential stuffing).

### Probe

```bash
EP="${URL%/}/api/auth/login"            # adapt to the real login path
PROBE_USER="live-audit-probe-$(date +%s)@example.invalid"
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" \
    --max-time 10 \
    -X POST "$EP" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${PROBE_USER}\",\"password\":\"definitely-not-the-password-${i}\"}"
  sleep 0.2
done
```

`example.invalid` is RFC-2606-reserved and cannot belong to a real user, so this never burns a real account. The 200ms gap is fast enough to detect missing limits and slow enough to avoid being itself a DoS.

### What to interpret

- All 15 responses return `401` with similar timing and no `Retry-After` / `429` → **High** finding: no rate limit detected.
- A `429 Too Many Requests` after N attempts → expected; record N and `Retry-After`.
- A `403` or temporary lockout after N attempts → expected; record N.
- A CAPTCHA challenge appearing in the response body after N attempts → expected; record N.
- Responses get measurably slower per attempt (exponential backoff) → expected (good defense).
- The endpoint starts returning `500` after N attempts → **Medium**: rate-limit fails open or the server is crashing.

### Important guardrails

- Use a clearly synthetic, RFC-reserved email. Never a real-looking one.
- 15 attempts is the cap. Do not increase "to see what happens" — escalating is what makes a probe an attack.
- Restrict to one login endpoint per run. Do not also hammer `/reset` and `/register` here.

> **For full guidance read `references/06-auth-rate-limiting.md`.**

## Step 7 — Password-Reset / Login Username Enumeration (Active Probe — Gated)

**Run only if Step 0 authorized active probes.** Otherwise skip and record as in Step 6.

What you're looking for: whether the response to `forgot-password` or `login` differs depending on whether the email is registered. Differences leak account existence and feed downstream credential-stuffing and phishing.

### Probe — choose two emails

- **Email A — guaranteed not registered:** `live-audit-probe-not-registered-$(date +%s)@example.invalid`.
- **Email B — guaranteed registered:** ask the user for one (a test account they control). If the user can't or won't supply one, use a second `.invalid` address — you'll only detect very loose enumeration, but document the limitation.

### Probe both endpoints

```bash
RESET_EP="${URL%/}/api/auth/forgot-password"
LOGIN_EP="${URL%/}/api/auth/login"

for email in "$EMAIL_A" "$EMAIL_B"; do
  echo "=== /forgot-password — $email ==="
  curl -s -i --max-time 10 -X POST "$RESET_EP" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\"}"
  echo "=== /login (wrong pw) — $email ==="
  curl -s -i --max-time 10 -X POST "$LOGIN_EP" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"wrong-pw-probe\"}"
done
```

### What to compare

Diff the two responses for each endpoint along five axes:

1. **Status code** — `200` vs `404`, `400` vs `200`.
2. **Response body text** — "If that email exists, we sent a link" (good) vs "No account with that email" (bad).
3. **Response time** — > 50ms difference is suspicious (DB lookup gate vs. early-return).
4. **Set-Cookie behavior** — only one variant sets a cookie.
5. **Headers** — `X-RateLimit-Remaining` only decremented for the existing user.

Any single axis differing is a finding.

### What to flag

- Different status codes between exists / not-exists → **High** (clear enumeration).
- Different body text → **High**.
- Consistent >50ms timing gap → **Medium**.
- Different `Set-Cookie` or rate-limit-header behavior → **Medium**.
- All five axes identical → ✅ — record as "no enumeration detected on tested endpoints."

> **For full guidance read `references/07-username-enumeration.md`.**

## Report Output

### Determine project root

Use `git rev-parse --show-toplevel` if inside a repo; otherwise the working directory. Treat that path as `<project_root>`.

### Choose the report path (ISO date; collision-safe)

```bash
DATE=$(date +%Y-%m-%d)
DIR="<project_root>/audit/${DATE}"
mkdir -p "$DIR"
FILE="${DIR}/live-audit.md"
if [ -e "$FILE" ]; then
  TIME=$(date +%H%M%S)
  FILE="${DIR}/live-audit-${TIME}.md"
fi
```

```powershell
$date = Get-Date -Format 'yyyy-MM-dd'
$dir  = Join-Path $projectRoot "audit\$date"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir 'live-audit.md'
if (Test-Path $file) {
  $time = Get-Date -Format 'HHmmss'
  $file = Join-Path $dir "live-audit-$time.md"
}
```

The first run of the day writes `live-audit.md`; subsequent same-day runs write `live-audit-HHMMSS.md`. Nothing is overwritten. The path mirrors `security-vulnerability-scan` so reports from both skills live side-by-side under `audit/<date>/`.

### Report structure

Write via the `Write` tool with this exact skeleton:

```markdown
# Live App Security Audit — <target URL> — <YYYY-MM-DD>

## Summary
- **Target:** <normalized URL>
- **Overall risk:** Critical | High | Medium | Low
- **Scan time:** <timestamp>
- **Authorization:** <"granted by <user> at <timestamp>" or "Steps 6–7 declined">
- **Scope run:** <list which of Steps 1–7 ran; which were skipped and why>
- **Findings:** N Critical / N High / N Medium / N Low / N Informational

## Findings

### Critical

#### LIVE-001 — <short title>
- **Step:** <1–7>
- **CWE:** CWE-NNN
- **Where:** <URL / bundle path / endpoint>
- **Description:** <what the issue is, in plain language>
- **Evidence:** <the redacted curl response, header line, or grep match — exact text>
- **Attack scenario:** <how an attacker uses this>
- **Remediation:** <how to fix; include framework-level config snippets where possible>
- **References:** [`references/0X-<file>.md`](references/0X-<file>.md)

### High
### Medium
### Low
### Informational

## Prioritized Remediation
1. <Critical-1 — one-line action>
2. <Critical-2 — one-line action>
3. <High-1 — one-line action>
…

## Steps Skipped
- <Step N — reason>

## Recommended Follow-ups
- **Static code review:** run `security-vulnerability-scan` against this app's source repo. It finds what this skill cannot (broken access control in code, injection sinks, supply-chain risk, secret leaks in commits).
- **DAST:** schedule an OWASP ZAP / Burp scan against the staging copy for deeper coverage of the request surface.
- **Secret rotation:** if any Critical secret was found in the bundle, rotate it **immediately** and audit downstream usage logs — assume it has been seen.
- **CSP rollout:** if Step 1 found no CSP, draft one in report-only mode first, then enforce.
```

### Severity rubric (copied verbatim from `security-vulnerability-scan`)

- **Critical** — unauthenticated remote code execution, public exfiltration of secrets/PII at scale, privilege escalation to admin from anonymous, complete authentication bypass.
- **High** — authenticated RCE, IDOR exposing other users' sensitive data, missing auth on sensitive endpoints, hard-coded credentials in a committed file or shipped bundle, weak password hashing, missing HSTS on auth-bearing sites, TLS ≤ 1.1.
- **Medium** — XSS in non-admin contexts, CSRF on state-changing endpoints, missing security headers, weak TLS configuration (B grade), dependency CVEs with known PoCs but limited blast radius, timing-based enumeration.
- **Low** — verbose error pages, missing rate limits without immediate abuse path, defense-in-depth gaps, missing audit logging on non-critical actions.
- **Informational** — designed-public values that warrant user confirmation (Supabase anon key, public app config) but are not findings on their own.

### After writing

1. Echo the absolute path of the report file back to the user.
2. Surface the top 3 highest-severity findings as a one-line preview each.
3. If any **Critical** secret was found in the bundle, lead the chat response with "**Rotate this credential immediately**" before anything else.
4. Suggest the user add `audit/` to `.gitignore` if not present. **Do not modify `.gitignore`** — surface only.

## Relationship with `security-vulnerability-scan`

This skill is the **runtime half**. `security-vulnerability-scan` is the **static half**. Different signals, different blind spots, both needed for a real review:

| Question | Where it's answered |
|---|---|
| "Is there a hard-coded API key in this file?" | `security-vulnerability-scan` |
| "Did the build inline `VITE_API_KEY` into the bundle?" | `live-app-security-audit` |
| "Does this route lack auth middleware?" | `security-vulnerability-scan` |
| "Does this deployed endpoint accept unauthenticated requests?" | `live-app-security-audit` |
| "Is bcrypt missing from password hashing?" | `security-vulnerability-scan` |
| "Does the login endpoint rate-limit?" | `live-app-security-audit` |
| "Is `DEBUG=True` in settings.py?" | `security-vulnerability-scan` |
| "Are stack traces being returned to the browser?" | `live-app-security-audit` |

Recommend running both when the user asks for "a security audit" without further qualification.

## Sandboxing Compatibility

- **Step 0** is a chat exchange — works anywhere.
- **Steps 1, 2, 3, 5, 6, 7** require outbound network. In a strict offline sandbox, mark each as `Skipped — sandbox (no outbound network)` and continue.
- **Step 4's static half** (greps over already-downloaded bundles) works offline if the bundles were fetched earlier. The DevTools half always needs the user.
- **WebFetch** is the preferred call for fetching pages and JSON APIs. Fall back to `curl` via `Bash` when you need response headers or non-text bodies.
- **ssllabs.com API** is rate-limited (about 1 scan per host per minute). If you get `429` or `503`, back off and retry once after 60 seconds; if still failing, mark Step 2 as "Skipped — SSL Labs unavailable" and use the local `curl` HTTPS check as a degraded substitute.

## Best Practices

- **Authorization isn't a formality.** A user saying "yeah go ahead" without reading what Steps 6 and 7 do is the right time to slow down and explain, not the right time to start probing.
- **One target per run.** Multi-origin sweeps are sequential reruns. Mixing origins in one report makes the findings hard to act on.
- **Cite exact evidence.** Every finding needs the curl response, the header line, the grep match, or the response-time diff. A finding without evidence is a guess.
- **Redact in the report.** Never write a full secret to the report. `sk-…REDACTED…1234` is enough to identify the leak without re-leaking it on disk.
- **Be conservative on severity.** When in doubt, mark Medium and let the user re-rank. Inflated Criticals destroy trust.
- **Re-fetch references on demand.** When triaging a specific step's finding, read the matching `references/0X-*.md` to ground the remediation language.
- **Do not pivot.** If a finding suggests another attack path (e.g., a leaked `service_role` key allowing arbitrary DB writes), **stop**, write the finding, recommend rotation, and ask the user. Do not exercise the new attack path even to confirm.

## Related Tools

- **`security-vulnerability-scan`** — the static counterpart in this repo. Run alongside.
- **OWASP ZAP / Burp Suite** — full DAST scanners. This skill is a fast triage; ZAP/Burp are the deep follow-up.
- **`sslyze`, `testssl.sh`** — local TLS scanners that work offline against a host you can reach.
- **`gitleaks` / `trufflehog`** — for the source-tree counterpart of Step 3.
- **`securityheaders.com`, `ssllabs.com/ssltest`** — the manual-UI versions of Steps 1 and 2.
