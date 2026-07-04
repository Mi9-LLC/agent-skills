# 05 — Network / Endpoint Inspection

**Mapped OWASP:** A01:2025 (Broken Access Control), A04:2025 (Cryptographic Failures — plaintext APIs), A06:2025 (Insecure Design — open endpoints).
**External references:**
- https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- https://graphql.org/learn/introspection/ — when to disable
- https://supabase.com/docs/guides/database/postgres/row-level-security — RLS basics

## Description

Every modern SPA hard-codes its API endpoints in the bundle. Some of those endpoints are intentionally public (`/api/health`, `/api/metadata`); some are designed to be authenticated but emit data unauthenticated because the developer forgot to apply middleware; some are designed to be admin-only but live on the same origin without route-level enforcement. The runtime check is: hit each endpoint without credentials and see what comes back.

The two big patterns this catches in 2025:

1. **Supabase / Hasura / PostgREST tables without Row-Level Security.** The pattern is "designed-public anon key calling a table that should have been gated by RLS." When RLS is off, the anon key reads/writes everything.
2. **Next.js / SvelteKit `/api/*` routes that forgot auth.** The framework gives a free public route by default; auth is opt-in middleware. A junior developer ships `/api/users/all` without thinking about it.

Both are runtime-visible only — the source review can find them with effort but the live request is unambiguous.

## Known limitation — opaque RPC backends (tRPC, gRPC-Web, GraphQL, JSON-RPC)

The "extract endpoint URLs from the bundle" approach is built for REST-style APIs where the client hard-codes path strings. Modern RPC frameworks defeat this by construction:

- **tRPC.** The client uses a typed proxy (`trpc.users.list.query()`) and only the base URL appears as a literal string (typically `/api/trpc` or `/trpc`). The actual procedure name is reached by JS property access through the proxy and won't appear as a quoted `/api/trpc/users.list` literal in the bundle. From the outside, an attacker (and this skill) can see *that* there is a tRPC backend but not *which procedures* exist.
- **GraphQL.** Operation names are in the query strings, not the URL. Discovery requires introspection (Step 5 already covers this) or watching real client traffic.
- **gRPC-Web.** Service / method names are in the request path, but the bundle references them through generated client stubs that minify the strings into single-letter identifiers.
- **JSON-RPC.** The method name is in the body, not the URL.

When the bundle reveals only an RPC base URL and no per-call paths, this step's findings will be sparse. Record that as a *limit of the external audit* in the report, not as "no endpoints found = nothing to worry about." Recommend an internal review of the procedure list, or a DAST run (ZAP/Burp) with a captured authenticated session that exercises the real client and records the procedures actually called.

## What to check

The executable probe commands live in SKILL.md Step 5; this reference covers interpretation, limitations (tRPC/GraphQL/gRPC opacity), and remediation depth.

### Endpoint extraction (from already-downloaded bundles in Step 3)

The extraction command lives in SKILL.md Step 5. Filter the resulting URLs to high-signal patterns:

- Paths containing: `/api/`, `/rest/`, `/v1/`, `/v2/`, `/graphql`, `/trpc`, `/admin`, `/internal`, `/debug`, `/private`, `/me`, `/users`, `/orders`, `/payments`.
- Different-origin URLs (other Supabase / Hasura / API Gateway / Edge Function hosts).

### Probes

The probe loop lives in SKILL.md Step 5. When probing manually, add `%{content_type}` to the `curl -w` format (`-w "%{http_code} %{size_download} %{content_type}\n"`) and send a `HEAD` rather than a `GET` on write-shaped paths for safety.

Inspect the body of each `200`. The finding shape:

- `200` + JSON array of objects with PII/IDs → **Critical**.
- `200` + JSON object with a single user's data → **Critical** (PII leak even singular).
- `200` + truthy data on a write-shaped path (POST/DELETE accessible via GET fallback) → **Critical**.
- `401`/`403` → expected behavior, log and move on.
- `404` with framework stack trace → **Medium** (info leak).
- `500` with stack trace → **Medium**.

### Supabase REST quick check (only if you found an anon key in Step 3)

