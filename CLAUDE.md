# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is the **Mi9 LLC public catalog of Claude Code Agent Skills**, hosted on GitHub at `github.com/Mi9-LLC/agent-skills`. Teammates and external users install individual skills with:

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill <skill-name>
```

It is **not** application code. There is no build, test, or lint pipeline — the entire repo is Markdown skill definitions. Do not invent commands; there are none to run.

## Layout

Flat skills layout, matching the canonical [`anthropics/skills`](https://github.com/anthropics/skills) example:

- `skills/<name>/SKILL.md` — the **skill definition** (YAML frontmatter with `name`, `description`, `allowed-tools` + Markdown body that's loaded into the model when the skill triggers).
- `skills/<name>/references/` — on-demand reference docs the skill reads itself when it needs the detail. Keep these out of `SKILL.md` so the always-loaded body stays small.

There are no plugin manifests, no `.claude-plugin/` directory, and no top-level catalog file. Adding any of those would mix two distribution mechanisms — see "Distribution mechanism" below for why we don't.

## Current skills

- **`security-vulnerability-scan`** (`skills/security-vulnerability-scan/`) — OWASP Top 10:2025 static scanner. **Read-only on the target source tree**; writes only `audit/<YYYY-MM-DD>/report.md`. Never modifies source files, configs, lockfiles, or `.gitignore` of the repo being scanned.
- **`live-app-security-audit`** (`skills/live-app-security-audit/`) — Runtime audit of a deployed live URL. Seven checks: security headers, TLS, frontend-bundle secret search, localStorage tokens, unauthenticated endpoints, login rate-limit, username enumeration. **Read-only on the user's source tree**; writes only `audit/<YYYY-MM-DD>/live-audit.md` (mirrors `security-vulnerability-scan`'s path, so both reports live side-by-side). Active probes (rate-limit, enumeration) require explicit target-authorization at Step 0; uses RFC-reserved `@example.invalid` emails for probes. Designed as the runtime counterpart to `security-vulnerability-scan`.
- **`anti-sycophancy`** (`skills/anti-sycophancy/`) — Behavioral skill that swaps Claude into critical-thinking-partner mode for review/feedback/decision asks. Argues the strongest opposing case first, names untested assumptions, surfaces weaknesses before strengths, ends with a sit-with question. **No file output, no tool access** — purely shapes how Claude responds. Trigger description carved by `skill-creator`'s description-optimization loop against an Opus 4.7 eval set.
- **`update-dependencies`** (`skills/update-dependencies/`) — Research-first dependency updater for any JS/TS project. Supports npm, pnpm, yarn Classic, yarn Berry, and bun; auto-detects single-package or monorepo layout. **Manual-only** (`disable-model-invocation: true`; invoke with `/update-dependencies [package-names...]`). Operates exclusively on a dedicated `agent/update-dependencies/<ts>-<rand>` branch created from the auto-detected default branch; **never commits or pushes**. Ships `references/` docs: per-PM command table (`package-managers.md`) and lockstep-ecosystem families (`lockstep-ecosystems.md`).
- **`convert-plan-to-feature`** (`skills/convert-plan-to-feature/`) — Decomposes an approved plan into independently-trackable, per-feature implementation specs under a dedicated `docs/plans/<initiative>/` subfolder: a `REQUIREMENTS.md` index (context, blast radius, cross-cutting catalogs, deploy ordering, feature table) plus one `features/NN - <name>.md` file per unit of work, each with its own requirements, technical steps with real file paths, dependencies, and acceptance criteria. **Produces planning documents only — does not implement anything.** Invoke when a finished/approved plan exists (from plan mode or under `docs/plans/`) and the user wants it split into trackable features/tickets/specs.
- **`new-feature`** (`skills/new-feature/`) — Investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written. Researches the relevant code plus current best practices first, then surfaces every ambiguous design decision as categorized questions (A/B/C…) with `[REC]`-marked default options, one category per message, locking decisions as the user confirms — then transitions to planning with zero ambiguity left. **Design-only — writes no code itself**; hands off to plan mode. Declares no `allowed-tools` (unrestricted). No `references/`.
- **`sonar-issue-check`** (`skills/sonar-issue-check/`) — Reads SonarCloud / self-hosted SonarQube issues for the current repo and prints a terminal summary; by default the **new-code** issues on the current branch (the pre-commit / pre-PR "did I introduce a problem?" check), or `--all` for the full backlog. Runs a bundled zero-dependency Node script (`scripts/extract-sonar-issues.mjs`, built-in `fetch`); **read-only against the Sonar API** — it queries results, never triggers a scan and never modifies the repo (writes only when `--out <file>` is passed). Auto-detects project key/org/host from `sonar-project.properties` (falling back to `.vscode/settings.json`); reads the token from `SONAR_TOKEN` or a local `.env`. `allowed-tools: Bash, Read`. No `references/`.
- **`sonar-issue-fix`** (`skills/sonar-issue-fix/`) — Companion to `sonar-issue-check` that **changes code to resolve** the findings. Triages the new-code issues by rule into *mechanical* (localized, recipe-driven edits) and *structural* (cognitive-complexity refactors), applies behavior-identical fixes, and re-verifies against the project's own lint / type-check / test gates. Hard constraint: **never changes runtime or wire behavior** — code-quality smells only, not bug fixes; genuine bugs are surfaced, not force-fixed. Structural refactors on untested code are **characterization-tests-first** (lock current output with a snapshot, refactor to byte-identical output, keep the tests as regression coverage). Recipes are JS/TS today; the workflow is language-agnostic. Calls `sonar-issue-check`'s script to fetch findings when installed, else accepts a pasted list. `allowed-tools: Read, Edit, Write, Bash, Grep, Glob`. Ships `references/`: per-rule fix recipes (`rule-fixes.md`) and the complexity-refactor playbook (`refactor-playbook.md`). **Does not commit or push.**
- **`trim-initial-bundle`** (`skills/trim-initial-bundle/`) — Gets heavy vendor libraries **off a React + Vite app's initial JavaScript load** when they're only needed behind a lazy route/component (shrinks first-load size, LCP, TTI). Decides everything from the **built `dist`** via a bundled zero-dependency Node analyzer (`scripts/analyze-initial-load.mjs` — computes the entry's static-import closure, ranks initial-load chunks, flags vendor-looking deferral candidates), then diagnoses the leak (eager import / un-tree-shaken barrel re-export / `manualChunks` hoist), applies the matching fix **on approval**, and verifies against rebuilt artifacts. **Vite/Rollup/Rolldown only** (not Next.js/Webpack). `allowed-tools: Bash, Read, Edit, Write, Grep, Glob`. Ships `references/` (`diagnosis-and-fixes.md`, `verification.md`).
- **`scaffold-claude`** (`skills/scaffold-claude/`) — Interview-driven `CLAUDE.md` author. Walks eight sections (header, stack, commands, architecture, conventions, hard constraints, doc pointers, gotchas) **one at a time**, capturing only non-obvious edge cases and tribal knowledge with the *reason* behind each — never facts derivable from the manifest/tree/README. **Iron Rule: never write a section from inference; ask, and leave a `<!-- TODO -->` stub on skip.** Writes a reviewable draft to `docs/scratchpad/CLAUDE.md` (never the repo root); the user moves it. For large repos, scaffold the root then run the interview per subsystem for nested `CLAUDE.md` files (Claude Code lazy-loads them). For `AGENTS.md`, keeps it in sync with `CLAUDE.md` via `@import`/symlink rather than maintaining a drifting copy. `allowed-tools: Read, Glob, Grep, Write` — **no shell, Windows-clean by construction.** Ships `references/` (interview scripts + an annotated one-shot example) and `templates/`. Vendored from `ragnar-pwninskjold/tech-snacks` (MIT, © 2026 Sean Kochel); adapted to be CLAUDE.md-focused and shell-free. **Does not edit an existing CLAUDE.md or write to the repo root.**
- **`systematic-debugging`** (`skills/systematic-debugging/`) — Root-cause-first debugging discipline adapted from `obra/superpowers` (MIT, © 2025 Jesse Vincent). Four phases: root-cause investigation → pattern/context analysis → single tested hypothesis → fix the cause behind a failing test. **Iron law: no fix without root-cause investigation first; after 3 failed fixes, stop and question the architecture rather than trying a 4th.** Decoupled from the superpowers hook/dispatcher/sibling skills; **Windows-clean** (no unix-only shell to run); examples for **.NET/xUnit + TS/Vitest**. Ships `references/` (root-cause-tracing, defense-in-depth, condition-based-waiting). `allowed-tools: Read, Grep, Glob, Bash, Edit`.
- **`test-driven-development`** (`skills/test-driven-development/`) — **Opt-in** red-green-refactor discipline adapted from `obra/superpowers` (MIT, © 2025 Jesse Vincent). Write a failing test → watch it fail for the right reason → minimal code to pass → refactor; with a rationalization-rebuttal table and anti-pattern guidance. **Deliberately narrow trigger:** fires only on an explicit TDD ask or a new feature the user wants built test-driven — never on every edit, routine bug fix, or trivial change. Decoupled from the superpowers hook/dispatcher; examples for **.NET/xUnit + TS/Vitest** with Windows-friendly commands. Ships `references/testing-anti-patterns.md`. `allowed-tools: Read, Write, Edit, Bash, Grep, Glob`.

## Contributing

1. Create or edit a directory under `skills/<skill-name>/`. Include a `SKILL.md`; put long-form reference docs under `references/`.
2. **When adding (or renaming/removing) a skill, update ALL catalog docs in the same change — this is mandatory, not optional:**
   - `README.md` — add a row to the **Skills at a glance** table *and* a full per-skill section (mirror the existing format: *what it does*, *use it for*, *triggers on*, *what it does not do* / *what it produces*, *install*, *full definition* link). The README is how consumers discover skills — an undocumented skill is effectively unshipped.
   - This `CLAUDE.md` — add a bullet to the **Current skills** list above.
   - Keep the table-row count, the `## ` section count, and the `skills/` directory count in agreement.
3. Open a PR against `main`. Teammates pick up changes on their next `npx skills add … --skill <name>`.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at.

## Distribution mechanism

This repo distributes **only** via `npx skills`. The earlier Bitbucket-hosted `mi9-plugins` marketplace (using `.claude-plugin/marketplace.json` + `/plugin install`) was retired because the Claude Code TUI's `/plugin install` flow hit a "source type not supported" bug that blocked teammates from installing through the UI. The skills-only model bypasses that flow entirely.

If we ever need to ship non-skill components (agents, hooks, MCP servers, LSP) from the same repo, the two options are:

1. Add a `.claude-plugin/marketplace.json` back alongside the flat `skills/` tree (dual-mode — `anthropics/skills` itself does this), or
2. Split into a second repo.

Not in scope today; flagged for future reconsideration.
