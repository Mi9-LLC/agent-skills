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
- **`live-app-security-audit`** (`skills/live-app-security-audit/`) — Runtime audit of a deployed live URL. Seven checks: security headers, TLS, frontend-bundle secret search, localStorage tokens, unauthenticated endpoints, login rate-limit, username enumeration. **Read-only on the user's source tree**; writes only `audit/<YYYY-MM-DD>/live-audit.md` (mirrors `security-vulnerability-scan`'s path, so both reports live side-by-side). Active probes (rate-limit, enumeration) require explicit target-authorization at Step 0; uses RFC-reserved `.invalid` emails for probes. Designed as the runtime counterpart to `security-vulnerability-scan`.
- **`anti-sycophancy`** (`skills/anti-sycophancy/`) — Behavioral skill that swaps Claude into critical-thinking-partner mode for review/feedback/decision asks. Argues the strongest opposing case first, names untested assumptions, surfaces weaknesses before strengths, ends with a sit-with question. **No file output, no tool access** — purely shapes how Claude responds. Trigger description carved by `skill-creator`'s description-optimization loop against an Opus 4.7 eval set.
- **`update-dependencies`** (`skills/update-dependencies/`) — Research-first dependency updater for any JS/TS project. Supports npm, pnpm, yarn Classic, yarn Berry, and bun; auto-detects single-package or monorepo layout. **Manual-only** (`disable-model-invocation: true`; invoke with `/update-dependencies [package-names...]`). Operates exclusively on a dedicated `agent/update-dependencies/<ts>-<rand>` branch created from the auto-detected default branch; **never commits or pushes**. Ships `references/` docs: per-PM command table (`package-managers.md`) and lockstep-ecosystem families (`lockstep-ecosystems.md`).
- **`convert-plan-to-feature`** (`skills/convert-plan-to-feature/`) — Decomposes an approved plan into independently-trackable, per-feature implementation specs under a dedicated `docs/plans/<initiative>/` subfolder: a `REQUIREMENTS.md` index (context, blast radius, cross-cutting catalogs, deploy ordering, feature table) plus one `features/NN - <name>.md` file per unit of work, each with its own requirements, technical steps with real file paths, dependencies, and acceptance criteria. **Produces planning documents only — does not implement anything.** Invoke when a finished/approved plan exists (from plan mode or under `docs/plans/`) and the user wants it split into trackable features/tickets/specs.
- **`new-feature`** (`skills/new-feature/`) — Investigative Q&A workflow that turns a fuzzy feature request into a fully-specified design *before* any code is written. Researches the relevant code plus current best practices first, then surfaces every ambiguous design decision as categorized questions (A/B/C…) with `[REC]`-marked default options, one category per message, locking decisions as the user confirms — then transitions to planning with zero ambiguity left. **Design-only — writes no code itself**; hands off to plan mode. Declares no `allowed-tools` (unrestricted). No `references/`.
- **`sonar-issue-check`** (`skills/sonar-issue-check/`) — Reads SonarCloud / self-hosted SonarQube issues for the current repo and prints a terminal summary; by default the **new-code** issues on the current branch (the pre-commit / pre-PR "did I introduce a problem?" check), or `--all` for the full backlog. Runs a bundled zero-dependency Node script (`scripts/extract-sonar-issues.mjs`, built-in `fetch`); **read-only against the Sonar API** — it queries results, never triggers a scan and never modifies the repo (writes only when `--out <file>` is passed). Auto-detects project key/org/host from `sonar-project.properties` (falling back to `.vscode/settings.json`); reads the token from `SONAR_TOKEN` or a local `.env`. `allowed-tools: Bash, Read`. No `references/`.

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