The Supabase REST probe command and the candidate-table list (`users`, `profiles`, `orders`, `posts`, `messages`, `payments`, `tenants`, `files`) live in SKILL.md Step 5 — run that single-table `curl` against each listed table. Interpretation:

- `200 [{...}]` — table accessible to anon, RLS disabled or wide-open → **Critical**.
- `200 []` — table exists, RLS filtering to no rows → ✅.
- `401 "JWSError"` / `404` — table doesn't exist or anon key invalid → ✅ for that table.
- `400 "permission denied for table X"` — RLS-on, anon denied → ✅.

### GraphQL introspection

If a `/graphql` endpoint exists, probe introspection:

```bash
curl -s --max-time 10 -X POST "$URL/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query":"{__schema{types{name}}}"}'
```

A `200` with a `__schema` body → **High**. Introspection enabled in production gives an attacker the full schema, query, and mutation surface.

### IDOR sniff

If a candidate path looks like `/api/orders/{id}`, hit `/api/orders/1`, `/api/orders/2`, and `/api/orders/9999999`. Different bodies for the first two, `404` for the third → IDOR surface (but each individual hit might still 401 — record results either way).

## How to fix

- **Add auth middleware to every non-public route.** Frameworks default to public; you opt-in to public, not auth. Express: `app.use('/api', requireAuth)`. Next.js: `middleware.ts` matcher. SvelteKit: `hooks.server.ts`. FastAPI: `Depends(get_current_user)` on the router.
- **Enable RLS on every Supabase/PostgREST table.** "Enable RLS" without writing policies = nothing readable. Pair it with `CREATE POLICY ... USING (auth.uid() = user_id)`.
- **Disable GraphQL introspection in production.** Apollo Server: `introspection: process.env.NODE_ENV !== 'production'`. Hasura: lock down via permissions in production console.
- **Generic error responses.** No stack traces. Generic 500 message; structured logging keeps the detail server-side.
- **Object-level authorization.** When fetching by ID, scope to the session user in the *query*, not after — `findFirst({ where: { id, ownerId: session.userId }})`. The `where` does the access control; `findFirst(id)` then checking `if (resource.ownerId !== userId) throw` is a TOCTOU footgun.
- **Cache-Control on authenticated data.** `Cache-Control: no-store` on responses that depend on the session. Otherwise a shared CDN can hand one user's data to another.

## Why it matters / attack scenario

**Scenario 1 — `/api/users` returns the user table.** Built quickly: a "list users for the admin UI" endpoint with no auth. Bundle references it. Attacker `curl https://app.example.com/api/users` and gets a JSON array of every account, including emails. Two days later it's on a breach-tracking site. Fix is a single line of middleware on the route.

**Scenario 2 — Supabase, RLS off.** The developer didn't realize "Enable RLS" is per-table. The `payments` table has RLS on but `payment_methods` doesn't. Attacker with the anon key (from the bundle) reads every saved card-on-file last-four and ZIP. Fix is enabling RLS on `payment_methods` and writing a policy.

**Scenario 3 — GraphQL introspection live.** Production GraphQL with introspection on. Attacker pulls the full schema, sees there's a `users(filter: {})` query, finds it returns email and `password_hash` (because the developer forgot to omit it from the GraphQL type). Hashed passwords are now leaked at scale. Fix: disable introspection AND audit the schema for fields that shouldn't be exposed.

**Scenario 4 — IDOR on order detail.** `/api/orders/:id` checks auth but not ownership. Logged-in user with order #482 reads orders 1–10,000 and harvests other customers' invoices. Fix: scope the query to the session user.

## Mapped CWEs (selected)

- CWE-285 — Improper Authorization
- CWE-862 — Missing Authorization
- CWE-863 — Incorrect Authorization
- CWE-639 — Authorization Bypass Through User-Controlled Key (IDOR)
- CWE-200 — Exposure of Sensitive Information to an Unauthorized Actor
- CWE-359 — Exposure of Private Personal Information
- CWE-552 — Files or Directories Accessible to External Parties
- CWE-425 — Direct Request ('Forced Browsing')
- CWE-209 — Generation of Error Message Containing Sensitive Information
- CWE-668 — Exposure of Resource to Wrong Sphere
