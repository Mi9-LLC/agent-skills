# Mi9 Skills

Mi9 LLC public catalog of [Claude Code](https://claude.com/claude-code) Agent Skills.

> **⚠️ Trust before you run.** A skill is instructions plus, sometimes, scripts that Claude Code executes and files it reads on your machine. Read a skill before installing it. Each section below states exactly what the skill touches (most are read-only; a few edit code, hit the network, or create a branch).

## How these skills work

**What a skill is.** A folder under `skills/<name>/` containing a `SKILL.md` — YAML metadata (`name`, a `description` that tells Claude *when* to use it, and the `allowed-tools` it's permitted) plus a Markdown playbook Claude follows. Some skills also ship `references/` docs or a `scripts/` helper.

**Install one** into the current project — it lands in your agent's skills directory (`.claude/skills/<name>/` for Claude Code):

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill <skill-name>
```

Add `-g` (`--global`) to install once at the **user level** instead, available in every project:

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill <skill-name> -g
```

Re-run either command anytime to update — it always pulls the current state of the branch; there are no versions to manage. The installer writes to whichever agent it detects; if a skill doesn't show up, confirm it landed under your Claude Code skills path and not a neutral `.agents/skills/` location.

**Two ways to run an installed skill:**
1. **Just talk.** Claude reads every installed skill's description and auto-activates the one that matches what you're doing. The **"Triggers on"** lines below are the phrases that fire each skill.
2. **Call it by name.** Type `/<skill-name>` to invoke it explicitly. A few skills are **manual-only** (they never auto-activate) and run *only* this way — each says so under **"How to run."**

**Check "Requirements" first.** Several skills need something in place before they work — a token, a production build, a deployed URL, the `gh` CLI, a clean git tree. If a skill seems to do nothing, it's almost always a missing requirement.

## Skills at a glance

| Skill | What it does |
|---|---|
| [`security-vulnerability-scan`](#security-vulnerability-scan) | [OWASP Top 10:2025](https://owasp.org/Top10/2025/) static scan of any codebase; writes `audit/<YYYY-MM-DD>/report.md`. Read-only on your source. |
| [`live-app-security-audit`](#live-app-security-audit) | Runtime audit of a deployed live URL — headers, TLS, bundle secrets, localStorage tokens, open endpoints, login rate-limit, account enumeration; writes `audit/<YYYY-MM-DD>/live-audit.md`. Authorization-gated. |
| [`anti-sycophancy`](#anti-sycophancy) | Behavioral mode for review/feedback/decision asks. Argues the opposing case first, names untested assumptions, refuses reflexive agreement. No file output. |
| [`update-dependencies`](#update-dependencies) | Research-first dependency updates for any JS/TS project (npm/pnpm/yarn/bun, single-package or monorepo). Reads real release notes, migrates code, verifies with quality gates. **Manual-only** (`/update-dependencies`). |
| [`convert-plan-to-feature`](#convert-plan-to-feature) | Decompose an approved plan into a folder of independently-trackable per-feature spec files — `REQUIREMENTS.md` index + one `features/NN - <name>.md` per unit of work, each with requirements, steps, interface contract, acceptance criteria, and dependencies. |
| [`new-feature`](#new-feature) | Investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written: researches the code + current best practices, then surfaces every ambiguous decision as categorized questions with `[REC]`-marked defaults, one category per message, until zero ambiguity remains. Design-only. |
| [`sonar-issue-check`](#sonar-issue-check) | Reads SonarCloud / self-hosted SonarQube issues for the current repo — by default the new-code issues on the current branch, or `--all` for the full backlog. Zero-dependency Node script; read-only against the Sonar API. |
| [`sonar-issue-fix`](#sonar-issue-fix) | Companion to `sonar-issue-check` that *fixes* the findings: triages by rule, applies behavior-preserving mechanical fixes plus a characterization-tests-first refactor for cognitive-complexity issues, and re-verifies with the project's gates. Never alters runtime/wire behavior. |
| [`trim-initial-bundle`](#trim-initial-bundle) | Find and defer vendor libraries that bloat a React + Vite app's initial JS load but are only needed behind lazy routes — shrinking first-load size, LCP, and TTI. Decides everything from the *built* `dist`, diagnoses the leak, fixes on approval, verifies against artifacts. Vite/Rollup/Rolldown only. |
| [`scaffold-claude`](#scaffold-claude) | Interview-driven `CLAUDE.md` author: asks one section at a time, captures only edge cases and tribal knowledge (never facts inferred from the manifest/tree/README), stubs what you skip, and writes a reviewable draft to `docs/scratchpad/CLAUDE.md`. No shell — Windows-clean. |
| [`systematic-debugging`](#systematic-debugging) | Root-cause-first debugging discipline: investigate before fixing, test one hypothesis at a time, fix the cause behind a failing test, and after 3 failed fixes stop and question the architecture. .NET + JS examples. |
| [`test-driven-development`](#test-driven-development) | **Opt-in** red-green-refactor discipline for work you choose to drive test-first — failing test → watch it fail → minimal code to pass → refactor. Triggers only on explicit TDD asks / new test-driven features, never on every edit. .NET + JS examples. |

---

## `security-vulnerability-scan`

**What it does.** OWASP Top 10:2025-aligned static vulnerability scanner. Reads your source tree — web frameworks, IaC, container configs, dependency lockfiles, secrets — and writes a structured, severity-ranked assessment to disk. Never runs your app.

**Requirements.** A source tree in the working directory. (If the directory is empty it asks for a GitHub URL and clones it with `gh` — that path needs network access.) The core static checks need nothing else. *Optional* dependency-auditors and secret-scanners (`npm audit`, `pip-audit`, `gitleaks`, `trivy`, `osv-scanner`, …) deepen the scan if they're installed, and are cleanly skipped if not. No tokens or credentials.

**How to run.** Auto-triggers on security/review asks, or run `/security-vulnerability-scan`. `allowed-tools: Read, Grep, Glob, Bash, Write`.

**Use it for.** PR reviews, periodic full-repo sweeps, onboarding to an unfamiliar codebase, or any "is there anything obvious" check. Designed to over-trigger rather than miss a real risk.

**Triggers on phrases like.** "review this code", "security review", "audit this app", "scan for vulnerabilities", "OWASP check", "find secrets", "harden security", "pentest this", "is this safe to ship".

**What it does not do.** Modify anything — never touches source, configs, dependencies, lockfiles, `.env*`, or `.gitignore`; the only write is under `audit/`. It surfaces a "add `audit/` to `.gitignore`" suggestion but won't edit `.gitignore` itself. The report body proposes no code edits.

**What it produces.** A Markdown report at `<project-root>/audit/<YYYY-MM-DD>/report.md` (a same-day re-run writes `report-HHMMSS.md` so nothing is overwritten) with findings ranked Critical / High / Medium / Low, OWASP A0X:2025 + CWE mappings, `file:line` citations, attack scenarios, remediations, and a prioritized fix list. **Read-only on your source tree.** It echoes the report path and previews the top 3 findings in chat.

**Example.**

```
You: security review this repo before I open the PR
→ Wrote audit/2026-06-30/report.md (12 findings). Top 3:
  SEC-001 (Critical) Hard-coded Stripe live key — src/config.ts:12 — A04:2025
  SEC-002 (High)     SQL built by string concat — src/db/orders.ts:88 — A03:2025
  SEC-003 (Medium)   Missing auth check on /admin/export — A01:2025
```

**Pairs with.** [`live-app-security-audit`](#live-app-security-audit) — the runtime counterpart. This skill reads the source; that one probes the deployed instance. Their reports land side-by-side under `audit/<date>/`.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill security-vulnerability-scan
```

**Full definition:** [`skills/security-vulnerability-scan/SKILL.md`](skills/security-vulnerability-scan/SKILL.md) (plus per-category reference docs under `references/`).

---

## `live-app-security-audit`

**What it does.** Runtime security audit of a deployed, live web app. Runs seven checks against the running target — security headers, TLS / SSL Labs grade, frontend-bundle secret search (including the Supabase anon-vs-`service_role` triage), `localStorage` / `sessionStorage` token exposure, unauthenticated endpoint inspection, login rate-limiting, and password-reset / login username enumeration — and writes a structured assessment.

**Requirements.** A deployed, reachable URL and outbound HTTPS. A mandatory **authorization gate (Step 0)**: you confirm the exact target and that you own or are authorized to test it — if you can't, the skill stops. The two *active* probes (rate-limit, enumeration) need your explicit consent, and the enumeration check works best if you supply a test-account email you control. It leans on `securityheaders.com` and the SSL Labs API when reachable and falls back to a local `curl` HTTPS check otherwise. No API token required.

**How to run.** Auto-triggers on live-audit asks (it'll ask for the URL if you don't give one), or run `/live-app-security-audit`. `allowed-tools: Read, Grep, Glob, Bash, WebFetch, Write`.

**Use it for.** Auditing a "vibe-coded" SPA you just shipped, checking that build-time env vars didn't leak into the bundle, sanity-checking production headers/TLS, and probing the most common runtime weaknesses on small / fast-shipped apps.

**Triggers on phrases like.** "audit my live site", "audit https://…", "are my API keys in the bundle", "Supabase anon key exposed", "check my security headers", "what's my SSL Labs grade", "JWT in localStorage", "test my login rate limit", "production security audit".

**What it does not do.** Touch the live app's data or your source tree. Send any payload beyond the documented probes. Skip Step 0 — a hedged "I think I own it" is treated as No, and a prior session's authorization does not carry over. It caps active probes (≤15 login attempts, one endpoint per run) and uses RFC-reserved `@example.invalid` emails so no real account is touched. On finding a new attack path it stops and recommends rotation rather than exploiting it.

**What it produces.** A Markdown report at `<project-root>/audit/<YYYY-MM-DD>/live-audit.md` (same-day re-runs append `-HHMMSS`), mirroring the static scan's path so both sit side-by-side under `audit/<date>/`. Findings are ranked Critical → Informational with CWE mappings, redacted evidence, attack scenarios, and remediations. **Read-only on your source and the live app.** A Critical bundle secret makes the reply lead with "Rotate this credential immediately."

**Example.**

```
You: audit my deployed app at https://myapp.example.com — did I leak any keys?
→ Step 0: confirm you own/are authorized to test this target, and OK active probes? (yes)
→ Wrote audit/2026-06-30/live-audit.md. Top findings:
  LIVE-001 (Critical) Supabase service_role key in assets/index-4f2a.js — rotate now
  LIVE-004 (High)     No Strict-Transport-Security header on /login
```

**Pairs with.** [`security-vulnerability-scan`](#security-vulnerability-scan) — run both for source + runtime coverage.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill live-app-security-audit
```

**Full definition:** [`skills/live-app-security-audit/SKILL.md`](skills/live-app-security-audit/SKILL.md) (plus per-check reference docs under `references/`).

---

## `anti-sycophancy`

**What it does.** Swaps Claude into critical-thinking-partner mode. Instead of agreeing reflexively or hedging, it argues the strongest opposing case first, names the load-bearing untested assumption, surfaces weaknesses before strengths, refuses to retreat without new evidence, and ends with a question worth sitting with. It also applies to *receiving code-review feedback* — verify a comment against the code before acting, no "great catch!", push back when a comment is wrong.

**Requirements.** None. Purely behavioral — no tools, no network, no files.

**How to run.** Auto-triggers on review / decision / feedback asks, or run `/anti-sycophancy`. Declares no `allowed-tools` (unrestricted), but it only shapes the reply — it reads nothing and writes nothing.

**Use it for.** Stress-testing your own judgment on a decision, plan, interpretation, or work you're about to commit to — the friction you'd want from a sharp colleague, not the validation from a friendly one.

**Triggers on phrases like.** "should I", "I'm planning to", "I've decided", "what do you think", "is this the right call", "review my plan", "am I seeing this right", plus explicit asks: "play devil's advocate", "be brutal", "punch holes", "challenge me". Stated confidence or stakeholder buy-in ("the team agrees") *amplifies* activation rather than skipping it.

**What it does not do.** Activate on objective questions with one knowable answer — syntax, config values, debugging, conversions, proofreading — even when phrased "is this correct?" Those need execution, not opposition. It won't manufacture a flaw to look thorough; if the idea holds up, it says so.

**What it produces.** Nothing on disk — a behavioral mode that shapes the conversation.

**Example.**

```
You: I'm going to move all our services to a monorepo this sprint — sounds right?
→ The strongest case against: your CI is the bottleneck, not the repo layout, and a
  monorepo multiplies CI minutes before it saves anyone time. Load-bearing assumption
  you haven't tested: that cross-service changes are frequent enough to pay for it.
  What would the last 20 PRs have looked like under a monorepo — actually faster, or just
  rebased more often?
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill anti-sycophancy
```

**Full definition:** [`skills/anti-sycophancy/SKILL.md`](skills/anti-sycophancy/SKILL.md).

---

## `update-dependencies`

**What it does.** Research-first dependency updater for any JavaScript/TypeScript project. Auto-detects the package manager and workspace layout, classifies outdated packages into safe (patch/minor) and major groups, bulk-applies the safe bumps behind a green gate, then handles each major individually — reading real release notes and changelogs first, migrating code for breaking changes, and reverting any group that won't go green.

**Requirements.** A JS/TS project with exactly one lockfile at the root (npm, pnpm, yarn Classic, yarn Berry, or bun) and that package manager on `PATH`. **git with a clean working tree** — it stops and asks you to stash/commit if the tree is dirty. Internet access (it researches every major before touching it). It respects the project's declared Node target (`engines.node` / `.nvmrc` / `.node-version`) and skips bumps that would require a newer Node. No prebuilt artifact needed — it runs whatever quality gates exist and skips the ones that don't.

**How to run.** **Manual-only** (`disable-model-invocation: true`) — it never auto-activates. Invoke it explicitly:

```
/update-dependencies                    # update everything outdated
/update-dependencies zod                # scope to one package (+ its lockstep ecosystem)
/update-dependencies react vitest       # scope to several
```

`allowed-tools: Bash, Read, Grep, Glob, Edit, Write, WebSearch, WebFetch, Agent`.

**Use it for.** Keeping a project current without reading every changelog yourself — periodic maintenance runs, pre-release sweeps, or a scoped single-package upgrade that needs safe migration.

**What it does not do.** Commit or push (changes stay on the work branch for you to review). Run on a dirty tree or with an ambiguous lockfile (it stops and asks). Make behavioral decisions on its own — a changed runtime default or a removed feature with several replacements pauses for you. Adopt a version needing a newer Node than the project targets.

**What it produces.** A safety branch `agent/update-dependencies/<timestamp>-<rand>` off the detected default branch, with the edits applied there, and an end-of-run chat report: **Updated / Migrated / Skipped-Reverted / Warnings / Branch**. Your working branch is never touched.

**Example.**

```
You: /update-dependencies
→ Branch agent/update-dependencies/20260630-a1c4 off the detected default branch (origin/main here).
  Safe pass: bumped 18 patch/minor (vite 7.0.2→7.0.6, …) — gates green.
  Majors: zod 3→4 migrated (2 files); react-router 6→7 skipped (needs Node 22, project targets 20).
  No commits made. Review with `git diff`.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill update-dependencies
```

**Full definition:** [`skills/update-dependencies/SKILL.md`](skills/update-dependencies/SKILL.md) (plus the per-PM command reference and lockstep-ecosystem table under `references/`).

---

## `convert-plan-to-feature`

**What it does.** Takes a finished, approved plan — from plan mode, a conversation, or a file under `docs/plans/` — and decomposes it into a folder of independently-trackable per-feature specs. The plan answered *what* and *why*; this skill produces the *per-unit-of-work execution surface* so a team (or a fleet of agents) can pick up one feature at a time without re-reading the whole plan.

**Requirements.** An approved/finished plan to convert (plan-mode output, a confirmed design in the conversation, or an existing file under `docs/plans/`). It writes under `docs/plans/` (or a top-level `plans/` fallback). No tokens or network.

**How to run.** Auto-triggers once a plan exists and you ask to decompose it, or run `/convert-plan-to-feature`. `allowed-tools: Bash, Read, Write, Glob, Grep, Agent`.

**Use it for.** Breaking a complex plan into separately assignable, reviewable, closeable units of work — feature tickets/specs a team or implementation agents can run in parallel.

**Triggers on phrases like.** "convert this plan into features", "split the plan up", "break this into per-feature files", "turn the plan into implementation specs", "make a feature breakdown", "decompose the plan", "create feature tickets from this plan".

**What it does not do.** Implement anything — it writes planning documents only and stops. It never writes at the `docs/plans/` root (everything goes inside the `<initiative>/` subfolder so concurrent efforts don't collide), and it leaves the source plan where it is.

**What it produces.**
- `docs/plans/<initiative>/REQUIREMENTS.md` — the index: context, blast radius, locked decisions, consolidated cross-cutting catalogs (wire-contract/enum tables, message types, error codes), deploy ordering, a feature table with suggested models, test strategy, and open questions.
- `docs/plans/<initiative>/features/NN - <Feature Name>.md` — one file per feature: requirement, a **Consumes/Produces interface contract**, ordered technical steps with real file paths (no placeholders), objectively checkable acceptance criteria, and dependency/risk notes.

**Example.**

```
You: break this approved rollback plan into feature files
→ docs/plans/stf-555-store-release-rollback/
   REQUIREMENTS.md
   features/01 - Contracts protocol v3 bump.md   (Produces: protocol v3 enums)
   features/02 - Store Agent backup engine.md     (Consumes: 01)
   features/03 - Store Agent rollback engine.md   (Consumes: 01, 02)
   … one slice each, numbered in deploy order.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

**Full definition:** [`skills/convert-plan-to-feature/SKILL.md`](skills/convert-plan-to-feature/SKILL.md) · **README:** [`skills/convert-plan-to-feature/README.md`](skills/convert-plan-to-feature/README.md).

---

## `new-feature`

**What it does.** An investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written. It researches first — the relevant code, the repo's `CLAUDE.md`/`AGENTS.md` invariants, prior plans and git history, and current best practices — then surfaces every ambiguous decision as categorized questions (A/B/C…) with `[REC]`-marked defaults and a short reason, asking one category per message and locking each answer with a one-line summary, until zero ambiguity is left.

**Requirements.** A codebase to investigate. Internet / Context7 access helps it ground recommendations in current best practices. Writes no files of its own.

**How to run.** Auto-triggers aggressively on feature / design / "is it possible to" asks, or run `/new-feature`. Declares no `allowed-tools` (unrestricted).

**Use it for.** Any non-trivial change with real design surface — new modules, protocol / contract changes, cross-service behavior, security-sensitive code, significant refactors. The `[REC]` markers keep it fast: skim, say "agreed with all recommended", and spend attention only on the decisions you'd actually change.

**Triggers on phrases like.** "new feature", "design / scope / plan a feature", "add capability", "analyze options", "think hard about", "before we implement", "what do you think about adding X", "is it possible to".

**What it does not do.** Write code — it's design-only and hands off to plan mode once decisions are locked. Trigger on tiny, obvious tasks ("rename this variable"). Skip the research and make you fill in what it could have found itself. Dump every question at once.

**What it produces.** No files — a locked set of design decisions carried into the planning phase.

**Example.**

```
You: I want to add SSO to the portal
→ (after reading the auth code) Question — Category A, identity protocol:
  A1. (a) SAML  (b) [REC] OIDC — your stack already has an OAuth2 client; least new surface
  A2. Session model: (a) [REC] reuse existing JWT cookie  (b) new server session store
  Confirm A1–A2.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill new-feature
```

**Full definition:** [`skills/new-feature/SKILL.md`](skills/new-feature/SKILL.md).

---

## `sonar-issue-check`

**What it does.** Runs a bundled, zero-dependency Node script that reads SonarCloud (or self-hosted SonarQube) issues for the repo you're in and prints a terminal summary — no Sonar web UI, MCP server, or extra install. By default it reports only the unresolved issues in the **new code** of the current branch; `--all` dumps the full backlog.

**Requirements.**
- **Node 18+** (uses the built-in `fetch`; zero npm dependencies).
- **A Sonar project that has already been scanned** — this skill *reads* results, it does not scan. Run it after pushing the branch or once a PR exists, so Sonar has analysed the code.
- **A token** in `SONAR_TOKEN` (env) or a local `.env` / `env/.env` (or `--env-file <path>`).
- **Project config** — `sonar-project.properties` at the repo root (project key / org / host), or a SonarLint binding in `.vscode/settings.json`; otherwise pass `--project`.
- Run inside a **git repo** (it reads the current branch), or pass `--branch`. For self-hosted SonarQube, point `--host` at it (the `organization` field is sent only for SonarCloud).

**How to run.** Auto-triggers on read-only Sonar asks, or run `/sonar-issue-check`. `allowed-tools: Bash, Read`. Useful flags: `--all` (full backlog), `--branch <name>`, `--pull-request <id>`, `--types BUG,VULNERABILITY,CODE_SMELL`, `--severities BLOCKER,…,INFO`, `--out <file>` (also write JSON), `--host <url>`, `--fail-on-issues` (exit 1 when matches found — for a gate).

**Use it for.** The pre-commit / pre-PR "did I just introduce a problem?" check, pulling findings for a specific branch or PR, filtering to bugs/vulnerabilities or high severities, or exporting JSON for a CI gate.

**Triggers on phrases like.** "check sonar before I push", "what did sonarcloud flag on my branch", "any new code smells", "pull the sonar bugs for PR 123", "did I introduce any new issues".

**What it does not do.** Run the Sonar scan itself (that's your CI pipeline). Modify the repo — it's read-only against the Sonar API and writes a file only with `--out`. Configure SonarLint, tokens, or quality-gate thresholds.

**What it produces.** A terminal summary — counts by severity and type, then one line per issue (`[SEVERITY/TYPE] file:line` + message + rule), worst first. A JSON file only when you pass `--out`. Exit code is `0` normally, `1` only with `--fail-on-issues` when matches exist, `2` on a setup error (missing token/config).

**Example.**

```
You: check sonar on my branch before I push
→ Found 3 issue(s):  By severity: CRITICAL=1, MAJOR=2
  [CRITICAL/CODE_SMELL] src/utils/parse.ts:88
     Refactor this function to reduce its Cognitive Complexity from 21 to 15.  (typescript:S3776)
  [MAJOR/BUG] src/api/orders.ts:42
     "await" on a non-Promise value.  (typescript:S4123)
```

**Pairs with.** [`sonar-issue-fix`](#sonar-issue-fix) — the writer that clears these.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill sonar-issue-check
```

**Full definition:** [`skills/sonar-issue-check/SKILL.md`](skills/sonar-issue-check/SKILL.md).

---

## `sonar-issue-fix`

**What it does.** The companion to `sonar-issue-check` that actually *resolves* the findings. It triages the new-code issues by rule into **mechanical** (localized, recipe-driven edits) and **structural** (cognitive-complexity refactors), applies behavior-identical fixes, and re-verifies against the project's own lint / type-check / test gates.

**Requirements.** A list of findings, each with a `file:line`, a message, and a **rule key** (e.g. `typescript:S3776`) — the rule key selects the fix. If `sonar-issue-check` is installed it fetches them for you (inheriting all of that skill's requirements — Node, `SONAR_TOKEN`, config); otherwise paste the list and it proceeds. It also needs the project's own quality gates to re-verify against (it discovers them from `package.json` / `CLAUDE.md` / CI config). Fix recipes are JS/TS today; the workflow is language-agnostic.

**How to run.** Auto-triggers on "fix the sonar issues" asks, or run `/sonar-issue-fix`. `allowed-tools: Read, Edit, Write, Bash, Grep, Glob`.

**Use it for.** Clearing the new-code smells/bugs on a branch before merge, making the quality gate green, or safely knocking out a specific cognitive-complexity warning.

**Triggers on phrases like.** "fix the sonar issues", "clear the sonarcloud findings on my branch", "resolve the new code smells before I merge", "make the quality gate green", "fix the cognitive complexity Sonar flagged".

**What it does not do.** Report-only inspection (that's `sonar-issue-check`). Change runtime or wire behavior — these are code-quality smells, not bug fixes; if a finding's correct fix is a real bug fix, it surfaces that to you instead of forcing a quality-pass edit. Commit or push unless you ask.

**What it produces.** Code edits applying per-rule recipes for mechanical findings. For structural (S3776) refactors on untested code it writes **characterization tests first** to snapshot current output, refactors until the snapshots are byte-identical, and keeps those tests as permanent regression coverage. It then re-runs the project's gates (e.g. `npm run lint`, `tsc --noEmit`, `vitest run`) and reports green. Ships `references/` (per-rule recipes + the complexity-refactor playbook).

**Example.**

```
You: fix the sonar issues on my branch before I merge
→ Fixed 4 mechanical (S6594 regex, S7773 Number.parseInt, S6606 ??, S1116 empty stmt).
  1 structural (S3776 in parse.ts): wrote 6 characterization snapshots (green), refactored,
  snapshots byte-identical. Gates: lint clean, tsc clean, vitest 41 passed. Not committed.
```

**Pairs with.** [`sonar-issue-check`](#sonar-issue-check) — install both: check finds the work (this skill calls its script), fix clears it.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill sonar-issue-fix
```

**Full definition:** [`skills/sonar-issue-fix/SKILL.md`](skills/sonar-issue-fix/SKILL.md) (plus per-rule fix recipes and the complexity-refactor playbook under `references/`).

---

## `trim-initial-bundle`

**What it does.** Finds heavy vendor libraries that ship on a React + Vite app's **initial JavaScript load** but are only needed behind a lazy route or click, and gets them off first load — shrinking download/parse cost, LCP, and TTI. It decides everything from the **built `dist`** (a zero-dependency analyzer ranks what's actually on first load), never from source guesses, then diagnoses *why* a library leaks and fixes it.

**Requirements.** A **React + Vite / Rollup / Rolldown** app (not Next.js, not raw Webpack). A **production build it can run** — the method works off `dist/`, so the build must succeed and produce `index.html` + `.js` chunks. **Node** for the bundled analyzer (`scripts/analyze-initial-load.mjs`, zero dependencies). git is used only at the verify step (clean-baseline comparison). *Windows note:* it builds from the project root with absolute paths — never `cd` into `dist` during a rebuild (Vite's `emptyOutDir` fails with `EPERM`).

**How to run.** Auto-triggers on bundle / first-load / "why is X in the main chunk" asks, or run `/trim-initial-bundle`. `allowed-tools: Bash, Read, Edit, Write, Grep, Glob`.

**Use it for.** "Our JS bundle is too big", "the app loads slowly", "why is recharts / monaco / cmdk in the main chunk", "lazy-load this heavy dependency", "improve LCP / TTI / Lighthouse on our Vite app".

**Triggers on phrases like.** "reduce / shrink / trim the bundle", "first-load / initial-load size", "why is `<library>` in the entry / index chunk", "defer / lazy-load `<heavy dep>`", "what's bloating my Vite build", "speed up first load".

**What it does not do.** Run on Next.js or raw Webpack — it says so and stops. Commit or push. Assert anything it hasn't grepped out of `dist`. Add a `manualChunks` entry to "isolate" a lib (it only *removes* one once proven). Edit before you approve the plan.

**What it produces.** First, a read-only ranked initial-load report plus a per-candidate leak diagnosis (eager import / un-tree-shaken barrel re-export / `manualChunks` hoist). Then a plan presented **for your approval** — library, size, leak mechanism with grep evidence, exact edits, projected brotli/gzip saving. On approval it applies one fix at a time, rebuilds, re-runs your gates, compares against a clean baseline, and reports before/after sizes. Ships `references/` (diagnosis + verification) and the analyzer under `scripts/`.

**Example.**

```
You: our Vite dashboard's first load is huge — why is recharts in the main chunk?
→ Built dist; analyzer: recharts-*.js = 142 kB br on the initial load.
  Leak: barrel `export { Chart } from './charts'` consumed by the always-mounted layout.
  Plan: drop the dead re-export + lazy-split <Chart>. Projected saving ~142 kB. Approve?
→ (after approval & rebuild) recharts now only in the lazy Reports chunk; initial JS 480→338 kB.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill trim-initial-bundle
```

**Full definition:** [`skills/trim-initial-bundle/SKILL.md`](skills/trim-initial-bundle/SKILL.md) (plus the diagnosis / verification references and the `analyze-initial-load.mjs` analyzer under `scripts/`).

---

## `scaffold-claude`

**What it does.** Interview-driven `CLAUDE.md` author. Instead of scraping `package.json` and the directory tree into a generic file, it walks eight sections one at a time — header, stack, commands, architecture, conventions, hard constraints, doc pointers, gotchas — asking for the *non-obvious* facts and the *reason* behind each, and writes only what you confirm. Its Iron Rule: never write a section from inference — ask, and leave a `<!-- TODO -->` stub when you skip.

**Requirements.** A project to document (it reads the manifest, tree, and README only to know *what to ask about*). No tokens, no network, no shell.

**How to run.** Auto-triggers on "scaffold/write/set up CLAUDE.md" asks, or run `/scaffold-claude`. `allowed-tools: Read, Glob, Grep, Write`.

**Use it for.** Bootstrapping a `CLAUDE.md` for a project that has none, or redoing a weak one from scratch. For a large repo, scaffold the root file, then run the same interview once per substantial subsystem to add nested `CLAUDE.md` files — Claude Code loads a nested file only when it touches that folder.

**Triggers on phrases like.** "scaffold CLAUDE.md", "write a CLAUDE.md", "set up CLAUDE.md", "create project instructions for Claude", "bootstrap CLAUDE.md".

**What it does not do.** Surgically edit an existing `CLAUDE.md` (just edit it directly). Infer or fabricate content to fill a section — an empty stub beats a confident guess. Write to the repo root — the draft lands in `docs/scratchpad/` for you to move. Run any shell command, so it's Windows-clean by construction.

**What it produces.** A reviewable draft at `docs/scratchpad/CLAUDE.md` — confirmed sections filled, skipped sections left as `<!-- TODO -->` stubs. Ships `references/` (an annotated one-shot example + the interview scripts) and a `templates/` stub.

**Example.**

```
You: set up a CLAUDE.md for this project
→ Saw a .NET solution + a React/Vite app, no existing CLAUDE.md. I won't assume — I'll ask.
  Section 1/8 — Header: one or two sentences, what is this project and what does it optimize for?
  (say "skip" and I'll stub it)
→ … (8 sections later) Wrote docs/scratchpad/CLAUDE.md — 5 filled, 3 stubbed. Move it to the
  repo root when you're happy with it.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill scaffold-claude
```

**Full definition:** [`skills/scaffold-claude/SKILL.md`](skills/scaffold-claude/SKILL.md) (plus interview scripts + an annotated example under `references/`, a stub under `templates/`). Adapted from [`ragnar-pwninskjold/tech-snacks`](https://github.com/ragnar-pwninskjold/tech-snacks) (MIT).

---

## `systematic-debugging`

**What it does.** Enforces a four-phase debugging discipline instead of guess-and-check: (1) root-cause investigation, (2) pattern / context analysis, (3) one tested hypothesis at a time, (4) fix the cause behind a failing test. Hard rules: no fix before root-cause investigation, and after three failed fixes, stop and question the architecture rather than trying a fourth.

**Requirements.** A failure you can reproduce, and a way to run it — your test runner / build / repro command (it uses `dotnet test`, `npm test`, etc.). git helps for the "what recently changed" step. No tokens or network.

**How to run.** Auto-triggers on debugging asks, or run `/systematic-debugging`. `allowed-tools: Read, Grep, Glob, Bash, Edit`.

**Use it for.** Any failure you're about to fix — a bug, a failing or flaky test, a regression, a build break, a crash, "works locally but not in CI", or a repeated failed-fix loop. Most valuable exactly when it's tempting to skip: under time pressure and when a fix "looks obvious."

**Triggers on phrases like.** "why is this broken", "this test is flaky", "my fix didn't work", "this keeps failing", "it works locally but not in CI", or a pasted stack trace. Not for trivial self-evident edits (a typo, a rename).

**What it does not do.** Propose a fix before the root cause is found. Bundle a refactor or "while I'm here" cleanup into the fix. Keep trying on the same theory — three failed fixes means the design is the suspect, and it stops to raise that with you.

**What it produces.** No artifacts — a debugging discipline that ends in a root-cause fix behind a failing test (red before, green after). Ships `references/` (backward root-cause tracing, defense-in-depth validation, condition-based waiting for flaky tests).

**Example.**

```
You: this test passes locally but fails in CI
→ Phase 1: read the full error, reproduce, check the recent diff, instrument the CI/build/test
  boundary to see which layer differs (not guess). Found: CI sets TZ=UTC; the test asserts a
  local-time string. One fix at the root (format with an explicit timezone), behind a test that
  fails before and passes after.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill systematic-debugging
```

**Full definition:** [`skills/systematic-debugging/SKILL.md`](skills/systematic-debugging/SKILL.md) (plus the three technique references). Adapted from [`obra/superpowers`](https://github.com/obra/superpowers) (MIT) — decoupled, Windows-clean, with .NET/xUnit + TS/Vitest examples.

---

## `test-driven-development`

**What it does.** Guides the red-green-refactor cycle for a piece of work you've chosen to build test-first: write one failing test, watch it fail *for the right reason*, write the minimal code to pass, then refactor — and pushes back on the rationalizations for skipping that order.

**Requirements.** A test framework set up for your stack so RED/GREEN can actually run — xUnit / `dotnet test` (C#) or Vitest / `npm test` (TS/JS). You opt in for the specific piece of work.

**How to run.** **Opt-in** — it auto-triggers *only* on an explicit TDD ask or a new feature you say you want built test-first; or run `/test-driven-development`. `allowed-tools: Read, Write, Edit, Bash, Grep, Glob`.

**Use it for.** A new feature, module, or component you want built test-driven. It's a deliberate methodology you opt into — not a global mandate on all your code.

**Triggers on phrases like.** "let's TDD this", "build X test-first", "write the tests first", "red-green-refactor", "implement Y test-driven". Deliberately does **not** trigger on ordinary work — every edit, routine bug fix, small tweak, refactor of existing code, or "add tests after the fact."

**What it does not do.** Impose itself on changes you didn't opt into. Delete your existing code to "redo it properly" unless you ask. Let a test pass on the first run without you having watched it fail (that proves nothing).

**What it produces.** No artifacts — a disciplined test-first workflow with a verification checklist. Ships `references/testing-anti-patterns.md` (asserting on mock behavior, test-only methods on production classes, incomplete mocks).

**Example.**

```
You: let's build the retry helper test-first
→ RED: wrote a Vitest test "retries until the third attempt succeeds"; ran it — fails (no retry yet).
  GREEN: minimal retry loop — test passes, suite green.
  REFACTOR: extracted the backoff; re-ran — still green. Next behavior?
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill test-driven-development
```

**Full definition:** [`skills/test-driven-development/SKILL.md`](skills/test-driven-development/SKILL.md) (plus the anti-patterns reference). Adapted from [`obra/superpowers`](https://github.com/obra/superpowers) (MIT) — reframed as opt-in, decoupled, with .NET/xUnit + TS/Vitest examples.

---

## Contributing

To add or modify a skill:

1. Create or edit a directory under `skills/<skill-name>/` containing a `SKILL.md` (YAML frontmatter with `name` + `description` + optional `allowed-tools`, plus a Markdown body). Long-form reference docs go under `skills/<skill-name>/references/`; helper scripts under `scripts/`. If the skill ships a standalone `skills/<skill-name>/README.md`, keep it in sync with the `SKILL.md` — divergent copies silently mislead users.
2. Add a row to the **Skills at a glance** table and a per-skill section to this README, mirroring the template every section above uses: *what it does*, *requirements*, *how to run*, *use it for*, *triggers on*, *what it does not do*, *what it produces*, *example*, *pairs with* (if any), *install*, *full definition*. Consumers discover skills from this README — an undocumented or vaguely-documented skill is effectively unshipped, and generates support questions.
3. Keep the table-row count, the `## ` section count, and the `skills/` directory count in agreement.
4. Open a PR against `main`. Teammates pick up the new version on their next `npx skills add … --skill <name>`.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at. Tag releases (e.g. `v1.0.0`) only when you want to offer a `--ref`-able pin.

## License

[MIT](LICENSE).

## Documentation

For more on Claude Code Agent Skills, see the [official Anthropic documentation](https://code.claude.com/docs/en/skills) and [`anthropics/skills`](https://github.com/anthropics/skills) for the canonical layout.
