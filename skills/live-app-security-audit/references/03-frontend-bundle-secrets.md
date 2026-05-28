# 03 — Frontend Bundle Secret Search

**Mapped OWASP:** A04:2025 (Cryptographic Failures — exposure), A07:2025 (Authentication Failures — leaked tokens), A02:2025 (Misconfig — inlined env vars).
**External references:**
- https://vitejs.dev/guide/env-and-mode — `VITE_` prefix exposes to client
- https://create-react-app.dev/docs/adding-custom-environment-variables — `REACT_APP_` same
- https://nextjs.org/docs/app/building-your-application/configuring/environment-variables — `NEXT_PUBLIC_`
- https://supabase.com/docs/guides/api/api-keys — anon vs service_role

## Description

Modern frontend build tools (Vite, CRA, Next.js, SvelteKit, Nuxt, Astro) inline environment variables matching a public-by-convention prefix (`VITE_`, `REACT_APP_`, `NEXT_PUBLIC_`, `PUBLIC_`) directly into the production JS bundle. The prefix is a "this is meant to be public" marker — but a developer racing to ship often (a) puts a secret behind the public prefix without realizing what the prefix means, or (b) uses a secret-bearing SDK on the client when the backend would have been correct.

The result is that the deployed `index-<hash>.js` contains the literal value of a real production credential. Anyone with a browser can `View Source` → `index-hash.js`, search for `sk-`, and read it. The fix is always the same: rotate the key, move the call server-side, and rebuild without the secret.

This step is the single highest-yield check in the skill. On "vibe-coded" deploys it's not unusual to find 2–4 secrets per bundle.

## What to check

Grep the downloaded bundle files for:

- Provider key prefixes: `sk-`, `pk_live_`, `sk_live_`, `rk_live_`, `AKIA*`, `ASIA*`, `ghp_*`, `gho_*`, `github_pat_*`, `xox[abprs]-*`, `glpat-*`, `Bearer\s+[A-Za-z0-9._-]{20,}`.
- JWTs: `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`. Decode the payload (`base64 -d` the middle segment) and read the claims.
- Supabase: any `https://*.supabase.co` URL, plus `service_role`, `supabase_admin`, `SUPABASE_SERVICE_ROLE_KEY` strings.
- Database URLs: `(postgres|mysql|mongodb|redis|rediss)://[^@/]+:[^@/]+@`.
- Generic high-entropy assignments: `(?i)(apikey|api_key|api-key|secret|password|token)\s*[:=]\s*["'][A-Za-z0-9+/=_-]{16,}["']`.
- Build-tool env-var assignments where the value is a credential, not a URL or flag:
  - `VITE_[A-Z0-9_]+\s*[:=]\s*["'][^"']{16,}["']`
  - `REACT_APP_[A-Z0-9_]+\s*[:=]\s*["'][^"']{16,}["']`
  - `NEXT_PUBLIC_[A-Z0-9_]+\s*[:=]\s*["'][^"']{16,}["']`
- Private key material: `-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----`.
- Webhook URLs with embedded secrets: `https://hooks\.slack\.com/services/[A-Z0-9/]+`, `https://discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+`.

## How to fix

- **Rotate first.** Any matched secret should be rotated at the provider before anything else. Assume it has been seen.
- **Move secret-bearing calls server-side.** The right architecture for any call needing a real secret is: browser → your backend (auth'd) → provider. The browser never sees the secret.
  - Next.js: API routes / server components. Use a non-`NEXT_PUBLIC_` env var.
  - Remix / SvelteKit / Nuxt: server-side `+server.ts` / `+page.server.ts` / `server/api/`.
  - SPA without a backend: add a thin proxy (Cloudflare Worker, Vercel Function, Supabase Edge Function) that holds the secret and authenticates the browser.
- **Use designed-public keys correctly.** Supabase anon key, Firebase web config, Stripe publishable key, Google Maps API key — these are intended to be public, but their safety depends on the *server-side* rules (RLS, Firestore rules, restricted referrers). Verify those rules; the anon key isn't a finding, but missing RLS is.
- **CI guard.** Add a build-time check that fails the build if the resulting bundle matches a denylist regex set. `gitleaks --no-git --source=dist/` works as a post-build step.
- **Rebuild and redeploy.** Rotating without rebuilding leaves the old bundle on the CDN and in user caches. Invalidate the CDN cache after redeploy.

## Why it matters / attack scenario

**Scenario 1 — Supabase service_role in the bundle.** A developer copy-pasted from a tutorial that used `service_role` on the client. The bundle ships with `eyJ...role=service_role...`. Any visitor can hit any table, read or write, bypassing every RLS policy. Worst-case is full database dump in minutes. The fix is rotating the key, moving the call server-side, and verifying RLS is on for every table.

**Scenario 2 — OpenAI key in a chat SPA.** The "vibe-coded" chat app calls OpenAI directly from the browser using `VITE_OPENAI_API_KEY`. The key is in `index-abc.js`. An attacker scrapes it, racks up $40,000 in usage on their own prompts before the bill alert fires. Server-side proxy with per-user rate limiting prevents this.

**Scenario 3 — Slack webhook in admin tooling.** An internal admin SPA posts to a Slack incoming webhook to notify ops. The webhook URL is in the bundle. Anyone with the URL can post arbitrary messages to that channel — useful for phishing internal users. Slack supports rotating webhook URLs; do it.

**Scenario 4 — Private SSH key in a build artifact.** A CI step accidentally copied a deploy key into the public folder. The bundle includes `-----BEGIN OPENSSH PRIVATE KEY-----` (compressed). Attacker uses it to push to the repo or to a downstream system trusting that key. Rotate the key, audit the repo for unauthorized commits, audit downstream systems for that key fingerprint.

## Mapped CWEs (selected)

- CWE-200 — Exposure of Sensitive Information to an Unauthorized Actor
- CWE-201 — Insertion of Sensitive Information Into Sent Data
- CWE-312 — Cleartext Storage of Sensitive Information
- CWE-538 — Insertion of Sensitive Information into Externally-Accessible File or Directory
- CWE-540 — Inclusion of Sensitive Information in Source Code
- CWE-798 — Use of Hard-coded Credentials
- CWE-547 — Use of Hard-coded, Security-Relevant Constants
- CWE-922 — Insecure Storage of Sensitive Information
- CWE-260 — Password in Configuration File
- CWE-256 — Plaintext Storage of a Password
