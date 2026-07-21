# Mi9 Skills

Mi9 LLC public catalog of [Claude Code](https://claude.com/claude-code) Agent Skills.

> **⚠️ Trust before you run.** A skill is instructions plus, sometimes, scripts that Claude Code executes and files it reads on your machine. Read a skill before installing it. Each section below states exactly what the skill touches (most are read-only; a few edit code, hit the network, or create a branch).

## How these skills work

**What a skill is.** A folder under `skills/<name>/` containing a `SKILL.md` — YAML metadata (`name`, a `description` that tells Claude *when* to use it, and an optional `allowed-tools` list) plus a Markdown playbook Claude follows. `allowed-tools` only pre-approves those tools (skips permission prompts) — it doesn't restrict what the skill can use. A skill that promises restraint (e.g. read-only, no shell) declares `disallowed-tools` instead, which removes those tools from Claude's pool while the skill is active — the restriction clears on your next message, so it guards the activating turn rather than a whole multi-turn flow (a permanent block needs a permission deny rule). Some skills also ship `references/` docs or a `scripts/` helper.

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
| [`anti-sycophancy`](#anti-sycophancy) | Behavioral mode for review/feedback/decision asks. Argues the opposing case first, names untested assumptions, refuses reflexive agreement. Produces no files or reports. |
| [`update-dependencies`](#update-dependencies) | Research-first dependency updates for any JS/TS project (npm/pnpm/yarn/bun, single-package or monorepo). Reads real release notes, migrates code, verifies with quality gates. **Manual-only** (`/update-dependencies`). |
| [`convert-plan-to-feature`](#convert-plan-to-feature) | Decompose an approved plan into a folder of independently-trackable per-feature spec files — `REQUIREMENTS.md` index + one `features/NN - <name>.md` per unit of work, each with requirements, steps, interface contract, acceptance criteria, and dependencies. |
| [`new-feature`](#new-feature) | Investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written: researches the code + current best practices, then surfaces every ambiguous decision as categorized questions with `[REC]`-marked defaults, one category per message, until zero ambiguity remains. Design-only. |
| [`sonar-issue-check`](#sonar-issue-check) | Reads SonarCloud / self-hosted SonarQube issues for the current repo's analyzed branch or PR — by default just the new-code issues, or `--all` for the full unresolved backlog on that branch/PR. Zero-dependency Node script; read-only against the Sonar API. |
| [`sonar-issue-fix`](#sonar-issue-fix) | Companion to `sonar-issue-check` that *fixes* the findings: triages by rule, applies behavior-preserving mechanical fixes plus a characterization-tests-first refactor for cognitive-complexity issues, and re-verifies with the project's gates. Never alters runtime/wire behavior. |
| [`trim-initial-bundle`](#trim-initial-bundle) | Find and defer vendor libraries that bloat a React + Vite app's initial JS load but are only needed behind lazy routes — shrinking first-load size, LCP, and TTI. Decides everything from the *built* `dist`, diagnoses the leak, fixes on approval, verifies against artifacts. Vite/Rollup/Rolldown only. |
| [`scaffold-claude`](#scaffold-claude) | Interview-driven `CLAUDE.md` author: asks one section at a time, captures only edge cases and tribal knowledge (never facts inferred from the manifest/tree/README), stubs what you skip, and writes a reviewable draft to `docs/scratchpad/CLAUDE.md`. No shell — Windows-clean. |
| [`systematic-debugging`](#systematic-debugging) | Root-cause-first debugging discipline: investigate before fixing, test one hypothesis at a time, fix the cause behind a failing test, and after 3 failed fixes stop and question the architecture. .NET + JS examples. |
| [`test-driven-development`](#test-driven-development) | **Opt-in** red-green-refactor discipline for work you choose to drive test-first — failing test → watch it fail → minimal code to pass → refactor. Triggers only on explicit TDD asks / new test-driven features, never on every edit. .NET + JS examples. |
| [`session-handoff`](#session-handoff) | Create and resume handoff documents for transferring work between AI agent sessions — bundled Python scripts scaffold the document, validate it (secret scan + completeness score), and grade staleness before a resume. Writes under `.claude/handoffs/`. |
| [`retro`](#retro) | Data-grounded engineering retrospective from the current repo's git history — commits, sessions, churn, test ratio, focus score, AI-assisted share — by default the last 7 days, or `--compare` for a trend against the prior window. Zero-dependency Node script; every number traces to its JSON output, never estimated. |
| [`verify-frontend-change`](#verify-frontend-change) | Never calls a UI change done from a clean edit alone — starts the dev server, opens the affected page in Chrome (via the Chrome DevTools MCP server), interacts with the change, gates on zero new console errors, records a performance trace. Any failure is fixed and the loop rerun from the top. |
| [`health`](#health) | Local quality-gate dashboard for the current repo — runs the project's own typecheck/lint/test/dead-code/shell-lint gates, scores each 0–10 against a weighted rubric, and computes a composite; `--save` tracks the trend against repo history. Zero-dependency Node script; every number traces to its JSON output, never estimated. |
| [`plan-eng-review`](#plan-eng-review) | Pre-implementation review gate for a *written* implementation plan — scope challenge, what-already-exists reuse check, four review dimensions (architecture / code quality / tests / performance), evidence-gated findings, then a verdict plus a `## ENG REVIEW REPORT` spliced into the plan file (terminal-only when the plan has no file on disk). Never implements the plan. |
| [`document-generate`](#document-generate) | Writes Diataxis documentation files (tutorial / how-to / reference / explanation) for a named feature, module, or project — end-to-end codebase archaeology first, a partition plan approved before any file is written, every example executed, traced, or labeled illustrative. Never edits `CLAUDE.md`/`AGENTS.md`, never commits. |
| [`stdlib-first`](#stdlib-first) | Reuse-before-build ladder for new TypeScript/Node and C#/.NET code — built-in/standard library first, then (C#) first-party `Microsoft.Extensions.*`, then a library the project already uses, custom code last; precise types, specific error classes, doc comments. Asks before adding any dependency. Behavioral only — produces no files. |
| [`repo-change-summary`](#repo-change-summary) | Deterministic per-month change totals for a git repo across **all** branches — lines added/deleted, total churn, distinct files, file-touches, commits, PRs merged, authors — as a Markdown table plus a styled HTML report; a companion multi-repo mode rolls up a named group of repos into one combined report. Bundled POSIX-shell scripts; each commit counted once, merges excluded. Optionally emails the report as a PDF attachment, preview-first. |

---

## `security-vulnerability-scan`

**What it does.** OWASP Top 10:2025-aligned static vulnerability scanner. Reads your source tree — web frameworks, IaC, container configs, dependency lockfiles, secrets — and writes a structured, severity-ranked assessment to disk. Never runs your app.

**Requirements.** A source tree in the working directory. (If the directory is empty it asks for a GitHub URL and clones it with `gh` — that path needs network access.) The core static checks need nothing else. *Optional* dependency-auditors and secret-scanners (`npm audit`, `pip-audit`, `gitleaks`, `trivy`, `osv-scanner`, …) deepen the scan if they're installed, and are cleanly skipped if not. No tokens or credentials.

**How to run.** Auto-triggers on security/review asks, or run `/security-vulnerability-scan`. `allowed-tools: Read, Grep, Glob, Bash, Write`.

**Use it for.** PR reviews, periodic full-repo sweeps, onboarding to an unfamiliar codebase, or any "is there anything obvious" check. Designed to over-trigger rather than miss a real risk.

**Triggers on phrases like.** "review this code", "security review", "audit this app", "scan for vulnerabilities", "OWASP check", "find secrets", "harden security", "pentest this", "is this safe to ship".

**What it does not do.** Modify anything — never touches source, configs, dependencies, lockfiles, `.env*`, or `.gitignore`; the only write is under `audit/`. It declares `disallowed-tools: Edit, NotebookEdit`, which drops those tools while the skill is active (a per-turn guard — the restriction clears on your next message). It surfaces a "add `audit/` to `.gitignore`" suggestion but won't edit `.gitignore` itself. The report body proposes no code edits.

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

**How to run.** Auto-triggers on live-audit asks (it'll ask for the URL if you don't give one), or run `/live-app-security-audit`. `allowed-tools: Read, Grep, Bash, WebFetch, Write`.

**Use it for.** Auditing a "vibe-coded" SPA you just shipped, checking that build-time env vars didn't leak into the bundle, sanity-checking production headers/TLS, and probing the most common runtime weaknesses on small / fast-shipped apps.

**Triggers on phrases like.** "audit my live site", "audit https://…", "are my API keys in the bundle", "Supabase anon key exposed", "check my security headers", "what's my SSL Labs grade", "JWT in localStorage", "test my login rate limit", "production security audit".

**What it does not do.** Touch the live app's data or your source tree — it declares `disallowed-tools: Edit, NotebookEdit` to drop those tools while the skill is active (a per-turn guard; the restriction clears on your next message). Send any payload beyond the documented probes. Skip Step 0 — a hedged "I think I own it" is treated as No, and a prior session's authorization does not carry over. It caps active probes (≤15 login attempts, one endpoint per run) and uses RFC-reserved `@example.invalid` emails so no real account is touched. On finding a new attack path it stops and recommends rotation rather than exploiting it.

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

**Requirements.** None. Purely behavioral — changes only how Claude argues.

**How to run.** Auto-triggers on review / decision / feedback asks, or run `/anti-sycophancy`. Declares no `allowed-tools` (unrestricted), but it only shapes the reply.

**Use it for.** Stress-testing your own judgment on a decision, plan, interpretation, or work you're about to commit to — the friction you'd want from a sharp colleague, not the validation from a friendly one.

**Triggers on phrases like.** "should I", "I'm planning to", "I've decided", "what do you think", "is this the right call", "review my plan", "am I seeing this right", plus explicit asks: "play devil's advocate", "be brutal", "punch holes", "challenge me". Stated confidence or stakeholder buy-in ("the team agrees") *amplifies* activation rather than skipping it.

**What it does not do.** Activate on objective questions with one knowable answer — syntax, config values, debugging, conversions, proofreading — even when phrased "is this correct?" Those need execution, not opposition. It won't manufacture a flaw to look thorough; if the idea holds up, it says so. It also does not run the structured pre-implementation review of a written implementation plan — that is [`plan-eng-review`](#plan-eng-review)'s job.

**What it produces.** No files or reports — a behavioral mode that changes only how Claude argues.

**Example.**

```
You: I'm going to move all our services to a monorepo this sprint — sounds right?
→ The strongest case against: your CI is the bottleneck, not the repo layout, and a
  monorepo multiplies CI minutes before it saves anyone time. Load-bearing assumption
  you haven't tested: that cross-service changes are frequent enough to pay for it.
  What would the last 20 PRs have looked like under a monorepo — actually faster, or just
  rebased more often?
```

**Pairs with.** [`plan-eng-review`](#plan-eng-review) — anti-sycophancy supplies the skepticism *stance* for any decision or idea; plan-eng-review is the structured *gate* for a written implementation plan.

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

**Full definition:** [`skills/update-dependencies/SKILL.md`](skills/update-dependencies/SKILL.md) · **README:** [`skills/update-dependencies/README.md`](skills/update-dependencies/README.md) (plus the per-PM command reference and lockstep-ecosystem table under `references/`).

---

## `convert-plan-to-feature`

**What it does.** Takes a finished, approved plan — from plan mode, a conversation, or a file under `docs/plans/` — and decomposes it into a folder of independently-trackable per-feature specs. The plan answered *what* and *why*; this skill produces the *per-unit-of-work execution surface* so a team (or a fleet of agents) can pick up one feature at a time without re-reading the whole plan.

**Requirements.** An approved/finished plan to convert (plan-mode output, a confirmed design in the conversation, or an existing file under `docs/plans/`). It writes under `docs/plans/` (or a top-level `plans/` fallback). No tokens or network.

**How to run.** Auto-triggers once a plan exists and you ask to decompose it, or run `/convert-plan-to-feature`. `allowed-tools: Read, Write, Glob, Grep`.

**Use it for.** Breaking a complex plan into separately assignable, reviewable, closeable units of work — feature tickets/specs a team or implementation agents can run in parallel.

**Triggers on phrases like.** "convert this plan into features", "split the plan up", "break this into per-feature files", "turn the plan into implementation specs", "make a feature breakdown", "decompose the plan", "create feature tickets from this plan".

**What it does not do.** Implement anything — it writes planning documents only and stops. It declares `disallowed-tools: Edit, NotebookEdit`, which drops those tools while the skill is active (a per-turn guard — the restriction clears on your next message). It never writes at the `docs/plans/` root (everything goes inside the `<initiative>/` subfolder so concurrent efforts don't collide), and it leaves the source plan where it is.

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

**Pairs with.** [`plan-eng-review`](#plan-eng-review) — gate the plan before decomposing it.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

**Full definition:** [`skills/convert-plan-to-feature/SKILL.md`](skills/convert-plan-to-feature/SKILL.md) · **README:** [`skills/convert-plan-to-feature/README.md`](skills/convert-plan-to-feature/README.md).

---

## `new-feature`

**What it does.** An investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written. It researches first — the relevant code, the repo's `CLAUDE.md`/`AGENTS.md` invariants, prior plans and git history, and current best practices — then surfaces every ambiguous decision as categorized questions (A/B/C…) with `[REC]`-marked defaults and a short reason, asking one category per message and locking each answer with a one-line summary, until zero ambiguity is left.

**Requirements.** A codebase to investigate. Internet / Context7 access helps it ground recommendations in current best practices. Writes no files of its own.

**How to run.** Auto-triggers aggressively on feature / design / "is it possible to" asks, or run `/new-feature`. Declares `disallowed-tools: Edit, Write, NotebookEdit` (drops those tools while active; a per-turn guard that clears on the next message) — Bash stays available for the git-history research step.

**Use it for.** Any non-trivial change with real design surface — new modules, protocol / contract changes, cross-service behavior, security-sensitive code, significant refactors. The `[REC]` markers keep it fast: skim, say "agreed with all recommended", and spend attention only on the decisions you'd actually change.

**Triggers on phrases like.** "new feature", "design / scope / plan a feature", "add capability", "analyze options", "think hard about", "investigate", "before we implement", "what do you think about adding X", "is it possible to".

**What it does not do.** Write code — it's design-only (enforced by the `disallowed-tools` guard above) and hands off to plan mode once decisions are locked. Trigger on tiny, obvious tasks ("rename this variable"). Skip the research and make you fill in what it could have found itself. Dump every question at once.

**What it produces.** No files — a locked set of design decisions carried into the planning phase.

**Example.**

```
You: I want to add SSO to the portal
→ (after reading the auth code) Question — Category A, identity protocol:
  A1. (a) SAML  (b) [REC] OIDC — your stack already has an OAuth2 client; least new surface
  A2. Session model: (a) [REC] reuse existing JWT cookie  (b) new server session store
  Confirm A1–A2.
```

**Pairs with.** [`document-generate`](#document-generate) — this skill settles the design decisions before a line of code is written; that one documents the feature once it exists. Also [`plan-eng-review`](#plan-eng-review) — settle the design here, draft the plan, then gate the resulting plan before building.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill new-feature
```

**Full definition:** [`skills/new-feature/SKILL.md`](skills/new-feature/SKILL.md) (plus longer worked examples under `references/`).

---

## `sonar-issue-check`

**What it does.** Runs a bundled, zero-dependency Node script that reads SonarCloud (or self-hosted SonarQube) issues for the repo you're in and prints a terminal summary — no Sonar web UI, MCP server, or extra install. It always queries the analyzed branch or PR; by default it reports only the unresolved issues in that branch/PR's **new code**, and `--all` reports every unresolved issue on that same branch/PR instead.

**Requirements.**
- **Node 18+** (uses the built-in `fetch`; zero npm dependencies).
- **A Sonar project that has already been scanned** — this skill *reads* results, it does not scan. Run it after pushing the branch or once a PR exists, so Sonar has analysed the code.
- **A token** in `SONAR_TOKEN` (env) or a local `.env` / `env/.env` (or `--env-file <path>`).
- **Project config** — `sonar-project.properties` at the repo root (project key / org / host), or a SonarLint binding in `.vscode/settings.json`; otherwise pass `--project`.
- Run inside a **git repo** (it reads the current branch), or pass `--branch`. For self-hosted SonarQube, point `--host` at it (the `organization` field is sent only for SonarCloud).

**How to run.** Auto-triggers on read-only Sonar asks, or run `/sonar-issue-check`. `allowed-tools: Bash, Read`. Useful flags: `--all` (full unresolved backlog on the analyzed branch/PR, not just new code), `--include-resolved` (also include already-resolved issues), `--branch <name>`, `--pull-request <id>`, `--types BUG,VULNERABILITY,CODE_SMELL`, `--severities BLOCKER,…,INFO`, `--out <file>` (also write JSON), `--host <url>`, `--fail-on-issues` (exit 1 when matches found — for a gate).

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

**Pairs with.** [`verify-frontend-change`](#verify-frontend-change) — after trimming, verify the app still renders and behaves in a real browser.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill trim-initial-bundle
```

**Full definition:** [`skills/trim-initial-bundle/SKILL.md`](skills/trim-initial-bundle/SKILL.md) (plus the diagnosis / verification references and the `analyze-initial-load.mjs` analyzer under `scripts/`).

---

## `scaffold-claude`

**What it does.** Interview-driven `CLAUDE.md` author. Instead of scraping `package.json` and the directory tree into a generic file, it walks eight sections one at a time — header, stack, commands, architecture, conventions, hard constraints, doc pointers, gotchas — asking for the *non-obvious* facts and the *reason* behind each, and writes only what you confirm. Its Iron Rule: never write a section from inference — ask, and leave a `<!-- TODO -->` stub when you skip.

**Requirements.** A project to document (it reads the manifest, tree, and README only to know *what to ask about*). No tokens, no network, no shell.

**How to run.** Auto-triggers on "scaffold/write/set up CLAUDE.md" asks, or run `/scaffold-claude`. `allowed-tools: Read, Glob, Write`.

**Use it for.** Bootstrapping a `CLAUDE.md` for a project that has none, or redoing a weak one from scratch. For a large repo, scaffold the root file; then, when you explicitly ask, run the same interview once per substantial subsystem to add nested `CLAUDE.md` files — Claude Code loads a nested file only when it touches that folder.

**Triggers on phrases like.** "scaffold CLAUDE.md", "write a CLAUDE.md", "set up CLAUDE.md", "create project instructions for Claude", "bootstrap CLAUDE.md".

**What it does not do.** Surgically edit an existing `CLAUDE.md` (just edit it directly). Infer or fabricate content to fill a section — an empty stub beats a confident guess. Write to the repo root — the draft lands in `docs/scratchpad/` for you to move. Run any shell command, so it's Windows-clean by construction — and, along with editing, it declares `disallowed-tools: Bash, Edit, NotebookEdit` to drop those tools while the skill is active (a per-turn guard; the restriction clears on your next message).

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

**Pairs with.** [`document-generate`](#document-generate) — this skill authors the agent-facing context (`CLAUDE.md`); that one authors the human-facing docs for the same project.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill scaffold-claude
```

**Full definition:** [`skills/scaffold-claude/SKILL.md`](skills/scaffold-claude/SKILL.md) (plus interview scripts + an annotated example under `references/`, a stub under `templates/`). Adapted from [`ragnar-pwninskjold/tech-snacks`](https://github.com/ragnar-pwninskjold/tech-snacks) (MIT).

---

## `systematic-debugging`

**What it does.** Enforces a four-phase debugging discipline instead of guess-and-check: (1) root-cause investigation, (2) pattern / context analysis, (3) one tested hypothesis at a time, (4) fix the cause behind a failing test. Hard rules: no fix before root-cause investigation, and after three failed fixes, stop and question the architecture rather than trying a fourth.

**Requirements.** A failure you can reproduce, and a way to run it — your test runner / build / repro command (it uses `dotnet test`, `npm test`, etc.). git helps for the "what recently changed" step. No tokens or network.

**How to run.** Auto-triggers on debugging asks, or run `/systematic-debugging`. `allowed-tools: Read, Grep, Glob, Bash, Edit, Write`.

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

## `session-handoff`

**What it does.** Creates comprehensive handoff documents so a fresh AI agent session can pick up work with zero ambiguity, and resumes from them later. Two modes: **CREATE** — scaffold a handoff, fill in state/decisions/next-steps, validate it before finalizing; **RESUME** — list available handoffs, grade staleness against the current repo state, then load the handoff (and its chain of predecessors, if any) before starting work.

**Requirements.** **Python 3.9+** (the bundled scripts use built-in generics like `list[str]`; stdlib only — `argparse`, `os`, `re`, `subprocess`, `datetime`, `pathlib` — nothing to `pip install`). A git repository improves the auto-filled metadata (branch, recent commits, modified files) but isn't required. No tokens or network.

**How to run.** Auto-triggers on save-state / handoff / resume asks, or run `/session-handoff`. Declares no `allowed-tools` (unrestricted).

**Use it for.** Preserving context before a long session runs out of room, handing off to a different agent or teammate, or picking a project back up after a break without re-deriving what you already figured out.

**Triggers on phrases like.** "save state", "create handoff", "I need to pause", "context is getting full", "load handoff", "resume from", "continue where we left off". Also self-triggers proactively after substantial work (5+ file edits, complex debugging, an architecture decision).

**What it does not do.** Let you finalize a handoff with secrets detected or a validation score below 70 — `validate_handoff.py` scans for API keys, passwords, tokens, private keys, and common connection-string/bearer-token patterns before sign-off. Let a resume proceed blind — `check_staleness.py` grades the handoff FRESH → SLIGHTLY_STALE → STALE → VERY_STALE from time elapsed, commits since, files changed, and branch divergence, and a VERY_STALE result is a signal to create a fresh handoff rather than trust the old one.

**What it produces.** A Markdown handoff at `.claude/handoffs/YYYY-MM-DD-HHMMSS-<slug>.md` — metadata, current state summary, codebase understanding, decisions made with rationale, immediate next steps, pending work, critical files, patterns discovered, and gotchas — optionally linked to a predecessor with `--continues-from` to form a chain. The documented workflow writes only under `.claude/handoffs/`. Ships `scripts/` (`create_handoff.py`, `list_handoffs.py`, `validate_handoff.py`, `check_staleness.py`) and `references/` (`handoff-template.md`, `resume-checklist.md`).

**Example.**

```
You: context is getting full, save state before we continue tomorrow
→ python scripts/create_handoff.py implementing-user-auth
  Wrote .claude/handoffs/2026-07-08-143022-implementing-user-auth.md
  Validation: 88/100, no secrets detected, no TODOs remaining.
  First step next session: wire the refresh-token rotation in src/auth/session.ts.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill session-handoff
```

**Full definition:** [`skills/session-handoff/SKILL.md`](skills/session-handoff/SKILL.md) · **README:** [`skills/session-handoff/README.md`](skills/session-handoff/README.md) (plus the handoff template and resume checklist under `references/`).

---

## `retro`

**What it does.** Engineering retrospective for the current git repository. A bundled, zero-dependency Node script (`scripts/git-retro.mjs`) computes every metric deterministically from git history — commits, contributors, LOC, test ratio, per-author work sessions (45-minute-gap detection), an hourly histogram, commit-type mix, churn hotspots, approximate PR count/size buckets, focus score, ship-of-the-window, streaks, and AI-assisted-commit share (via `Co-Authored-By` trailers) — and emits one JSON document; the model's only job is to turn that JSON into a narrative, never to compute or round a number itself.

**Requirements.** **Node 18+** (uses `node:util` parseArgs; zero npm dependencies). A git repository with commit history. The script does one best-effort `git fetch` unless `--no-fetch` is passed. No token required.

**How to run.** Auto-triggers on retro / velocity / "what did we ship" asks, or run `/retro`. `allowed-tools: Bash, Read, Write`. Useful flags: `--window 7d|24h|Nd|Nh|Nw` (default 7-day window), `--compare` (adds the prior same-length window, computed live from git, plus deltas), `--base <ref>` (default `origin/<default-branch>`, auto-detected), `--no-fetch`, `--save [dir]` (writes a JSON snapshot to `docs/retros/`, then the model writes the markdown narrative alongside it).

**Use it for.** Weekly or sprint retros, "are we shipping faster than last month" trend checks, or a fast read on team velocity, focus, and churn hotspots without hand-computing git-log arithmetic.

**Triggers on phrases like.** "what did we ship this week", "weekly retro", "engineering retrospective", "team velocity", "commit stats for the last N days", "who worked on what lately", "are we shipping faster than last month".

**What it does not do.** State a number that isn't in the script's JSON — the iron rule is every figure in the retro traces back to that JSON, or the skill says the metric is unavailable. Grade, rank, or critique individual teammates — per-author output is stats-only (a leaderboard plus a personal deep-dive for the runner), improvement suggestions stay team-level, and it declines performance-review / HR asks outright. Pad a quiet window — a zero-commit window is reported as exactly that. Commit, push, or write anything beyond the optional `docs/retros/` snapshot and narrative on an explicit `--save`.

**What it produces.** By default, a 1,500–2,500-word narrative straight into the conversation: a tweetable one-liner, then a summary table, time/session patterns, shipping velocity, code-quality signals, focus & ship-of-the-window, a personal "your week" section for the runner, a team leaderboard, top 3 wins, 3 things to improve, 3 habits for next week, and — with `--compare` — a deltas table. Any true guard from the JSON (`zeroCommits`, `staleBase`, `fetchFailed`, `noRemote`, `detachedHead`, `shallowClone`) is carried into the narrative as a caveat, verbatim. With `--save`, also a JSON snapshot at `docs/retros/<YYYY-MM-DD>-<n>.json` and a markdown report at `docs/retros/<YYYY-MM-DD>-retro.md`. **Read-only on the repository otherwise.**

**Example.**

```
You: what did we ship this week?
→ Week of Jul 1: 47 commits (3 contributors), 3.2k LOC, 38% tests, 12 PRs, peak: 22:00 | streak 12d
  … summary table, time & session patterns, shipping velocity, code-quality signals,
  focus & ship of the window, your week, team leaderboard, top 3 wins, 3 things to
  improve, 3 habits for next week.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill retro
```

**Full definition:** [`skills/retro/SKILL.md`](skills/retro/SKILL.md) (plus the `git-retro.mjs` script under `scripts/`). Adapted from [`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT) — rebuilt so a deterministic script replaces model-computed arithmetic; gstack-state integrations (learnings, Greptile, telemetry, global mode) dropped.

---

## `verify-frontend-change`

**What it does.** Closes the "should work now" gap on frontend work. After a UI change it runs a five-step browser verification loop via the Chrome DevTools MCP server: start (or reuse) the dev server → open the affected page → interact with the changed behavior → require zero new console errors → record a performance trace. A change is reported *done* only when every step passes in one uninterrupted pass; any failure gets fixed and the loop reruns from the top.

**Requirements.** The [Chrome DevTools MCP server](https://github.com/ChromeDevTools/chrome-devtools-mcp) registered in Claude Code (`claude mcp add chrome-devtools --scope user npx chrome-devtools-mcp@latest` — needs Node 20.19+/22.12+/23+ and a current Chrome). Without it the skill stops and reports the change **unverified** instead of pretending. Plus a web app with a runnable dev server.

**How to run.** Auto-triggers when a frontend change is about to be declared done, and on verify-asks; or run `/verify-frontend-change`. Declares no `allowed-tools` (unrestricted) — shell and browser actions prompt per your own permission settings, including your `chrome-devtools` MCP tools.

**Use it for.** Any web-app change you'd otherwise sign off from a green build — component behavior, style tweaks, routes, client state — in any framework with a dev server (Vite, Next.js, CRA, Angular, Nuxt, Astro, SvelteKit, Remix; same loop for Rails/Django/ASP.NET-served frontends).

**Triggers on phrases like.** "verify it works", "check it in the browser", "make sure nothing broke", "does it actually render", "test the UI change" — and proactively whenever a frontend edit is about to be called done/fixed/working. Does **not** trigger for backend-only, CLI, test-only, or docs-only changes.

**What it does not do.** Call a change done from a clean edit, green build, or HMR reload. Resume mid-loop after a fix — a fix voids earlier evidence, so it reruns from Step 1. Patch forever — after 3 failed fix-and-rerun cycles on the same step it stops and questions the approach instead of trying a 4th. Invent login credentials, kill a dev server it didn't start, or hide a blocked step — "blocked, here's exactly what wasn't checked" is a valid end state; fake-verified is not.

**What it produces.** No repo artifacts — an evidence-backed verdict in chat: the URL verified, the interactions performed, console triage (new vs pre-existing), and trace numbers (LCP/CLS, flagged long tasks) with dev-mode caveats. Ships `references/` (`chrome-devtools-mcp.md` tool cheatsheet, `dev-server-playbook.md`).

**Example.**

```
You: swap the settings page's theme toggle for the new ThemePicker — done?
→ Not yet — verifying. Started `pnpm dev` (localhost:5174 — port hopped), opened
  /settings, picked "dark", saved, reloaded — persisted. Console: 1 new error
  (ThemePicker.tsx:42, `prefs` undefined) → fixed, reran from the top: 0 errors.
  Trace: LCP 1.1s, CLS 0.00, no new long tasks (dev-mode numbers).
  Verified — done. Dev server stopped.
```

**Pairs with.** [`trim-initial-bundle`](#trim-initial-bundle) — when the trace step flags heavy first-load JS on a Vite app, that skill finds and defers the vendor weight.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill verify-frontend-change
```

**Full definition:** [`skills/verify-frontend-change/SKILL.md`](skills/verify-frontend-change/SKILL.md) (plus the tool cheatsheet and dev-server playbook under `references/`).

---

## `health`

**What it does.** A local quality-gate dashboard for the current repository. A bundled, zero-dependency Node script (`scripts/check-health.mjs`) runs the project's own tools — typecheck, lint, test, dead-code, shell lint — parses their output, scores each category 0–10 against a weighted rubric (typecheck 25 / lint 20 / test 30 / deadcode 15 / shell 10, renormalized over whichever gates actually ran), and computes one weighted composite; the model's only job is to narrate that JSON, never to compute or estimate a score itself.

**Requirements.** **Node 18+** (zero npm dependencies). Whatever quality-gate tools the project already uses — a typechecker, linter, test runner, dead-code detector, shell linter. A category without an installed tool is skipped, not failed, and its weight redistributes across the rest. On first run there's no `.claude/health.json` yet — the skill detects a proposed config and has you confirm it before anything runs.

**How to run.** Auto-triggers on whole-project quality-overview asks, or run `/health`. `allowed-tools: Bash, Write`. First run: `--detect-only` prints the proposed config (command/weight/reason per category) for you to confirm via AskUserQuestion before it's saved to `.claude/health.json` and anything executes. After that: no flags for a normal check, `--only typecheck,lint` to run a subset, `--config <path>` for a specific config file, `--save [dir]` to append a line to `docs/health/history.jsonl` (trend is read from that file automatically whenever it exists).

**Use it for.** A whole-project quality snapshot before a release or a big refactor, a "how healthy is this codebase" gut-check on an unfamiliar repo, or tracking whether quality is trending up or down over time via `--save` history.

**Triggers on phrases like.** "check project health", "how healthy is the codebase", "quality dashboard", "run all the quality gates", "code health score", "full quality check", "are we getting better or worse".

**What it does not do.** Fix anything it finds — that's a separate ask (`sonar-issue-fix` for Sonar findings). Run a single gate — "just run the tests" needs no dashboard. Set up CI pipelines, or substitute its own linter/test runner for the project's — it wraps the project's own commands and configs exactly. Score a skipped category — no tool installed means skipped, never a zero. State a number that isn't in the script's JSON.

**What it produces.** A terminal dashboard: a header (repo/branch/date), a category table (gate, command, score, label, findings, duration — skipped rows say *skipped (reason)*, never a score), the composite (`X.X/10` with a CLEAN/WARNING/NEEDS WORK/CRITICAL label), a details block quoting real output for anything scoring below 7, script-ranked recommendations, a trend section when history exists, and a caveat line for every true honesty guard (`noToolsDetected`, `notGitRepo`, `dirtyWorkingTree`, `anyTimeout`, `anyParseFallback`, `firstRun`). Writes nothing by default; `--save` appends one line to `docs/health/history.jsonl`, and only on an explicit ask does the model also Write `docs/health/<YYYY-MM-DD>-health.md`. **Never commits or pushes.**

**Example.**

```
You: how healthy is this codebase?
→ No .claude/health.json yet — detected: typecheck (tsc, 25), lint (eslint, 20), test (vitest, 30),
  dead-code (knip, 15), shell (shellcheck, 10). Save this and run? (yes)
→ Composite: 6.8/10 NEEDS WORK
  typecheck 9.0 · lint 7.2 · test 5.5 (12 failing) · deadcode 8.0 · shell skipped (no .sh files)
  Top recommendation (HIGH): 12 failing tests in src/orders/*.spec.ts are dragging the composite down.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill health
```

**Full definition:** [`skills/health/SKILL.md`](skills/health/SKILL.md) (plus the `check-health.mjs` script under `scripts/`). Adapted from [`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT) — rebuilt so a deterministic script replaces model-computed scoring; the gstack-only gbrain dimension and `~/.gstack` global state are dropped (weights renormalized to 100); config moves to a user-confirmed `.claude/health.json`; history is opt-in (`--save`) and lives in-repo under `docs/health/`.

---

## `plan-eng-review`

**What it does.** The gate between "a plan exists" and "code gets written". Reviews a written implementation plan (the plan-mode draft, a file under `docs/plans/`, or a pasted plan) before any code is written: scope challenge → what-already-exists reuse check → four dimensions (architecture; code quality of the planned code; tests — the heaviest; performance) → verdict. Iron law: no finding without evidence — a presence finding quotes the plan or a `file:line` verified with Read/Grep; an absence finding quotes the plan text that creates the obligation plus the negative search that verified the absence. REGRESSION RULE: if the plan modifies existing behavior and no existing test covers the changed path, a regression test goes into Required plan changes — never asked, never waived.

**Requirements.** A written implementation plan to review, and the codebase it targets — the review grounds itself in the repo's `CLAUDE.md` and the files the plan touches. No tokens, no network.

**How to run.** Auto-triggers when a written plan exists and you ask for it to be reviewed, or run `/plan-eng-review`. `allowed-tools: Read, Grep, Glob, Bash, Write, Agent` (Bash is used read-only: git context, existence probes; Agent only for the optional outside-voice subagent).

**Use it for.** Gating a plan before implementation — catching rebuilt-what-already-exists, untested behavior changes, silent failure paths, and bloated scope while they are still cheap to fix.

**Triggers on phrases like.** "review this plan", "eng review the plan", "is this plan sound", "architecture review before we build", "check the implementation plan before I start".

**What it does not do.** Implement the plan (whatever the verdict). Design a feature from scratch (that's `new-feature`), decompose an approved plan (`convert-plan-to-feature`), devil's-advocate a decision or idea that isn't a written plan (`anti-sycophancy`), or review written code/diffs. It never edits any plan byte outside the report — the only mutation is replacing/appending the `## ENG REVIEW REPORT` section via a single whole-file Write-splice. Findings are batched into the report (each with a `[REC]`); AskUserQuestion is reserved for genuine scope/design forks, batched per section; an unanswered fork is recorded under `UNRESOLVED DECISIONS:`, never silently defaulted. Never commits or pushes.

**What it produces.** An `## ENG REVIEW REPORT` section appended at the end of the plan file (replacing any prior report; resolved decisions carry forward on re-runs and are never re-asked): a VERDICT (APPROVED / APPROVED WITH CHANGES / NEEDS REVISION — bound by a decision table: any CRITICAL GAP or unresolved decision ⇒ NEEDS REVISION; non-empty Required plan changes ⇒ at most APPROVED WITH CHANGES), scope-reduction opportunities, what-already-exists reuse findings, per-dimension findings (max 8 each, severity-ranked, confidence 1–10), a Required plan changes checklist, a failure-modes table (failure / test? / handled? / user-visible?), a test-coverage summary (★★★/★★/★/GAP planned-coverage legend + `COVERAGE: N/M`), a Decisions block, a NOT-in-scope list, a low-confidence appendix, and a closing `NO UNRESOLVED DECISIONS` / `UNRESOLVED DECISIONS:` marker. Terminal-only (zero writes) when the plan has no file on disk. Optional outside voice on explicit ask only: one subagent prompted to refute the verdict, tensions shown neutrally. Ships `references/review-dimensions.md`.

**Example.**

```
You: review docs/plans/csv-import.md before I start building
→ Grounded in CLAUDE.md + the 6 files the plan touches. 1 decision batch: processing
  model (sync in request vs [REC] async job). Spliced ## ENG REVIEW REPORT into the plan:
  VERDICT: NEEDS REVISION — importOrders() failure path is silent, untested, unhandled
  (CRITICAL GAP). Required plan changes: 2 (regression test for calculateTotals — the
  plan changes tested-by-nobody behavior; explicit error path for failed rows).
  What already exists: parseCsv() at src/lib/csv.ts — plan rebuilds it; reuse instead.
```

**Pairs with.** [`new-feature`](#new-feature) → plan mode → **this gate** → [`convert-plan-to-feature`](#convert-plan-to-feature) — design the feature, plan it, gate the plan, then decompose it. Also [`anti-sycophancy`](#anti-sycophancy) — that skill is the skepticism *stance* for any decision or idea; this one is the structured, evidence-gated *workflow* for a written plan. They complement, not compete. Also [`document-generate`](#document-generate) — this gate reviews the plan before implementation; that skill writes the user-facing docs once the code exists.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill plan-eng-review
```

**Full definition:** [`skills/plan-eng-review/SKILL.md`](skills/plan-eng-review/SKILL.md) (plus the review checklists, calibration tables, and report skeleton under `references/`). Adapted from [`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT) — rebuilt so per-finding question gates become per-section decision batching, the automatic Codex outside voice becomes an optional on-request Claude subagent, the separate test-plan/tasks artifacts fold into the single in-plan report, and gstack state is dropped.

---

## `document-generate`

**What it does.** Writes human-facing documentation files — Diataxis tutorials, how-to guides, reference pages, and explanations — for a named feature, module, or whole project. Reads the implementation and tests end-to-end before writing a word (codebase archaeology), classifies what's needed across the four Diataxis quadrants via a decision matrix, gets the partition plan approved, then writes in a fixed order: reference, explanation, how-to, tutorial.

**Requirements.** A codebase to document — the whole project, or a named feature/module/file within it. No bundled script, token, or network dependency; it works entirely from the repo's own source, tests, and existing docs.

**How to run.** Auto-triggers on doc-writing asks, or run `/document-generate`. `allowed-tools: Read, Grep, Glob, Bash, Write, Edit`.

**Use it for.** Producing an actual documentation file for a feature, module, or project — a tutorial that gets a newcomer to a working result, a how-to for one specific task, a reference page covering the full public surface, or an explanation of a design decision.

**Triggers on phrases like.** "write docs for this", "generate documentation", "document this feature / module / project", "create a tutorial for X", "write a how-to for X", "add reference docs".

**What it does not do.** Answer a "how does X work?" question asked in conversation — that gets answered directly, no files produced. Author `CLAUDE.md` or `AGENTS.md` agent context (`scaffold-claude`'s job — never touched by this skill). Design a feature that isn't built yet (`new-feature`) or decompose an approved plan into specs (`convert-plan-to-feature`). Run an automated stale-docs sweep across a diff — "document the changes I just made" gets redirected at Step 0 to name the actual targets, since the code is the documentation source, not the diff. Commit or push, under any circumstance.

**What it produces.** New or extended Markdown files in the resolved docs home — target-local convention, then repo `docs/`, then a detected doc framework (Docusaurus / MkDocs / VitePress / Nextra, with its sidebar updated), then a new root `docs/` as the last resort — written in order reference → explanation → how-to → tutorial, plus link lines added to the README's documentation section (a minimal `## Documentation` section is appended if none exists) and any existing docs sidebar. Ends with a report: files new/extended, quadrant counts, quality-gate results, a per-example verification list (executed / traced / illustrative), and a Corrections field for anywhere existing docs contradicted the code.

**Example.**

```
You: document the retry helper in src/retry.ts
→ Archaeology: retry(fn, opts) — maxAttempts (default 3), baseDelayMs (default 100);
  maxAttempts=0 throws RangeError (retry.test.ts:71).
  Partition plan: reference (new) + how-to (new) — approved as-is.
→ Wrote docs/reference-retry.md, docs/how-to-retry-flaky-calls.md. 1 link line added to
  README's ## Documentation.
  Corrections: README said the default maxAttempts is 5; src/retry.ts:14 says 3 — both
  new docs and the README now say 3.
```

**Pairs with.** [`scaffold-claude`](#scaffold-claude) — that skill authors the agent-facing context (`CLAUDE.md`); this one authors the human-facing docs for the same project. Also [`new-feature`](#new-feature) and [`plan-eng-review`](#plan-eng-review) — those settle decisions before the code is built; this skill documents it once it exists.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill document-generate
```

**Full definition:** [`skills/document-generate/SKILL.md`](skills/document-generate/SKILL.md) (plus the quadrant templates, anti-mixing table, and collision-policy detail under `references/`). Adapted from [`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT) — rebuilt so the commit/push/PR-update tail is dropped (this skill never commits), the `gstack-redact` binary becomes a placeholder-credentials rule, the confirm-above-5-docs threshold becomes an always-on partition-plan approval gate, upstream's inline-summaries-plus-standalone-files default narrows to standalone files plus minimal link lines, and the gstack machinery is dropped.

---

## `stdlib-first`

**What it does.** Enforces a reuse-before-build ladder when Claude writes new TypeScript/Node or C#/.NET code: reach for a built-in or standard-library API first, then (C#) a first-party `Microsoft.Extensions.*` package, then a widely-adopted library the project already uses — and only when every rung fails, write a custom implementation. On top of the ladder: precise types (no `any`, no `object`/`dynamic`), specific error classes instead of bare `Error`/`Exception`, C# async discipline (`CancellationToken`, no sync-over-async), and short doc comments on non-obvious members.

**Requirements.** None. Purely behavioral — it changes what code Claude writes, not what tools it can use.

**How to run.** Auto-triggers when Claude is about to write a new utility/helper/service or add/choose a dependency in TS or C#, or run `/stdlib-first`. Declares no `allowed-tools`/`disallowed-tools` — it guides code-writing and must not drop tools.

**Use it for.** Keeping generated code on the platform: no hand-rolled retry loops, date parsers, deep clones, or HTTP wrappers when `fetch`, `structuredClone`, LINQ, or an already-installed library does the job — and no surprise dependencies, because a missing library is always a question to you first.

**Triggers on phrases like.** "write a helper/utility/function to X", "implement retry / parsing / validation logic", "create a service for Y", "should we add lodash/Polly/date-fns", "which library for X".

**What it does not do.** Fire on code review or critique asks, debugging of existing behavior, trivial edits (a typo, rename, one-line fix), or languages other than TypeScript/C#. It never adds a dependency on its own — a missing library is surfaced as a question, never a silent `npm install`.

**What it produces.** No files or reports — a behavioral discipline that changes the code Claude writes. It is also the canonical copy of the `## Coding standards` block checked into Mi9 repos' `CLAUDE.md` files; the `<!-- source -->` comment in those blocks points here.

**Example.**

```
You: write a helper that retries a fetch up to 3 times with backoff
→ Ladder check: no retry library in package.json. Want p-retry added, or a
  zero-dependency helper? [asks]
→ "no new deps" → small helper on fetch + setTimeout from timers/promises,
  throws RetryExhaustedError extends Error, one-line JSDoc.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill stdlib-first
```

**Full definition:** [`skills/stdlib-first/SKILL.md`](skills/stdlib-first/SKILL.md).

---

## `repo-change-summary`

**What it does.** Answers "how much did this repo change in month X?" with one deterministic table. A bundled POSIX-shell script (`scripts/summary.sh`) runs a validated `git log` pipeline across **all branches** — each commit counted once, merge commits excluded from the line/file/commit counts — and reports lines added, lines deleted, total lines changed (added + deleted — churn, not net), files modified two ways (distinct, and summed across commits), commits, pull requests merged, and distinct authors. The script prints a finished Markdown table and writes a styled, self-contained HTML report; the model relays the table verbatim and never re-derives a number by hand. A companion script (`scripts/multi-summary.sh --group NAME`) does the same for a **named group of repos** — one combined report with a rollup table (totals row; authors counted as distinct people across the group, never the column sum; repos whose fetch failed marked `*`; repos ordered by total changed ascending, smallest first) followed by every repo's full table in that same order. Groups are machine-local `.list` files under `~/.claude/repo-change-summary-groups/` (one repo path per line), kept outside the skill because clone paths differ per machine. An optional `--per-author` flag appends a per-developer **activity** table (lines, files, commits, plus PRs authored-and-merged via the Bitbucket API — git merge commits credit the merger, not the author) — ordered by total changed ascending (a presentation choice, not a ranking), explicitly labeled activity-not-performance, with any developer's single dominating file (lockfile, generated code) called out in a footnote rather than hidden. Bot identities (built-in: Bitbucket Pipelines; extendable via `bot-emails.list`) are excluded from the developer table and footnoted with their commit count, while the repo rollup keeps every commit.

**Requirements.** `git` and a POSIX shell (Git Bash on Windows works) — no other dependencies. By default the script runs `git fetch` first so remote-only branches are included; a fetch failure is non-fatal (falls back to local branches with a warning), or skip the fetch with `--no-fetch`. The `--per-author` PR column additionally needs Python 3.9+ and Bitbucket credentials already stored for git (`git credential fill`; set `BITBUCKET_EMAIL` if your git email isn't your Atlassian login) — without them the column is omitted with a note, everything else still works. Emailing the report (`--email`) additionally needs Python 3.9+, a locally-installed headless Chrome or Edge (to render the HTML report to PDF), and SMTP credentials in a `repo-change-summary.env` file (kept in `~/.claude/`) — without these the email flags are simply unavailable and the rest of the skill is unaffected.

**How to run.** Auto-triggers on monthly change-volume asks, or run `/repo-change-summary`. `allowed-tools: Bash`; runs on `model: claude-sonnet-5` (pinned in frontmatter — the work is script-driven). Flags: `--month YYYY-MM` (default: current month), `--repo PATH` (default: current directory), `--out DIR` (where the HTML report lands; default: current directory), `--no-fetch`, `--no-open` (don't open the report in a browser), `--exclude PATTERN` (repeatable; excludes a file from every count by exact basename — see "What it does not do" for the default-excluded list). Optional emailing: `--email`, `--to LIST` (implies `--email`), `--subject STR`, `--email-dry-run` (preview only, sends nothing), `--env-file PATH`, `--mailmap PATH` — always dry-run first; see "What it produces" and `skills/repo-change-summary/references/emailing.md`.

**Use it for.** Monthly reporting numbers — "how many lines changed in June", "how many PRs did we merge last month", a churn snapshot for a status update. For a narrative retrospective with work sessions, hotspots, and trends over an arbitrary window, use `retro` instead — this skill is the raw monthly totals.

**Triggers on phrases like.** "how many lines changed this month", "how many files did we modify in June", "how many pull requests were merged last month", "repo churn for 2026-06", "diff volume in May", "monthly change summary", "generate the monthly change report / HTML summary", "give me the summary report for STF" (a named repo group).

**What it does not do.** Count a commit twice because it sits on several branches, or count merge commits' diffs (merged work is never double-counted). Count stash entries, tag-only commits, reverts that quote a merge subject, commit bodies that merely discuss a PR, or the same PR number twice — PRs are counted as distinct numbers from platform merge markers (GitHub / Bitbucket incl. its squash merges / GitLab), so markerless squash- or rebase-merges are not counted. Split one person into two authors over a name spelling — `.mailmap` is respected. Report the net line delta — "total lines changed" is churn (added + deleted). Count lockfiles or CI config toward any total by default — `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `composer.lock`, `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, `Pipfile.lock`, `go.sum`, `pubspec.lock`, and `bitbucket-pipelines.yml` are excluded from every count out of the box (exact basename match, not a glob); add more with repeatable `--exclude PATTERN`. Modify the repo — it only reads git history and writes the one HTML report to `--out`. Never commits or pushes.

**What it produces.** A Markdown summary table in the conversation, plus a self-contained styled HTML report named `YYYY-MM-DD-HHMM-repo-change-summary-<month>.html` in the output directory, opened in the default browser (suppress with `--no-open`). In group mode: one combined Markdown summary (rollup + per-repo tables) and one combined HTML report named `…-repo-change-summary-<group>-<month>.html`, with inline-SVG bar charts (no JS/CDN — offline-portable): lines changed by repo, and per developer (lines + PRs authored) when `--per-author` is on. With `--email`, also a PDF of that HTML report attached to an email with a modern, email-safe HTML body rendering the same summary table (plain-text alternative: the raw Markdown) — always **preview-first**: `--email-dry-run` resolves recipients and builds the PDF without sending, and only a confirmed re-run actually sends.

**Example.**

```
You: how many lines of code changed in this repo in June?
→ June, 2026 — Repository change summary (all branches · each commit counted once ·
  merges excluded): 12,480 added · 7,912 deleted · 20,392 total changed ·
  214 distinct files · 532 file-touches · 187 commits · 23 PRs merged · 6 authors.
  HTML report: ./2026-07-17-1512-repo-change-summary-2026-06.html
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill repo-change-summary
```

**Full definition:** [`skills/repo-change-summary/SKILL.md`](skills/repo-change-summary/SKILL.md) (plus the `summary.sh` script under `scripts/`).

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
