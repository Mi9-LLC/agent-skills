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

**Two skills are also published as plugins.** `npx skills add` installs skill files and nothing else, so a skill that needs a hook cannot arrive that way. `clear-and-short` needs a `UserPromptSubmit` hook to switch on reliably, and `execute-change` needs three hooks that watch its subagents — so both are published as plugins as well:

```
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install clear-and-short@mi9-agent-skills
claude plugin install execute-change@mi9-agent-skills
```

Install either skill this way **instead of** `npx skills add`, not as well: both register a skill under the same name, and only the plugin carries the hooks. Each plugin declares its own hooks inline in its `.claude-plugin/marketplace.json` entry — a marketplace entry rejects a hooks file path, and a hooks file at the repo root would load into both plugins, because both entries use the repo root as their plugin root. See [`hooks/README.md`](hooks/README.md).

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
| [`verify-implementation`](#verify-implementation) | Post-implementation gate: adversarially verifies finished work against whatever claims it is done — audits the report against the actual diff, re-derives every acceptance criterion, reads every new test body and re-runs mutation proofs to catch tautological guards, re-runs the project's own gates — then **fixes what it finds** on the branch in dedicated commits. Pins `claude-opus-5`. |
| [`execute-change`](#execute-change) | Autonomous end-to-end execution of a plan brief — or a free-text idea, which first gets a design interview (in rounds, until no decision is open; repo facts looked up, not asked; project terms sharpened against `CONTEXT.md`, ADRs offered sparingly) and a user-approved brief — in an OpenSpec-managed repo: one lead session drives author-change → review gate → apply changes → implement → audit → simplify via fresh per-step subagents, pauses with a phone push only when it needs the user (a decision, or a failure it may not resolve alone), commits per checkpoint on the branch and in the run root you pick at a blocking preflight question — the current branch and checkout (recommended), the run's own branch in that checkout, or a dedicated git worktree (only the worktree leaves your main working tree untouched and lets several plans run concurrently on one repo), and stops after the local commits — never deploys, never opens a PR. Installed as a plugin it also gets a heartbeat: three hooks log every subagent start, stop, and notification to `.claude/` in the directory you started the session in, a background watcher reads that log and speaks only when it goes quiet or a subagent asks for permission, and a Windows-only process sweep kills the build and test processes a finished subagent left behind. **Manual-only** (`/execute-change`). |
| [`clear-and-short`](#clear-and-short) | Behavioral mode that cuts the word count of Claude's replies and keeps them in simple English — drops preamble, tool-call narration, restated questions, repeated facts, option surveys, and closing summaries; prefers the common word, short sentences, and no idioms; keeps full sentences, articles, negations, numbers, and code verbatim; asks questions with numbered options so the user can answer with one number. A second entry point takes the voice-only asks ("humanize your responses", "remove the AI tells", "your replies sound like ChatGPT"): the AI-tells and simple-English rules switch on and the length caps stay off, because that request is for a different voice, not for less content. Steps back to full prose for security warnings, destructive-action confirmations, and hand-followed step lists. Produces no files. |
| [`unslop`](#unslop) | Edits human-facing prose (docs, READMEs, posts, emails, PR descriptions) to remove 31 catalogued AI-writing patterns — puffery, AI vocabulary, "not just X, but Y", forced groups of three, em-dash/colon/bold overuse, title-case headings, chatbot phrases, filler, hedging, abstract metaphor nouns, passive voice, feeling-words in place of facts. Keeps meaning, facts, numbers, and technical terms. Not for code, comments, commit messages, or chat replies (the length, wording, and AI tells of a reply belong to `clear-and-short`). Produces no files of its own; edits the text it is given. |

## Recommended workflow — from idea to verified code

This is one workflow, not a mandate: a way the catalog's planning and verification skills chain end to end for a substantial feature or initiative, shared because it works well in practice. Every step is independently useful — run the whole chain for large work, a single step for a small task, or just the pieces that fit how you already work. Each skill fires implicitly (describe the work and the matching skill launches on its own) or explicitly (start the message with `/<skill-name>`) — see "How these skills work" above. In an OpenSpec-managed repo the whole chain is **one command** — start with the automated path; the manual path serves every other repo, and the runs you want to drive stage by stage yourself.

```
OpenSpec repos    /execute-change "<idea or brief>" — design interview → review gate → implement → audit → simplify, unattended
all other repos   new-feature → plan mode → plan-eng-review → convert-plan-to-feature → implement → verify-implementation → /simplify
                    (design)     (the plan)  (pre-code gate)      (decomposition)                    (post-code gate)        (cleanup)
```

### The automated path — OpenSpec-managed repos (start here)

One command runs the journey end to end. [`/execute-change "add CSV import to the orders page"`](#execute-change) starts from the raw idea: it runs its own design interview (research dossier first, then categorized questions with `[REC]`-marked defaults, asked in rounds until no decision is open — facts from the repo are looked up, not asked), drafts the plan brief with its glossary and ADR sections, and waits for your approval — nothing executes on an unapproved brief. Already have a plan? Hand it the brief instead — `/execute-change "docs/up next/<name>-plan.md"` — written however you like, including via manual steps 1–2 below.

From the approved brief on, everything is agent-driven: it authors the OpenSpec change (the change's `tasks.md` is the decomposition — the OpenSpec counterpart of `convert-plan-to-feature`), runs `plan-eng-review` inside itself against the change artifacts (the gate is not skipped — it moves inside the automation), puts open decisions to you as batched questions (phone push via Remote Control), implements task group by task group, audits with `verify-implementation`, runs a simplification pass, and commits per checkpoint on the branch and in the directory you pick at a blocking preflight question — the current branch and checkout (recommended), the run's own branch there, or a dedicated git worktree. It stops after the local commits — deploy, archive, and PR remain yours.

### The manual path — repos without OpenSpec, or when you drive each stage yourself

`execute-change` cannot run its pipeline outside an OpenSpec-managed repo (`openspec/config.yaml` at the root, or a store the CLI resolves); finding one is a blocking preflight question offering to stop and work without the skill (recommended) or to run `openspec init` here first, so everywhere else this is the chain — and every skill in it stays independently useful; the automated path invokes the same gates internally:

1. [`new-feature`](#new-feature) — design before code. Turns a fuzzy request into locked design decisions: it researches the code and current best practices first, then asks categorized questions with a recommended default on each — nothing is assumed.

   ```
   You: I want to add CSV import to the orders page
   Claude: (after reading the auth + orders code) Category A — processing model:
     A1. (a) sync in the request   (b) [REC] async job — files can be large
     A2. Duplicate rows: (a) [REC] reject the file with a row report   (b) skip silently
   Confirm A1–A2 — or say "agreed with all recommended".
   ```

2. **Plan mode** (built into Claude Code) drafts the implementation plan from the locked decisions. Each phase gets a model recommendation — quality first: Opus is the default; a cheaper model only for clearly mechanical work.

3. [`plan-eng-review`](#plan-eng-review) reviews the written plan before any code is written and ends in a verdict.
4. [`convert-plan-to-feature`](#convert-plan-to-feature) decomposes the approved plan into per-feature spec files, each with its own checkbox acceptance criteria, a quality-first suggested model (Opus by default, a cheaper tier only for clearly mechanical work, every assignment re-reviewed in a second pass for underestimation), and a parallel group marking which features can be implemented concurrently.
5. **Implement** — one subagent per feature file (or a developer working by hand from the spec), each on the model its feature file suggests. When agents implement, this is the **last prompt you type** in the chain: steps 6 and 7 are not separate prompts — the prompt below launches them automatically. They keep their own step numbers because each is also a standalone skill, usable outside this chain:

   ```
   Implement every feature in docs/plans/csv-import/ — do not skip any.
   One subagent per feature, each on the model its feature file suggests.
   Proceed parallel group by parallel group, as marked in REQUIREMENTS.md,
   running the features within a group concurrently. As each feature
   completes, launch a background review of it with verify-implementation
   and let it fix what it finds. When every feature is verified, run
   /simplify over the combined changes.
   ```

   (No need to specify a review model — `verify-implementation` pins Opus 5 itself.)
6. [`verify-implementation`](#verify-implementation) adversarially verifies each claim of doneness against the code and fixes what it finds. In the chain, the step-5 prompt launches it per feature; standalone, point it at any claim of doneness — a PR, a ticket marked complete, an agent's report. The feature files from step 4 are its highest-preference input — their acceptance criteria are exactly what it verifies against.
7. **`/simplify`** (built into Claude Code, not part of this catalog) cleans up the verified code — reuse, simplification, efficiency. In the chain, the step-5 prompt runs it at the end; it also works anytime on its own. Re-run your quality gates after it edits.

The two gates are deliberate counterparts: `plan-eng-review` catches problems while they are still words; `verify-implementation` catches them once they are code — on the manual path you run each yourself; on the automated path `execute-change` runs both for you.

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

**Requirements.** An approved/finished plan to convert (plan-mode output, a confirmed design in the conversation, or an existing file under `docs/plans/`). It writes under the repository's own plan location when one exists (checked via its CLAUDE.md and existing folders — e.g. `docs/up next/`), else `docs/plans/` (or a top-level `plans/` fallback). No tokens or network.

**How to run.** Auto-triggers once a plan exists and you ask to decompose it, or run `/convert-plan-to-feature`. `allowed-tools: Read, Write, Glob, Grep, AskUserQuestion`.

**Use it for.** Breaking a complex plan into separately assignable, reviewable, closeable units of work — feature tickets/specs a team or implementation agents can run in parallel.

**Triggers on phrases like.** "convert this plan into features", "split the plan up", "break this into per-feature files", "turn the plan into implementation specs", "make a feature breakdown", "decompose the plan", "create feature tickets from this plan".

**What it does not do.** Implement anything — it writes planning documents only and stops. It declares `disallowed-tools: Edit, NotebookEdit`, which drops those tools while the skill is active (a per-turn guard — the restriction clears on your next message). It never writes at the `docs/plans/` root (everything goes inside the `<initiative>/` subfolder so concurrent efforts don't collide), and it leaves the source plan where it is. It also stays out of repositories that mandate their own spec workflow (e.g. OpenSpec repos, where the change's `tasks.md` owns the breakdown) — there, its execution rigor (model rubric, parallel groups, acceptance criteria, standing implementer instructions) is ported into that artifact instead of a parallel breakdown.

**What it produces.**
- `docs/plans/<initiative>/REQUIREMENTS.md` — the index: context, blast radius, locked decisions, consolidated cross-cutting catalogs (wire-contract/enum tables, message types, error codes), deploy ordering, parallel groups (assigned mechanically from the dependency data — same group means no dependencies between them, safe to implement concurrently), a feature table with suggested models — assigned quality-first (Opus is the default; Sonnet/Haiku only for work meeting every condition of the cheaper tier; any underestimation signal forces Opus) and re-reviewed in a mandatory second pass, since a feature underestimated onto a cheaper model costs a bad implementation plus rework — a Status column (`todo` / `in progress` / `done` / `blocked` — the initiative's status board), test strategy, and open questions. On a re-run where the `<initiative>/` folder already exists it reads the existing `REQUIREMENTS.md` first, preserves every feature's Status value, and asks before overwriting any feature file whose status is past `todo`.
- `docs/plans/<initiative>/features/NN - <Feature Name>.md` — one file per feature: requirement, a **Consumes/Produces interface contract**, ordered technical steps with real file paths (no placeholders), objectively checkable acceptance criteria (a feature that modifies existing behavior must carry a criterion naming its regression test), dependency/risk notes, its parallel group in the header, and a fixed *Standing instructions for the implementer* block (verbatim in every file: ask rather than resolve open questions by assumption; verify external library/API behavior against current documentation, not internal knowledge; the file's acceptance criteria are the verification contract `verify-implementation` runs against, so a mid-feature scope change is written back into them).

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

**Pairs with.** [`plan-eng-review`](#plan-eng-review) — gate the plan before decomposing it. [`verify-implementation`](#verify-implementation) — each feature file's acceptance-criteria checklist is that skill's highest-preference input: decompose here, implement, then verify each feature against its own criteria.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

**Full definition:** [`skills/convert-plan-to-feature/SKILL.md`](skills/convert-plan-to-feature/SKILL.md) · **README:** [`skills/convert-plan-to-feature/README.md`](skills/convert-plan-to-feature/README.md).

---

## `new-feature`

**What it does.** An investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written. It researches first — the relevant code, the repo's `CLAUDE.md`/`AGENTS.md` invariants, prior plans and git history, and current best practices — then surfaces every ambiguous decision as categorized questions (A/B/C…) with `[REC]`-marked defaults and a short reason, asking one category per message and locking each answer with a one-line summary, until zero ambiguity is left. After the first one or two categories it emits the full punch list of outstanding decisions proactively (a living list it re-posts as answers add or close items), and before handing off to plan mode it posts the complete locked-decision register in one message.

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

**How to run.** Auto-triggers on read-only Sonar asks, or run `/sonar-issue-check`. `allowed-tools: Bash, Read`. Useful flags: `--all` (full unresolved backlog on the analyzed branch/PR, not just new code), `--include-resolved` (also include already-resolved issues), `--branch <name>`, `--pull-request <id>`, `--types BUG,VULNERABILITY,CODE_SMELL`, `--severities BLOCKER,…,INFO`, `--out <file>` (also write JSON), `--host <url>`, `--fail-on-issues` (exit 1 when matches found — for a gate), `--quality-gate` (report the project's quality-gate status for the branch/PR), `--max-print N` (raise or lower the 150-issue print cap).

**Use it for.** The pre-commit / pre-PR "did I just introduce a problem?" check, pulling findings for a specific branch or PR, filtering to bugs/vulnerabilities or high severities, or exporting JSON for a CI gate.

**Triggers on phrases like.** "check sonar before I push", "what did sonarcloud flag on my branch", "any new code smells", "pull the sonar bugs for PR 123", "did I introduce any new issues".

**What it does not do.** Run the Sonar scan itself (that's your CI pipeline). Modify the repo — it's read-only against the Sonar API and writes a file only with `--out`. Configure SonarLint, tokens, or quality-gate thresholds.

**What it produces.** A terminal summary — counts by severity and type, then one line per issue (`[SEVERITY/TYPE] file:line` + message + rule), worst first, capped at 150 issues with an "… and N more" line (raise or lower the cap with `--max-print N`); with `--quality-gate` it also reports the branch/PR quality-gate status. A JSON file only when you pass `--out`. Exit code is `0` normally, `1` only with `--fail-on-issues` when matches exist, `2` on a setup error (missing token/config).

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

**What it does not do.** Report-only inspection (that's `sonar-issue-check`). Change runtime or wire behavior — these are code-quality smells, not bug fixes; if a finding's correct fix is a real bug fix, it surfaces that to you instead of forcing a quality-pass edit, and it likewise surfaces genuine false positives (the code is right and the rule is wrong → recommends marking the issue won't-fix / accepted) rather than editing correct code. Commit or push unless you ask.

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

**How to run.** Auto-triggers on bundle / first-load / "why is X in the main chunk" asks, or run `/trim-initial-bundle`. `allowed-tools: Bash, Read, Edit, Write, Grep, Glob, WebFetch`.

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

**What it does.** Enforces a four-phase debugging discipline instead of guess-and-check: (1) root-cause investigation, (2) pattern / context analysis, (3) ranked hypotheses, one tested at a time, (4) fix the cause behind a failing test. Hard rules: no fix before root-cause investigation, and after three failed fixes, stop and question the architecture rather than trying a fourth. Phase 1 needs a reproduction loop before any diagnosis: one named command, run once with its output shown, that fails on the exact symptom, fast and deterministic (a flaky bug is pushed to the highest reproduction rate you can reach — loops, parallel runs, load, injected sleeps — before diagnosis), then minimised one element at a time. Phase 3 writes down 2–4 ranked hypotheses, each with a falsifiable prediction, and tests only the top one; a failed test moves to the next on the list. Phase 4 puts the regression test at a seam that exercises the bug as it happens at the real call site. Temporary logs carry a unique `[DEBUG-xxxx]` prefix so cleanup is one grep, and shown diagnostics are redacted (`<REDACTED>`, credentials only via environment variables).

**Requirements.** A failure you can reproduce, and a way to run it — your test runner / build / repro command (it uses `dotnet test`, `npm test`, etc.). git helps for the "what recently changed" step. No tokens or network.

**How to run.** Auto-triggers on debugging asks, or run `/systematic-debugging`. `allowed-tools: Read, Grep, Glob, Bash, Edit, Write`.

**Use it for.** Any failure you're about to fix — a bug, a failing or flaky test, a regression, a build break, a crash, "works locally but not in CI", or a repeated failed-fix loop. Most valuable exactly when it's tempting to skip: under time pressure and when a fix "looks obvious."

**Triggers on phrases like.** "why is this broken", "this test is flaky", "my fix didn't work", "this keeps failing", "it works locally but not in CI", or a pasted stack trace. Not for trivial self-evident edits (a typo, a rename).

**What it does not do.** Propose a fix before the root cause is found. Bundle a refactor or "while I'm here" cleanup into the fix. Keep trying on the same theory — it states the running fix-attempt count in the visible reply on every failed fix, and three failed fixes means the design is the suspect, so it stops to raise that with you.

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

**Full definition:** [`skills/systematic-debugging/SKILL.md`](skills/systematic-debugging/SKILL.md) (plus the three technique references). Adapted from [`obra/superpowers`](https://github.com/obra/superpowers) (MIT) — decoupled, Windows-clean, with .NET/xUnit + TS/Vitest examples. The reproduction-loop, ranked-hypotheses, seam, log-tag, redaction, and flaky-rate rules are adapted from [`mattpocock/skills`](https://github.com/mattpocock/skills) `diagnosing-bugs` (MIT, © 2026 Matt Pocock).

---

## `test-driven-development`

**What it does.** Guides the red-green-refactor cycle for a piece of work you've chosen to build test-first: write one failing test, watch it fail *for the right reason*, write the minimal code to pass, then refactor — and pushes back on the rationalizations for skipping that order. Before the first test it lists the test seams (the public boundaries the tests will go through — existing ones preferred, fewer is better) and confirms them with you, or states them in its report when running unattended. Expected values come from an independent source (a literal, a worked example, the spec), never recomputed the way the code computes them; writing all tests first and all code after (horizontal slicing) is named as a rationalization — one test, then one implementation.

**Requirements.** A test framework set up for your stack so RED/GREEN can actually run — xUnit / `dotnet test` (C#) or Vitest / `npm test` (TS/JS). You opt in for the specific piece of work.

**How to run.** **Opt-in** — it auto-triggers *only* on an explicit TDD ask or a new feature you say you want built test-first; or run `/test-driven-development`. `allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion`.

**Use it for.** A new feature, module, or component you want built test-driven. It's a deliberate methodology you opt into — not a global mandate on all your code.

**Triggers on phrases like.** "let's TDD this", "build X test-first", "write the tests first", "red-green-refactor", "implement Y test-driven". Deliberately does **not** trigger on ordinary work — every edit, routine bug fix, small tweak, refactor of existing code, or "add tests after the fact."

**What it does not do.** Impose itself on changes you didn't opt into. Delete your existing code to "redo it properly" unless you ask. Let a test pass on the first run without you having watched it fail (that proves nothing).

**What it produces.** No artifacts — a disciplined test-first workflow with a verification checklist. Ships `references/testing-anti-patterns.md` (asserting on mock behavior, test-only methods on production classes, incomplete mocks, the mocking-boundary rule — mock at the lowest boundary that owns the slow or external effect, and treat having to mock one of your own modules as a design smell — and verifying through a side channel such as a DB query instead of the interface).

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

**Full definition:** [`skills/test-driven-development/SKILL.md`](skills/test-driven-development/SKILL.md) (plus the anti-patterns reference). Adapted from [`obra/superpowers`](https://github.com/obra/superpowers) (MIT) — reframed as opt-in, decoupled, with .NET/xUnit + TS/Vitest examples. The seam, independent-expected-value, horizontal-slicing, mocking-boundary, and side-channel rules are adapted from [`mattpocock/skills`](https://github.com/mattpocock/skills) `tdd` (MIT, © 2026 Matt Pocock).

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
→ python "${CLAUDE_SKILL_DIR}/scripts/create_handoff.py" implementing-user-auth
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

**What it produces.** For a retro / retrospective / trend ask, the full 1,500–2,500-word narrative straight into the conversation: a tweetable one-liner, then a summary table, time/session patterns, shipping velocity, code-quality signals, focus & ship-of-the-window, a personal "your week" section for the runner, a team leaderboard, top 3 wins, 3 things to improve, 3 habits for next week, and — with `--compare` — a deltas table. For a narrower stat-shaped ask (e.g. "commit stats for the last N days") it gives a short form instead — the one-liner, the summary table, and only the sections the question actually asked about. Any true guard from the JSON (`zeroCommits`, `staleBase`, `fetchFailed`, `noRemote`, `detachedHead`, `shallowClone`) is carried into the narrative as a caveat, verbatim. With `--save`, also a JSON snapshot at `docs/retros/<YYYY-MM-DD>-<n>.json` and a markdown report at `docs/retros/<YYYY-MM-DD>-retro.md`. **Read-only on the repository otherwise.**

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

**Requirements.** **Node 18+** (zero npm dependencies). Whatever quality-gate tools the project already uses — a typechecker (JS/TS, Python, or .NET via `dotnet build --nologo`), linter, test runner, dead-code detector, shell linter. A category without an installed tool is skipped, not failed, and its weight redistributes across the rest. On first run there's no `.claude/health.json` yet — the skill detects a proposed config and has you confirm it before anything runs.

**How to run.** Auto-triggers on whole-project quality-overview asks, or run `/health`. `allowed-tools: Bash, Write`. First run: `--detect-only` prints the proposed config (command/weight/reason per category) for you to confirm via AskUserQuestion before it's saved to `.claude/health.json` and anything executes. After that: no flags for a normal check, `--only typecheck,lint` to run a subset, `--config <path>` for a specific config file, `--parallel` to run the gates concurrently (opt-in — the durations it reports are then wall-clock-under-contention and not comparable to history), `--save [dir]` to append a line to `docs/health/history.jsonl` (trend is read from that file automatically whenever it exists).

**Use it for.** A whole-project quality snapshot before a release or a big refactor, a "how healthy is this codebase" gut-check on an unfamiliar repo, or tracking whether quality is trending up or down over time via `--save` history.

**Triggers on phrases like.** "check project health", "how healthy is the codebase", "quality dashboard", "run all the quality gates", "code health score", "full quality check", "are we getting better or worse".

**What it does not do.** Fix anything it finds — that's a separate ask (`sonar-issue-fix` for Sonar findings). Run a single gate — "just run the tests" needs no dashboard. Set up CI pipelines, or substitute its own linter/test runner for the project's — it wraps the project's own commands and configs exactly. Score a skipped category — no tool installed means skipped, never a zero. State a number that isn't in the script's JSON.

**What it produces.** A terminal dashboard: a header (repo/branch/date), a category table (gate, command, score, label, findings, duration — skipped rows say *skipped (reason)*, never a score), the composite (`X.X/10` with a CLEAN/WARNING/NEEDS WORK/CRITICAL label), a details block quoting real output for anything scoring below 7 (a clean gate's captured output is trimmed to a short tail), script-ranked recommendations, a trend section when history exists, and a caveat line for every true honesty guard (`noToolsDetected`, `notGitRepo`, `dirtyWorkingTree`, `anyTimeout`, `anyParseFallback`, `firstRun`). Writes nothing by default; `--save` appends one line to `docs/health/history.jsonl`, and only on an explicit ask does the model also Write `docs/health/<YYYY-MM-DD>-health.md`. **Never commits or pushes.**

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

**What it does.** The gate between "a plan exists" and "code gets written". Reviews a written implementation plan (the plan-mode draft, a file under `docs/plans/`, or a pasted plan) before any code is written: scope challenge (which also challenges any per-phase model recommendations the plan carries — quality outranks price, so an underestimation signal in a phase forces an Opus recommendation) → what-already-exists reuse check → four dimensions (architecture — including the deletion test on every planned module (delete it in your head: if complexity vanishes it was a pass-through) and the two-adapter rule (no interface or port unless two implementations are justified, normally production + test); code quality of the planned code; tests — the heaviest, including a seams check (a planned test that must change when the implementation changes tests past the interface; fewer seams, existing ones preferred) and the dependency category — in-process, locally substitutable, remote-but-owned, true external — that decides the test strategy; performance) → verdict. Iron law: no finding without evidence — a presence finding quotes the plan or a `file:line` verified with Read/Grep; an absence finding quotes the plan text that creates the obligation plus the negative search that verified the absence; a finding that depends on external library/framework/API behavior is verified against that dependency's *current* documentation in-session, never against internal knowledge. REGRESSION RULE: if the plan modifies existing behavior and no existing test covers the changed path, a regression test goes into Required plan changes — never asked, never waived.

**Requirements.** A written implementation plan to review, and the codebase it targets — the review grounds itself in the repo's `CLAUDE.md` and the files the plan touches. No tokens; network only to check current documentation when a finding depends on external-library behavior.

**How to run.** Auto-triggers when a written plan exists and you ask for it to be reviewed, or run `/plan-eng-review`. `allowed-tools: Read, Grep, Glob, Bash, Write, Agent, AskUserQuestion, WebSearch, WebFetch` (Bash is used read-only: git context, existence probes; Agent for the parallel Explore subagents in the what-already-exists reuse sweep — the reviewer then re-reads every cited `file:line` itself, since a subagent report is a lead, not evidence — and for the optional outside-voice subagent; WebSearch/WebFetch only to verify external-library behavior against current docs).

**Use it for.** Gating a plan before implementation — catching rebuilt-what-already-exists, untested behavior changes, silent failure paths, bloated scope, and underestimated model recommendations while they are still cheap to fix.

**Triggers on phrases like.** "review this plan", "eng review the plan", "is this plan sound", "architecture review before we build", "check the implementation plan before I start".

**What it does not do.** Implement the plan (whatever the verdict). Design a feature from scratch (that's `new-feature`), decompose an approved plan (`convert-plan-to-feature`), devil's-advocate a decision or idea that isn't a written plan (`anti-sycophancy`), or review written code/diffs. It never edits any plan byte outside the report — the only mutation is replacing/appending the `## ENG REVIEW REPORT` section via a single whole-file Write-splice. Findings are batched into the report (each with a `[REC]`); AskUserQuestion is reserved for genuine scope/design forks, batched per section; an unanswered fork is recorded under `UNRESOLVED DECISIONS:`, never silently defaulted. Never commits or pushes.

**What it produces.** An `## ENG REVIEW REPORT` section appended at the end of the plan file (replacing any prior report; resolved decisions carry forward on re-runs and are never re-asked, and each prior report's Required plan changes are re-verified against the amended plan so the max-8-findings cap can't silently drop one): a VERDICT (APPROVED / APPROVED WITH CHANGES / NEEDS REVISION — bound by a decision table: any CRITICAL GAP or unresolved decision ⇒ NEEDS REVISION; non-empty Required plan changes ⇒ at most APPROVED WITH CHANGES), scope-reduction opportunities, what-already-exists reuse findings, per-dimension findings (max 8 each, severity-ranked, confidence 1–10), a Required plan changes checklist, a failure-modes table (failure / test? / handled? / user-visible?), a test-coverage summary (★★★/★★/★/GAP planned-coverage legend + `COVERAGE: N/M`), a Decisions block, a NOT-in-scope list, a low-confidence appendix, and a closing `NO UNRESOLVED DECISIONS` / `UNRESOLVED DECISIONS:` marker. Terminal-only (zero writes) when the plan has no file on disk. Optional outside voice on explicit ask only: one subagent prompted to refute the verdict, tensions shown neutrally. Ships `references/review-dimensions.md`.

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

**Pairs with.** [`new-feature`](#new-feature) → plan mode → **this gate** → [`convert-plan-to-feature`](#convert-plan-to-feature) → implement → [`verify-implementation`](#verify-implementation) — design the feature, plan it, gate the plan, decompose it, build it, then gate the built code (the full chain is the [recommended workflow](#recommended-workflow--from-idea-to-verified-code)). Also [`anti-sycophancy`](#anti-sycophancy) — that skill is the skepticism *stance* for any decision or idea; this one is the structured, evidence-gated *workflow* for a written plan. They complement, not compete. Also [`document-generate`](#document-generate) — this gate reviews the plan before implementation; that skill writes the user-facing docs once the code exists.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill plan-eng-review
```

**Full definition:** [`skills/plan-eng-review/SKILL.md`](skills/plan-eng-review/SKILL.md) (plus the review checklists, calibration tables, and report skeleton under `references/`). Adapted from [`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT) — rebuilt so per-finding question gates become per-section decision batching, the automatic Codex outside voice becomes an optional on-request Claude subagent, the separate test-plan/tasks artifacts fold into the single in-plan report, and gstack state is dropped. The deletion test, two-adapter rule, and seams/dependency-categories check are adapted from [`mattpocock/skills`](https://github.com/mattpocock/skills) `codebase-design` and `to-spec` (MIT, © 2026 Matt Pocock).

---

## `document-generate`

**What it does.** Writes human-facing documentation files — Diataxis tutorials, how-to guides, reference pages, and explanations — for a named feature, module, or whole project. Reads the implementation and tests end-to-end before writing a word (codebase archaeology), classifies what's needed across the four Diataxis quadrants via a decision matrix, gets the partition plan approved, then writes in a fixed order: reference, explanation, how-to, tutorial.

**Requirements.** A codebase to document — the whole project, or a named feature/module/file within it. No bundled script, token, or network dependency; it works entirely from the repo's own source, tests, and existing docs.

**How to run.** Auto-triggers on doc-writing asks, or run `/document-generate`. `allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent`.

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

**What it does.** Enforces a reuse-before-build ladder when Claude writes new TypeScript/Node or C#/.NET code: reach for a built-in or standard-library API first, then (C#) a first-party `Microsoft.Extensions.*` package, then a widely-adopted library the project already uses — and only when every rung fails, write a custom implementation. One consistency exception overrides the rung order: where the project already uses one library consistently for the exact task, matching that established convention outranks introducing a rung-1 built-in alongside it — or, if the two genuinely conflict, the conflict is named to you rather than decided silently. On top of the ladder: precise types (no `any`, no `object`/`dynamic`), specific error classes instead of bare `Error`/`Exception`, C# async discipline (`CancellationToken`, no sync-over-async), and short doc comments on non-obvious members.

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

**What it does.** Answers "how much did this repo change in month X?" with one deterministic table. A bundled POSIX-shell script (`scripts/summary.sh`) runs a validated `git log` pipeline across **all branches** — each commit counted once, merge commits excluded from the line/file/commit counts — and reports lines added, lines deleted, total lines changed (added + deleted — churn, not net), files modified two ways (distinct, and summed across commits), commits, pull requests merged, and distinct authors. The script prints a finished Markdown table and writes a styled, self-contained HTML report; the model relays the table verbatim and never re-derives a number by hand. A companion script (`scripts/multi-summary.sh --group NAME`) does the same for a **named group of repos**, processing them in parallel (bounded to 4 at a time) — one combined report with a rollup table (totals row; authors counted as distinct people across the group, never the column sum; repos whose fetch failed marked `*`; repos ordered by total changed ascending, smallest first) followed by every repo's full table in that same order. Groups are machine-local `.list` files under `~/.claude/repo-change-summary-groups/` (one repo path per line), kept outside the skill because clone paths differ per machine. An optional `--per-author` flag appends a per-developer **activity** table (lines, files, commits, plus PRs authored-and-merged via the Bitbucket API — git merge commits credit the merger, not the author) — ordered by total changed ascending (a presentation choice, not a ranking), explicitly labeled activity-not-performance, with any developer's single dominating file (lockfile, generated code) called out in a footnote rather than hidden. Bot identities (built-in: Bitbucket Pipelines; extendable via `bot-emails.list`) are excluded from the developer table and footnoted with their commit count, while the repo rollup keeps every commit.

**Requirements.** `git` and a POSIX shell (Git Bash on Windows works) — no other dependencies. By default the script runs `git fetch` first so remote-only branches are included; a fetch failure is non-fatal (falls back to local branches with a warning), or skip the fetch with `--no-fetch`. The `--per-author` PR column additionally needs Python 3.9+ and Bitbucket credentials already stored for git (`git credential fill`; set `BITBUCKET_EMAIL` if your git email isn't your Atlassian login) — without them the column is omitted with a note, everything else still works. Emailing the report (`--email`) additionally needs Python 3.9+, a locally-installed headless Chrome or Edge (to render the HTML report to PDF), and SMTP credentials in a `repo-change-summary.env` file (kept in `~/.claude/`) — without these the email flags are simply unavailable and the rest of the skill is unaffected.

**How to run.** Auto-triggers on monthly change-volume asks, or run `/repo-change-summary`. `allowed-tools: Bash`; runs on `model: claude-sonnet-5` (pinned in frontmatter — the work is script-driven). Flags: `--month YYYY-MM` (default: current month), `--repo PATH` (default: current directory), `--out DIR` (where the HTML report lands; default: current directory), `--no-fetch`, `--no-open` (don't open the report in a browser), `--exclude PATTERN` (repeatable; excludes a file from every count by basename, with `*`/`?` glob support — see "What it does not do" for the default-excluded list). Optional emailing: `--email`, `--to LIST` (implies `--email`), `--subject STR`, `--email-dry-run` (preview only, sends nothing), `--env-file PATH`, `--mailmap PATH` — always dry-run first; see "What it produces" and `skills/repo-change-summary/references/emailing.md`.

**Use it for.** Monthly reporting numbers — "how many lines changed in June", "how many PRs did we merge last month", a churn snapshot for a status update. For a narrative retrospective with work sessions, hotspots, and trends over an arbitrary window, use `retro` instead — this skill is the raw monthly totals.

**Triggers on phrases like.** "how many lines changed this month", "how many files did we modify in June", "how many pull requests were merged last month", "repo churn for 2026-06", "diff volume in May", "monthly change summary", "generate the monthly change report / HTML summary", "give me the summary report for STF" (a named repo group).

**What it does not do.** Count a commit twice because it sits on several branches, or count merge commits' diffs (merged work is never double-counted). Count stash entries, tag-only commits, reverts that quote a merge subject, commit bodies that merely discuss a PR, or the same PR number twice — PRs are counted as distinct numbers from platform merge markers (GitHub / Bitbucket incl. its squash merges / GitLab), so markerless squash- or rebase-merges are not counted. Split one person into two authors over a name spelling — `.mailmap` is respected. Report the net line delta — "total lines changed" is churn (added + deleted). Count lockfiles or CI config toward any total by default — `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `composer.lock`, `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, `Pipfile.lock`, `go.sum`, `pubspec.lock`, and `bitbucket-pipelines.yml` are excluded from every count out of the box — the default list lives in a shared `scripts/exclude-lib.sh` that both scripts source; add more with repeatable `--exclude PATTERN`, matched by basename with `*`/`?` glob support (an exact match is the fast path, character classes are not supported, and matching is case-sensitive). Modify the repo — it only reads git history and writes the one HTML report to `--out`. Never commits or pushes.

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

## `verify-implementation`

**What it does.** The post-implementation gate — `plan-eng-review`'s counterpart on the other side of the code. Takes a finished implementation plus whatever asserts it is complete (a feature file's acceptance criteria, a plan, a ticket, a PR description, or a subagent's completion report) and adversarially verifies the claim: audits the report against the actual diff (a claimed change absent from the diff is the most serious finding it can produce), re-derives every acceptance criterion from its own evidence, reads every new test body and re-runs mutation proofs to catch tautological guards — *a test that cannot be made to fail is not a guard* — re-runs the project's own quality gates reading output rather than exit codes, then **fixes what it finds** on the same branch in dedicated commits and re-runs the gates.

**Requirements.** A completed implementation in a git repo (the diff is the review object), and **a claim of doneness**. Written acceptance criteria are the preferred input — the `features/NN - <name>.md` files from [`convert-plan-to-feature`](#convert-plan-to-feature) are the ideal shape — but a plan, ticket, PR description, or an agent's own report works; an informal claim gets a derived acceptance table, labeled as derived. With no claim at all it refuses: there is nothing to verify against. The project's own quality gates as its `CLAUDE.md` defines them.

**How to run.** Auto-triggers when an implementation is finished and something asserts it is correct, or run `/verify-implementation`. `allowed-tools: Read, Edit, Write, Bash, Grep, Glob`. Pins `model: claude-opus-5` — a weaker review returns `CLEAN` on broken work, and `CLEAN` is acted on; the failure mode of this skill is false assurance.

**Use it for.** Verifying a subagent's (or teammate's) "done" report before acting on it, gating a feature branch against its acceptance criteria before merge, checking whether new tests actually guard anything, and closing the loop on an initiative implemented from `convert-plan-to-feature` specs.

**Triggers on phrases like.** "verify the implementation", "the agent says it's done — check it", "audit this against the acceptance criteria", "is this actually done", "double-check the work before I merge", "the tests pass but I don't trust them".

**What it does not do.** Review a written plan before code exists ([`plan-eng-review`](#plan-eng-review)). Open-ended critique of an idea ([`anti-sycophancy`](#anti-sycophancy)), static-analyser cleanups ([`sonar-issue-fix`](#sonar-issue-fix)), or debugging a known failure ([`systematic-debugging`](#systematic-debugging) — this skill starts from a claim of success, not a known failure). Manufacture findings — if the implementation is correct it says so plainly; a short review that confirms real evidence is a good review. Change a decision the plan or feature file locked, or widen scope — both go in the report, not into edits. Commit to a shared branch, push, or open a PR — fixes land on the working branch in dedicated commits, and if the work sits directly on `main` it proposes the fixes instead of committing.

**What it produces.** Fix commits on the working branch (when findings are fixable in scope), plus a six-section report: a verdict — `CLEAN` / `FIXED` / `NEEDS ATTENTION`, bound by a decision table (any unfixed finding, locked-decision conflict, or not-run gate ⇒ `NEEDS ATTENTION`) — with a one-line *Passes not run* slot naming any verification pass it skipped and why, a claim-vs-diff audit, findings most serious first each with `path:line` and fixed-or-not status, mutation proofs with verbatim failure output (each proof re-runs only the targeted test file or single test — the full suite is the separate gate pass), gate results including not-run-with-reason, and an acceptance table backed by the reviewer's own evidence. On a `CLEAN` or `FIXED` verdict against a `convert-plan-to-feature` feature file it also writes that feature's Status cell to `done` in the initiative's `REQUIREMENTS.md` — a write outside the reviewed diff, so it is named explicitly in the report (a `NEEDS ATTENTION` verdict changes no Status cell). When run as a subagent, the report is the run's return value — findings never get lost as chat text. Ships `references/` (the seven-pass checklist, the tautology catalog, the report skeleton).

**Example.**

```
You: the subagent says feature 07 (list caching) is done and tested — verify before I merge
→ Claim audit: the "pages can never change" argument has 3 premises; 2 hold, 1 is false —
  the ordering column is a caller-supplied business timestamp, and two shipped paths
  backdate it, so a backdated record lands mid-list on a page the cache marked fresh.
  Fixed: removed the line, rewrote the comment to name both backdating paths, added a
  regression guard, mutation-proved it (re-adding the line fails: expected 2, received 1).
  Gates re-run green. VERDICT: FIXED — 1 finding, fixed in 2 commits on the branch.
```

**Pairs with.** [`convert-plan-to-feature`](#convert-plan-to-feature) — its feature files' acceptance criteria are this skill's highest-preference input; decompose the plan there, verify the implementation here. [`plan-eng-review`](#plan-eng-review) — the same gate discipline on the other side of implementation (see the [recommended workflow](#recommended-workflow--from-idea-to-verified-code)). [`verify-frontend-change`](#verify-frontend-change) — browser-level evidence for frontend work; this skill verifies at the code-and-criteria level.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill verify-implementation
```

**Full definition:** [`skills/verify-implementation/SKILL.md`](skills/verify-implementation/SKILL.md) (plus the verification checklist, tautology catalog, and report skeleton under `references/`). Distilled from the review brief used in a 20-feature internal Mi9 initiative (July 2026), where each feature was implemented by one subagent and independently reviewed by another — and the reviews repeatedly beat their implementers. Not adapted from an external project.

---

## `execute-change`

**What it does.** Executes a plan brief end to end in an OpenSpec-managed repository, unattended. It can also start one step earlier, from a raw idea: a research subagent reads the relevant code and returns a design dossier (every claim with a source — a file path, or a URL to a primary source such as official docs or a spec), the lead runs a categorized design interview (`[REC]`-marked defaults, one category per question) in rounds — each answer opens the next round's questions, a question that depends on a still-open one waits, and the interview ends only when nothing is open; a fact from the repo or the docs is looked up by a read-only subagent, never asked of you; a term that conflicts with the repo's `CONTEXT.md` glossary is challenged, a vague word gets one proposed canonical term, and an ADR is offered only for a decision that is hard to reverse, surprising without context, and a real trade-off — drafts the brief to `docs/up next/<date-time>-<slug>-plan.md` (with `## Glossary updates` and `## Decisions to record as ADRs` sections, and the research dossier appended verbatim as `## Research dossier` so later steps and a resumed run see the same facts the interview used), and waits for your approval — only an approved brief enters the pipeline. One lead session coordinates the whole feature routine — author the OpenSpec change from the brief (`/opsx:propose` flow; task groups are vertical slices sized to one fresh context window — a change too wide for vertical slices is sequenced expand–contract: add the new form beside the old, migrate call sites in batches of one task group each, remove the old form last — and the brief's glossary/ADR sections are written into `CONTEXT.md` and `docs/adr/`, committed with the change) → [`plan-eng-review`](#plan-eng-review) gate → resolve the review's open decisions with the user → apply the required changes (`/opsx:update` flow) → an independent did-the-changes-land check → implement task group by task group (a serial implementer runs the type check and the test files it touches often and the full suite once before reporting; a parallel implementer runs its verify clauses only, never the full suite — the lead runs the gates once after all groups) → [`verify-implementation`](#verify-implementation) audit of everything the run committed — the diff from the run's start commit (the commit `HEAD` pointed at when the run began, recorded in the ledger) to `HEAD`, not the base branch against the branch — with a bounded fix loop → behavior-preserving simplification pass → reconcile `tasks.md` and stop. Every authoring, review, implementation, audit, and simplification step runs in a fresh subagent with an empty context (putting the review's open decisions to you is the lead's own step) — the lead starts a subagent for every substantial task precisely to preserve its own context for the hours-long run; it never edits source itself, checks every "done" claim against evidence on disk, and commits per checkpoint by explicit pathspec on the run's branch. **Where the run works is a blocking question at preflight**, and its answer decides both that branch and the *run root* — the directory the run works in. Three options: reuse the current branch and checkout (recommended — commits go onto whatever branch is checked out now, no new branch and no new directory); create the run's own `agent/execute-change/<timestamp>-<plan name>` branch in the current checkout; or create that branch in a dedicated git worktree under `../<repo>.worktrees/`. Only the worktree keeps your main working tree out of the run. Pick either of the other two and the main working tree *is* the run root: you cannot keep working in the repo while the run executes, and two plans cannot run on that repo at the same time — the worktree is what makes concurrent runs possible, because git refuses to check one branch out twice. The question tells you two things before you answer: whether reusing the current branch would commit an hours-long autonomous change straight onto `main` or `master` (it says so, and does not block it), and whether the working tree is dirty — commits stage explicit paths, so your unrelated modified files are never committed, but every gate run executes against those changes and a pre-existing failure can then be blamed on the implementation, so committing or stashing first is the clean path. That question and the not-an-OpenSpec-repo one — both asked rather than printed as a notice you could scroll past — are the only two the preflight asks beyond its offers to install the OpenSpec CLI and the two companion skills: it otherwise prints a readiness line (brief, branch, base, run root, notification state) and starts — the manual invocation is the authorization, and concurrency is decided mechanically at implementation time from the task groups' file lists. Human decisions pause the run in one batched question per step — with Remote Control on, the question pushes to your phone, waits indefinitely, and survives machine sleep. A crash or interruption resumes from the run's ledger file at the last committed checkpoint, recreating the worktree if the run uses one and it is gone. Every piece of prose the subagents write for people to read — `proposal.md`, `design.md`, the spec deltas, `tasks.md`, `CONTEXT.md`, an ADR, a commit message body — is written free of AI writing tells, through the [`unslop`](#unslop) rules; no fact, number, or technical term is changed to satisfy that.

**Heartbeat and cleanup.** Installed as a plugin, the run also watches its own subagents. Three hooks — `SubagentStart`, `SubagentStop`, and a `Notification` hook matching `permission_prompt|agent_needs_input|idle_prompt` — fire in the lead session (not inside the subagent) and append one JSON line each to `<session project root>/.claude/execute-change-run.jsonl` — under the directory you started the session in, not the run root, because a hook reads the payload's `cwd`, which is that directory, and a file written inside a worktree was never found. After launching a subagent the lead arms a background watcher that re-reads that log every 180 seconds and stays quiet unless something is wrong: nine minutes with no new line, or one of those notifications. It prints one `alive: N agents running, oldest <age>` line every 30 minutes and exits once every subagent has stopped. Nine minutes of silence is not by itself a stall — `SubagentStart` fires once and nothing else arrives until `SubagentStop`, so an implementer working normally for 20 minutes looks identical to a stall in the log — so the lead lists its running agents first: an agent still running means it is working, and only an idle agent whose stop event never arrived starts the retry ladder (a status request, then a stop and one relaunch, then a pause that asks you). A permission prompt is never treated as a stall: only you can answer it, so the lead reports it at once and waits. A subagent's stop carries no success or failure signal, so a failed step is caught by the lead's own acceptance check, not by the watcher. On Windows, when the last subagent of a batch stops, a process sweep kills what that batch left running — a process qualifies only when all three of these hold: its command line contains the run root path or it descends from the current `claude` process, it started at or after the batch began, and its executable is one of `node`, `npm`, `npx`, `pnpm`, `yarn`, `bun`, `biome`, `eslint`, `tsc`, `vitest`, `jest`, `esbuild`, `dotnet`. Shells (`bash`, `sh`, `pwsh`) are deliberately not on that list: every process the sweep exists for is a node or dotnet process, and a shell is far more often the lead's own tooling, including the watcher itself. A process started as `node script.js` from inside the run root carries no run root path on its command line, so only the parent-chain rule catches it — Windows exposes no working directory for a running process.

**Requirements.** An OpenSpec-managed repo (`openspec/config.yaml`, or a store the CLI recognizes) — the preflight verifies the OpenSpec CLI is installed and current and offers to install/update it (`npm install -g @fission-ai/openspec@latest`) if not. The [`plan-eng-review`](#plan-eng-review) and [`verify-implementation`](#verify-implementation) skills installed (the preflight offers to install those too). Git — and, if you pick the worktree run root, worktree support (any modern git); that run then installs the project's dependencies in its fresh worktree before the gates run, a per-run setup cost the other two run roots do not have, because they use the dependencies already installed in the checkout. Your main working tree may stay dirty, but only the worktree run root leaves it alone: under the other two the gates execute against your uncommitted changes, so commit or stash first if you want a gate result you can trust. For the phone-push pauses: Remote Control plus "Push when actions required" enabled (one-time setup documented in `references/preflight.md`; without it the run still works, it just waits in the terminal). For the heartbeat and the process sweep: install this skill as a plugin (see above) — `npx skills add` copies the skill files without the hooks, and the run then has no stall watcher and no cleanup. The three hooks run `python`, which must be on the PATH and be Python 3. The process sweep is Windows-only; on macOS and Linux it exits without killing anything and the rest of the run is unaffected. The machine must be on and awake while steps execute.

**How to run.** **Manual-only** (`disable-model-invocation: true`) — an hours-long autonomous run that commits must never start off a description match. Invoke it explicitly:

```
/execute-change "docs/up next/csv-import-plan.md"       # existing brief → straight to the pipeline
/execute-change "add CSV import to the orders page"     # free-text idea → design interview → approved brief → pipeline
/execute-change                                         # no argument → lists docs/up next/*-plan.md candidates and asks
/execute-change "docs/up next/csv-import-plan.md"       # same brief again after a crash/interruption → resumes from the ledger
```

No tool restriction and no model pin — the lead needs its full tool set, and you launch it on the model of your choice (subagent steps default to Opus; implementation groups run on the model their `tasks.md` row names).

**Use it for.** Running the whole recommended workflow unattended in repos where OpenSpec owns the spec artifacts — from a finished brief or straight from an idea: start it, answer the design questions if you started from an idea, walk away, answer the occasional decision from your phone, come back to an audited, simplified, checkpoint-committed feature branch.

**What it does not do.** Deploy, push, open a PR, or archive the OpenSpec change — it stops after the local commits and hands you the remaining manual steps. Commit the plan brief or its ledger, or use `git add -A` (every commit stages explicit paths). Resolve design forks by assumption — open questions always pause the run. Run its pipeline outside an OpenSpec-managed repo — finding one is a blocking question at preflight, offering to stop and work without the skill (recommended) or to run `openspec init` here first; it never initializes a repo without asking. Choose where it works — the run root is your answer to a blocking preflight question, not a default it picks; only the worktree option keeps your main working tree out of the run, and either current-checkout option means the run commits in that tree and you cannot work there while it executes. Demand `bypassPermissions` — an unexpected permission prompt pausing and notifying is part of the design. Kill a process outside the sweep's allowlist, or one that started before the batch it is cleaning up after — a shell is never a candidate, and neither is the background dependency install that Step 0 starts and steps 1–5 run alongside. Act in any session that is not an `execute-change` run: with no run metadata file, or a session id that does not match the one recorded in it, the hooks exit and write nothing. Block a subagent from stopping — the hooks always exit 0.

**What it produces.** Checkpoint commits (OpenSpec artifacts, one commit per implemented task group, audit fix commits, the simplification pass, the `tasks.md` reconciliation) on the branch you chose at preflight — the branch already checked out, a new `agent/execute-change/<timestamp>-<plan name>` branch in that checkout, or that branch in a worktree under `../<repo>.worktrees/` which you remove after the PR. A `<plan path>.ledger.md` next to the brief recording branch, run root, the run's start commit (the full sha `HEAD` pointed at when the run began — what the step-7 audit diffs against), change ID, per-step outcomes, and decisions (you delete it at close-out). And a final report: verdicts per step, decisions taken, the commit list, and the remaining manual steps — which list `git worktree remove` only when the run used a worktree. In the directory you started the session in it also writes two run-state files under `.claude/`: `execute-change-run.json`, written once at Step 0 with the session id, the `run_root` path, branch, ledger path, and start time, and deleted at close-out — its absence is what keeps the hooks inert everywhere else — and `execute-change-run.jsonl`, the hook log, one JSON object per line of kind `start`, `stop`, `notify`, or `sweep`. Those two go there rather than in the run root because the hooks read the payload's `cwd`, which is the session's directory; a worktree sits outside it, so a file written there was never found and every hook stayed inert. Pick either reuse-checkout option and the two directories are the same anyway.

**Example.**

```
You: /execute-change "docs/up next/tenant-export-plan.md"
→ Preflight: OpenSpec 1.9.0 current, companions installed, push notifications on.
  Where should this run work? [1] reuse the current branch and checkout
  (recommended) [2] create branch
  agent/execute-change/20260813-1054-tenant-export-plan in this checkout
  [3] create that branch in a dedicated worktree.
  Working tree clean; current branch feature/tenant-export, not main.
You: 1
→ Readiness: branch feature/tenant-export, base main, run root
  C:\Develop\myapp — your own checkout, so do not work in it while the run executes.
  Step 1: change tenant-export authored (proposal, design, deltas, tasks.md).
  Step 2: plan-eng-review — NEEDS REVISION, 2 unresolved decisions.
  Step 3: [push to phone] 2 questions answered from the phone.
  Steps 4–5: changes applied, landing check 9/9 LANDED, re-review APPROVED. Commit 1.
  Step 6: groups 1–4 implemented (Opus ×3, Sonnet ×1), commits 2–5.
  Step 7: verify-implementation — FIXED (1 finding, fix commit).
  Step 8: simplify — 2 cleanups, gates green. Commit 7.
  Close-out: tasks.md reconciled (commit 8), validate --strict green. STOPPED.
  Manual next steps: deploy dev + smoke test, CLAUDE.md updates, delete brief
  + ledger, opsx:archive, PR. (No worktree to remove — this run reused the
  current checkout.)
```

**Pairs with.** [`plan-eng-review`](#plan-eng-review) and [`verify-implementation`](#verify-implementation) — the run invokes both as its gates. The [recommended workflow](#recommended-workflow--from-idea-to-verified-code) — this skill is that chain's unattended form for OpenSpec repos; [`convert-plan-to-feature`](#convert-plan-to-feature) is the equivalent decomposition step for repos *without* a mandated spec workflow.

**Install.**

```
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install execute-change@mi9-agent-skills
```

`npx skills add https://github.com/Mi9-LLC/agent-skills --skill execute-change` still installs the skill, but without the three hooks: no subagent log, so no stall watcher, and no process sweep. Pick one or the other — installing both registers two copies under the same name.

**Full definition:** [`skills/execute-change/SKILL.md`](skills/execute-change/SKILL.md) (plus the preflight/one-time-setup guide, the verbatim step-prompt templates, and the `CONTEXT.md`/ADR formats in `domain-docs.md` under `references/`). The three hooks and the process sweep are documented in [`hooks/README.md`](hooks/README.md). The source-per-claim, research-dossier-in-brief, expand–contract, and serial-vs-parallel test-running rules are adapted from [`mattpocock/skills`](https://github.com/mattpocock/skills) `research`, `implement`, and `to-tickets` (MIT, © 2026 Matt Pocock).

---

## `clear-and-short`

**What it does.** Cuts the number of words in Claude's chat replies without making them harder to read. The compression happens at the level of **which facts get stated**, never **how the words are formed**: preamble and pleasantries, tool-call narration ("now I will read X"), restating your question back at you, the same fact repeated in a heading and a bullet and a closing line, a closing summary on a reply that is already short, surveys of options that were never going to be recommended, decorative tables and emoji, long raw logs, and hedging all go. Full sentences, articles, correct verb forms, negations, numbers, file paths, and verbatim code and error strings all stay. It also writes in **simple English** for readers whose first language is not English: the common word over the rare synonym ("use" not "utilize"), one idea per sentence of about 20 words or fewer, no idioms or figurative verbs ("the fix is merged", not "the fix landed"), concrete names instead of umbrella words ("the system", "the pipeline"), technical terms kept as names and defined in plain words the first time they appear. Questions to the user are asked one at a time with numbered options and a `[REC]` default, so the answer can be one number. This is the deliberate opposite of telegraphic "caveman" compression: dropping articles saves roughly 5-8% of tokens and costs every reader real effort — most of all anyone reading in a second language — while the structural cuts save far more and cost nothing.

**Two entry points.** Asking for shorter replies ("be brief", "too many words") switches on every rule. Asking only for a less machine-sounding voice ("humanize your responses", "remove the AI tells", "stop writing like an AI") switches on the simple-English and no-AI-tells rules and leaves the length caps off: the request is for a different voice, not for less content, so nothing the answer needs is dropped. The no-AI-tells rules cover the tells that the simple-English ones miss: em dashes, "not just X, but Y", forced groups of three, AI vocabulary ("crucial", "delve", "robust", "seamless"), "serves as" instead of "is", puffery, bold-label lists that restate the line, sycophantic openers, feeling-words in place of facts, and colons used as mid-sentence connectors. Either request also switches the mode on for the rest of the session, and a later message asking for the other one adds it.

**The voice half is on by default.** With the plugin installed you do not have to ask for it: the hook emits the voice directive on the first prompt of every session, so replies are in plain voice from the start. It emits the voice directive and not the length one deliberately — this is a default, and a default must not silently drop content you never asked to lose. It emits once per session, not on every prompt: re-injecting the same text every turn adds nothing and would conflict with an explicit "normal mode" later in the session. Sessions already seen are recorded in `~/.claude/.clear-and-short-sessions.json`; entries older than 7 days are pruned, the file is written atomically, and a missing or corrupt file never blocks a prompt. A prompt that matches the skill's own patterns keeps today's behavior exactly — "be brief" still upgrades to the length rules, "normal mode" still turns the skill off — and it also closes out the default for that session, so the voice directive can never fire a turn later and tell Claude to drop length rules you just asked for.

**Three things hold the default back.** A first prompt that asks for the mode *off* — "normal mode", "stop clear-and-short", "stop being brief", "you can be verbose again", "back to normal" — now emits nothing and closes out the default for that session; before, such a prompt got the voice directive on the very message asking for the mode to be off. The default also fires only when the payload's `source` is `user`, or when `source` is absent so older payloads keep working: it no longer fires in `claude -p`, SDK runs, or automated eval harnesses, where it silently changed output being measured for something else — a prompt that explicitly matches the skill's patterns is still honored whatever the source. And setting the environment variable `CLEAR_AND_SHORT_NO_DEFAULT` to any non-empty value turns the default off while matched prompts keep working; that is the documented opt-out, where before the only way out was uninstalling the plugin.

**Requirements.** Install it as a plugin rather than with `npx skills add` (see above): the plugin carries the `UserPromptSubmit` hook that makes the mode switch on reliably. The hook runs `python`, which must be on the PATH and be Python 3 — on macOS and Linux, where the interpreter is often `python3` only, the hook does nothing and reports no error. The skill itself is purely behavioral and needs nothing: it changes how Claude writes, not what tools it can use.

**How to run.** With the plugin installed the voice half needs no request at all — it is on from the first prompt of every session (see above), and asking for shorter replies adds the length rules on top of it. To ask explicitly: `/clear-and-short`, or just ask for shorter or simpler replies ("be brief", "too many words", "use simple English"), or for a less machine-sounding voice ("humanize your responses", "remove the AI tells"). It then stays on for the rest of the session until you say "normal mode" or "stop clear-and-short" — it does not drift back to long form or to harder words as the session grows. Declares no `allowed-tools`/`disallowed-tools`.

**Use it for.** Spending your context budget on the work instead of on prose about the work — long agent sessions, repeated investigation summaries, and any workflow where you read many status reports. Also for keeping replies readable when English is not your first language: shorter, but still ordinary English sentences.

**Triggers on phrases like.** "be brief", "keep it short", "from now on keep it short", "shorter answers", "too many words", "stop repeating yourself", "you are too verbose", "use fewer tokens", "save tokens", "stop narrating every tool call", "use simple English", "plain English", "I am not a native speaker" — and, for the voice entry point, "humanize your responses", "remove the AI tells", "your replies sound like ChatGPT", "stop writing like an AI", "de-AI your answers", "no more em dashes". A phrase that names a file or document instead ("humanize this README", "de-AI the docs") goes to `unslop`, not here. It triggers on the first such request even when the same message also asks an ordinary question — answering shorter just once is not a substitute, because loading the skill is what makes the change hold for the rest of the session.

**What it does not do.** Shorten anything written for other people to read — code, comments, commit messages, documentation, PR/issue/ticket text, and memory files stay at normal length in normal prose; that prose is `unslop`'s job, and this skill owns only the length, wording, and AI tells of Claude's own chat replies. It also steps back to full prose on its own for security warnings, destructive or irreversible action confirmations, multi-step instructions you will follow by hand where the order matters, and whenever you repeat a question (a repeat means the short answer did not land, so it answers at greater length and in simpler words, not less). A shorter report never turns a partial result into a clean one: anything skipped, failed, uncertain, or assumed is still reported.

**What it produces.** No files or reports — a behavioral discipline that changes how Claude writes in the chat.

**Example.**

```
Normal:  I've finished looking into this. The issue you're running into is
         caused by the auth middleware, which is checking token expiry with
         a strict less-than comparison instead of less-than-or-equal. That
         means a token expiring exactly on the boundary is rejected. I've
         gone ahead and fixed that. Let me know if you'd like anything else!

clear-and-short:
         `auth/middleware.ts:42` compares token expiry with `<` instead of
         `<=`, so a token expiring on the boundary is rejected. Fixed.
         Tests pass.
```

**Install.**

```
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install clear-and-short@mi9-agent-skills
```

Restart the session, then type "be brief" to confirm the skill loads. Do not also run `npx skills add … --skill clear-and-short`: that installs a second copy under the same name, without the hook.

**Origin.** Adapted from [`juliusbrussee/caveman`](https://github.com/juliusbrussee/caveman) (MIT, © 2026 Julius Brussee). Caveman's structural cuts are kept (plus its rules against invented abbreviations and arrows, which save no tokens); its grammar compression and six intensity levels are dropped. It is roughly caveman's `lite` level, extended with the simple-English and question rules.

**Full definition:** [`skills/clear-and-short/SKILL.md`](skills/clear-and-short/SKILL.md). The hook is documented in [`hooks/README.md`](hooks/README.md).

---

## `unslop`

**What it does.** Edits prose to remove the patterns that mark text as AI-written. It works from a fixed list of 31 patterns in seven groups: **content** (puffery, name-dropping, "highlighting… / ensuring…" phrases, promotional adjectives, vague attributions, "despite challenges… continues to thrive"), **language** (AI vocabulary such as "delve", "crucial", "tapestry", "landscape"; "serves as / boasts" instead of "is"; "not just X, but Y"; forced groups of three; synonym cycling; false "from X to Y" ranges), **style** (em dashes, mid-sentence colons, bold on every noun, bold-label lists that restate the line, title-case headings, decorative emoji, curly quotes), **communication artifacts** (chatbot phrases, cutoff disclaimers, sycophantic openers), **filler** (phrases, hedging stacks, generic conclusions), **jargon** (abstract metaphor nouns such as "substrate", "wedge", "north star", "flywheel", with the concrete replacement for each), and **plain speech** (name the mechanism or number instead of the feeling, one idea per sentence, active voice, cut adverbs, the plain word). The process is: scan for the patterns, rewrite while preserving meaning and tone, then self-audit for anything still obviously machine-written.

**Requirements.** None. Behavioral — it changes how Claude edits and writes prose.

**How to run.** `/unslop` on a file or pasted text, or ask to "unslop", "de-AI", or "humanize" a piece of writing. Claude also applies it on its own when it writes a new documentation page, README, or announcement. Declares no `allowed-tools`/`disallowed-tools`.

**Use it for.** Documentation, README files, blog posts, announcements, emails, PR descriptions, release notes — anything people will read where "this was written by an AI" is a cost.

**Triggers on phrases like.** "unslop this", "make it sound less like AI", "remove the AI tells", "humanize this text", "de-AI the README", "this reads like ChatGPT wrote it". The same words aimed at Claude's own replies rather than at a piece of writing ("humanize your responses", "your answers sound like ChatGPT") belong to `clear-and-short` instead.

**What it does not do.** Touch code, code comments, commit messages, or Claude's own chat replies (their length, wording, and AI tells are `clear-and-short`'s job — the two skills are complementary: `clear-and-short` decides how much to say in chat, `unslop` cleans up prose written for other readers). It does not change the meaning, facts, numbers, or the established technical terms of the text, and it does not add opinions or a first-person voice the author did not write. A project style guide (for example a house rule on heading case) overrides any conflicting pattern.

**What it produces.** No files or reports of its own — it edits the text it is given in place, or returns the rewritten text when given a paste.

**Example.**

```
Before:  This groundbreaking release serves as a testament to our commitment to
         developer experience — delivering not just speed, but reliability and
         elegance. Experts agree it's a pivotal moment for the ecosystem.

After:   Version 3.0 cuts cold-start time from 900 ms to 120 ms and removes the
         three flaky retry paths reported in #412, #418, and #430.
```

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill unslop
```

**Origin.** Adapted from the `unslop` skill in [`cursor/plugins`](https://github.com/cursor/plugins/tree/main/pstack/skills/unslop) (`pstack`, MIT, © 2026 Lauren Tan). The 31-pattern list is kept as-is. Upstream's "Adding soul" section (have opinions, use "I", let some mess in) and its "must always apply" trigger are dropped: the first conflicts with the plain-facts style used across this catalog, the second would fire on every turn including code and chat.

**Full definition:** [`skills/unslop/SKILL.md`](skills/unslop/SKILL.md).

---

## Contributing

To add or modify a skill:

1. Create or edit a directory under `skills/<skill-name>/` containing a `SKILL.md` (YAML frontmatter with `name` + `description` + optional `allowed-tools`, plus a Markdown body). Long-form reference docs go under `skills/<skill-name>/references/`; helper scripts under `scripts/`. If the skill ships a standalone `skills/<skill-name>/README.md`, keep it in sync with the `SKILL.md` — divergent copies silently mislead users.
2. Add a row to the **Skills at a glance** table and a per-skill section to this README, mirroring the template every section above uses: *what it does*, *requirements*, *how to run*, *use it for*, *triggers on*, *what it does not do*, *what it produces*, *example*, *pairs with* (if any), *install*, *full definition*. Consumers discover skills from this README — an undocumented or vaguely-documented skill is effectively unshipped, and generates support questions.
3. Keep the table-row count, the `## ` section count, and the `skills/` directory count in agreement.
4. Open a PR against `main`. Teammates pick up the new version on their next `npx skills add … --skill <name>`.

**A skill that needs a hook also needs a plugin entry.** `npx skills add` installs skill files only, so a hook cannot reach a teammate that way. Put the hook script under `hooks/`, add the skill to `.claude-plugin/marketplace.json`, and declare the hooks **inline in that entry**, as an object mapping hook event names to matcher arrays — a marketplace entry rejects a hooks file path, and a hooks file at the repo root would load into every plugin here, because all entries use the repo root as their plugin root. Then document it in both [`hooks/README.md`](hooks/README.md) and the skill's section here — whose **Install** block must then show the `claude plugin` commands rather than `npx skills add`. [`clear-and-short`](#clear-and-short) and [`execute-change`](#execute-change) are the worked examples.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at. Tag releases (e.g. `v1.0.0`) only when you want to offer a `--ref`-able pin.

## License

[MIT](LICENSE).

## Documentation

For more on Claude Code Agent Skills, see the [official Anthropic documentation](https://code.claude.com/docs/en/skills) and [`anthropics/skills`](https://github.com/anthropics/skills) for the canonical layout.
