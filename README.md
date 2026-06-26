# Mi9 Skills

Mi9 LLC public catalog of Claude Code Agent Skills.

> **⚠️ Important:** Make sure you trust a skill before installing or running it. Skills can execute commands and read your files when triggered.

## Skills at a glance

| Skill | What it does |
|---|---|
| [`security-vulnerability-scan`](#security-vulnerability-scan) | [OWASP Top 10:2025](https://owasp.org/Top10/2025/) static scan of any codebase; writes `audit/<YYYY-MM-DD>/report.md`. |
| [`live-app-security-audit`](#live-app-security-audit) | Runtime audit of a deployed live URL — headers, TLS, bundle secrets, localStorage tokens, open endpoints, login rate-limit, account enumeration; writes `audit/<YYYY-MM-DD>/live-audit.md`. |
| [`anti-sycophancy`](#anti-sycophancy) | Behavioral mode for review/feedback/decision asks. Argues the opposing case first, names untested assumptions, refuses reflexive agreement. No file output. |
| [`update-dependencies`](#update-dependencies) | Research-first dependency updates for any JS/TS project (npm/pnpm/yarn/bun, single-package or monorepo). Reads real release notes, migrates code, verifies with quality gates. Manual-only (`/update-dependencies`). |
| [`convert-plan-to-feature`](#convert-plan-to-feature) | Decompose an approved plan into a folder of independently-trackable per-feature spec files — `REQUIREMENTS.md` index + one `features/NN - <name>.md` per unit of work, each with requirements, ordered implementation steps, acceptance criteria, and dependencies. |
| [`sonar-issue-check`](#sonar-issue-check) | Reads SonarCloud / self-hosted SonarQube issues for the current repo — by default the new-code issues on the current branch (pre-commit / pre-PR check), or `--all` for the full backlog. Zero-dependency Node script; read-only against the Sonar API. |
| [`sonar-issue-fix`](#sonar-issue-fix) | Companion to `sonar-issue-check` that *fixes* the findings: triages by rule, applies behavior-preserving mechanical fixes plus a characterization-tests-first refactor for cognitive-complexity issues, and re-verifies with the project's lint / type-check / test gates. Changes code; never alters runtime/wire behavior. |

---

## `security-vulnerability-scan`

**What it does.** OWASP Top 10:2025-aligned static vulnerability scanner. Detects common security issues across the relevant stack — web frameworks, IaC, container configs, dependency lockfiles, secrets — and writes a structured assessment to disk.

**Use it for.** PR reviews, periodic full-repo sweeps, onboarding to an unfamiliar codebase, or any "is there anything obvious" check. Designed to overtrigger rather than miss a real risk.

**Triggers on phrases like.** "review this code", "security review", "audit this app", "scan for vulnerabilities", "OWASP check", "find secrets", "harden security", "pentest this", "assess risk", "audit dependencies" — and casual variants ("what's broken here", "is this safe to ship").

**What it produces.**
- A Markdown report at `<project-root>/audit/<YYYY-MM-DD>/report.md` with severity-ranked findings (Critical / High / Medium / Low), OWASP A0X:2025 + CWE mappings, file:line citations, attack scenarios, remediations, and a prioritized fix list.
- **Read-only on the target source tree.** Never modifies source files, configs, dependencies, lockfiles, `.env*`, or `.gitignore` of the repo being scanned. The only write is `audit/`.
- If the working directory is empty, the skill asks for a GitHub URL and clones with `gh` before scanning.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill security-vulnerability-scan
```

**Pairs with.** [`live-app-security-audit`](#live-app-security-audit) — the runtime counterpart. This skill reads the source tree; `live-app-security-audit` probes the deployed instance. Run both for full coverage. Their reports land side-by-side under `audit/<YYYY-MM-DD>/`.

**Full definition:** [`skills/security-vulnerability-scan/SKILL.md`](skills/security-vulnerability-scan/SKILL.md) (plus per-category reference docs under `references/`).

---

## `live-app-security-audit`

**What it does.** Runtime security audit of a deployed, live web application. Walks seven checks against the running target — security headers, TLS / SSL Labs grade, frontend-bundle secret search (including the Supabase anon-vs-`service_role` triage), `localStorage` / `sessionStorage` token exposure, unauthenticated network endpoint inspection, login rate-limiting, and password-reset / login username enumeration — and writes a structured assessment to disk.

**Use it for.** Auditing a "vibe-coded" SPA you just shipped, verifying that build-time env vars didn't leak into the bundle, sanity-checking the production headers/TLS posture, and probing the most common runtime weaknesses on small / fast-shipped apps. Designed to be the runtime counterpart to `security-vulnerability-scan` — run both for full coverage.

**Triggers on phrases like.** "audit my live site", "audit https://…", "scan my deployed app", "are my API keys in the bundle", "Supabase anon key exposed", "check my security headers", "what's my SSL Labs grade", "JWT in localStorage", "test my login rate limit", "password reset enumeration", "vibe-coded app security check", "production security audit", "runtime security check".

**What it does not do.** Touch the live app's data. Run any active probe (rate-limit, enumeration) without an explicit authorization gate at Step 0. Continue against third-party targets — if the user can't confirm ownership or authorization, the skill stops.

**What it produces.**
- A Markdown report at `<project-root>/audit/<YYYY-MM-DD>/live-audit.md` with severity-ranked findings (Critical / High / Medium / Low / Informational), CWE mappings, exact evidence (redacted), attack scenarios, remediations, and a prioritized fix list. Mirrors `security-vulnerability-scan`'s report format so the two live side-by-side under `audit/<date>/`.
- **Read-only on the user's source tree.** Writes only to `audit/`. Never sends payloads beyond the documented probes; uses RFC-reserved `.invalid` email addresses for active probes so no real account is touched.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill live-app-security-audit
```

**Full definition:** [`skills/live-app-security-audit/SKILL.md`](skills/live-app-security-audit/SKILL.md) (plus per-check reference docs under `references/`).

---

## `anti-sycophancy`

**What it does.** Behavioral skill that swaps Claude into critical-thinking-partner mode. Instead of agreeing reflexively or hedging, Claude argues the strongest opposing case first, names the load-bearing untested assumption, surfaces weaknesses before strengths, refuses to retreat without new evidence or reasoning, and ends with a question worth sitting with — not a recap.

**Use it for.** Stress-testing your own judgment on decisions, plans, interpretations, or work you're about to commit to. The skill is the friction you'd ask a sharp colleague for — not the validation you'd get from a friendly one.

**Triggers on phrases like.** "should I", "I'm planning to", "I've decided", "what do you think", "is this the right call", "review my plan", "my read on this", "am I seeing this right" — plus explicit pushback asks: "play devil's advocate", "be brutal", "punch holes", "challenge me", "don't tell me it's a good idea". Confidence and stakeholder buy-in (`the team agrees`, `leadership signed off`) **amplify** activation rather than skip it.

**What it does not do.** Activate on objective technical questions with one knowable answer — syntax, config values, debugging, conversions, proofreading — even when phrased "is this correct?" Those need execution, not opposition.

**What it produces.** Nothing on disk. Purely a behavioral mode that shapes the conversational response.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill anti-sycophancy
```

**Full definition:** [`skills/anti-sycophancy/SKILL.md`](skills/anti-sycophancy/SKILL.md).

---

## `update-dependencies`

**What it does.** Research-first dependency updater for any JavaScript/TypeScript project. Detects the package manager (npm, pnpm, yarn Classic, yarn Berry, or bun) and workspace layout automatically, then classifies outdated packages into safe (patch/minor) and major groups, bulk-applies safe bumps with a green gate, and handles each major group individually — fetching real release notes and changelogs before touching anything, migrating code for breaking changes, reverting groups that won't go green, and producing a structured report.

**Use it for.** Keeping a project current without the manual archaeology of reading every changelog yourself. Good for periodic maintenance runs, pre-release dependency sweeps, or scoped single-package upgrades that need safe migration of breaking changes.

**Invocation.** This skill is **never auto-triggered** (`disable-model-invocation: true`). Invoke it explicitly:

```
/update-dependencies                    # update everything outdated
/update-dependencies zod                # scope to one package (+ its lockstep ecosystem)
/update-dependencies react vitest       # scope to multiple packages
```

**What it produces.**
- A safety branch `agent/update-dependencies/<timestamp>-<rand>` created from the auto-detected default branch. All changes land there — your working branch is never touched.
- A structured end-of-run report: Updated / Migrated / Skipped-Reverted / Warnings / Branch.
- **Never commits or pushes.** The branch is yours to review, squash, and merge on your own schedule.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill update-dependencies
```

**Full definition:** [`skills/update-dependencies/SKILL.md`](skills/update-dependencies/SKILL.md) (plus per-PM command reference and lockstep-ecosystem table under `references/`).

---

## `convert-plan-to-feature`

**What it does.** Takes a finished, approved plan — from plan mode, a conversation, or an existing file under `docs/plans/` — and decomposes it into a folder of independently-trackable per-feature spec files. The plan answered *what* and *why*; this skill produces the *per-unit-of-work execution surface*: a `REQUIREMENTS.md` index (context, blast radius, locked decisions, consolidated cross-cutting catalogs, deploy ordering, feature table with suggested models, test strategy, open questions) plus one `features/NN - <name>.md` per unit of work (requirement, ordered implementation steps with real file paths, objectively checkable acceptance criteria, dependency/risk notes).

**Use it for.** Decomposing complex plans so a team or a fleet of implementation agents can pick up one feature at a time without re-reading the whole plan. Each feature file is separately assignable, reviewable, and closeable.

**Triggers on phrases like.** "convert this plan into features", "split the plan up", "break this into per-feature files", "turn the plan into implementation specs", "make a feature breakdown", "decompose the plan", "create feature tickets from this plan", or any request to take a single big plan and produce one trackable file per feature.

**What it produces.**
- `docs/plans/<initiative>/REQUIREMENTS.md` — the shared index: context, blast radius, locked decisions, cross-cutting catalogs (wire-contract/enum tables, message types, error codes), deploy ordering, feature table with suggested models, test strategy, and open questions.
- `docs/plans/<initiative>/features/NN - <Feature Name>.md` — one file per feature: requirement, ordered technical steps with real file paths, objectively checkable acceptance criteria, and dependency/risk notes.
- **Planning documents only — no implementation.** The skill stops when the specs are written.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

**Full definition:** [`skills/convert-plan-to-feature/SKILL.md`](skills/convert-plan-to-feature/SKILL.md) · **README:** [`skills/convert-plan-to-feature/README.md`](skills/convert-plan-to-feature/README.md).

---

## `sonar-issue-check`

**What it does.** Runs a bundled, zero-dependency Node script that reads SonarCloud (or self-hosted SonarQube) issues for the repository you're in and prints a terminal summary — no Sonar web UI, MCP server, or extra install required. By default it reports only the unresolved issues introduced in the **new code** of the current git branch; `--all` dumps the full project backlog. Uses Node's built-in `fetch`, so it runs anywhere Node does.

**Use it for.** The "did I just introduce a problem?" check before you commit or open a pull request, pulling the Sonar findings for a specific branch or PR, filtering to bugs/vulnerabilities or high severities, or exporting results to JSON for a gate (`--fail-on-issues`).

**Triggers on phrases like.** "check sonar before I push", "what did sonarcloud flag on my branch", "any new code smells", "pull the sonar bugs for PR 123", "did I introduce any new issues", "show the quality-gate issues on this branch".

**What it does not do.** Run the Sonar scan itself — that happens in your CI pipeline; this skill only *reads* results. Modify the repo — it's read-only against the Sonar API and writes a file only when you pass `--out`. Configure SonarLint, quality-gate thresholds, or tokens.

**Configuration.** Auto-detects the project key, organization, and host from `sonar-project.properties` (the canonical scanner config), falling back to the SonarLint binding in `.vscode/settings.json`; reads the token from `SONAR_TOKEN` or a local `.env`. The `organization` parameter is sent only for SonarCloud — point `--host` at a self-hosted SonarQube server and it's omitted automatically.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill sonar-issue-check
```

**Full definition:** [`skills/sonar-issue-check/SKILL.md`](skills/sonar-issue-check/SKILL.md).

---

## `sonar-issue-fix`

**What it does.** The companion to `sonar-issue-check` that actually *resolves* the findings. Reads the branch's new-code issues, triages them by rule into **mechanical** (localized, recipe-driven edits) and **structural** (cognitive-complexity refactors), applies behavior-identical fixes, and re-verifies against the project's own lint / type-check / test gates. The hard constraint: a Sonar fix never changes runtime or wire behavior — these are code-quality smells, not bug fixes.

**Use it for.** Clearing the new-code smells/bugs on a branch before merge, making the quality gate green, or safely knocking out a specific cognitive-complexity warning. For structural fixes on untested code it writes **characterization tests first**, so the refactor is provably output-preserving — and those tests stay as permanent regression coverage.

**Triggers on phrases like.** "fix the sonar issues", "clear the sonarcloud findings on my branch", "resolve the new code smells before I merge", "make the quality gate green", "fix the cognitive complexity warning Sonar flagged", "knock out those Sonar issues".

**What it does not do.** Report-only inspection (that's `sonar-issue-check`). Change behavior — if a finding's correct fix is a real bug fix, it surfaces that to you instead of forcing a quality-pass edit. Commit or push unless you ask.

**Pairs with.** [`sonar-issue-check`](#sonar-issue-check) — the read-only sibling. Install both: check finds the work (this skill calls its script to fetch the findings), fix does it. If check isn't installed, paste the findings and it proceeds.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill sonar-issue-fix
```

**Full definition:** [`skills/sonar-issue-fix/SKILL.md`](skills/sonar-issue-fix/SKILL.md) (plus per-rule fix recipes and the complexity-refactor playbook under `references/`).

---

## Contributing

To add or modify a skill:

1. Create or edit a directory under `skills/<skill-name>/` containing a `SKILL.md` (YAML frontmatter with `name` + `description` + optional `allowed-tools`, plus a Markdown body). Long-form reference docs go under `skills/<skill-name>/references/`.
2. Add a row to the **Skills at a glance** table and a per-skill section to this README (mirror the format above: *what it does*, *use it for*, *triggers on*, *what it produces*, *install*, *full definition* link). Consumers discover skills from this README — an undocumented skill is effectively unshipped.
3. Open a PR against `main`. Teammates pick up the new version on their next `npx skills add … --skill <name>`.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at. Tag releases (e.g. `v1.0.0`) only when you want to offer a `--ref`-able pin.

## License

[MIT](LICENSE).

## Documentation

For more on Claude Code Agent Skills, see the [official Anthropic documentation](https://code.claude.com/docs/en/skills) and [`anthropics/skills`](https://github.com/anthropics/skills) for the canonical layout.
