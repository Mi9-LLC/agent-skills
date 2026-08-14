# Convert Plan to Feature Specs Skill

> Decompose an approved plan into a folder of independently-trackable per-feature spec files — `REQUIREMENTS.md` index + one `features/NN - <name>.md` per unit of work

## Quick Start

### Invocation

Claude triggers this skill automatically when you ask to decompose a finished plan:

```
# After approving a plan in plan mode
convert this plan into features

# With a saved plan file
split up docs/plans/2026-06-09-my-initiative.md into feature specs

# Other trigger phrases
break this into per-feature files
turn the plan into implementation specs
make a feature breakdown
/convert-plan-to-feature
```

The skill reads the plan from the conversation (plan-mode output or approved design) or from a file path you give it. If neither is clearly present, it asks before proceeding.

**When not to use:** in a repository that mandates its own spec workflow (e.g. OpenSpec repos, where the change's `tasks.md` owns the breakdown). There, port this skill's execution rigor — the model rubric, parallel groups, acceptance criteria, and standing implementer instructions — into that artifact instead of creating a parallel breakdown that would drift from it.

### What happens

1. Derives a kebab-case initiative name from the plan title (ticket prefix included when present).
2. Creates `<plan-location>/<initiative>/` and `<plan-location>/<initiative>/features/` — checking the repository's own plan location first (its CLAUDE.md and existing folders; e.g. some repos use `docs/up next/`), defaulting to `docs/plans/`. If the initiative folder already exists, it re-runs instead of overwriting: reads the existing `REQUIREMENTS.md` first, preserves the Status value of every feature it re-emits, and asks before overwriting any feature file whose status is past `todo` (unanswered = not overwritten, reported as skipped).
3. Writes `REQUIREMENTS.md` — the shared index: context, blast radius, locked decisions, cross-cutting catalogs, deploy/build ordering, feature table with suggested models, parallel groups (same group = no dependencies between them = safe to implement concurrently), and a Status column (`todo` / `in progress` / `done` / `blocked` — the initiative's status board), test strategy, and open questions.
4. Writes one `features/NN - <Feature Name>.md` per unit of work — requirement, a Consumes/Produces interface contract, ordered implementation steps with real file paths (no placeholders), objectively checkable acceptance criteria (a feature that modifies existing behavior must name its regression test in one of them), dependency/risk notes, its parallel group in the header, and a fixed *Standing instructions for the implementer* block (verbatim in every file: ask rather than resolve open questions by assumption; verify external library/API behavior against current documentation, not internal knowledge; the file's acceptance criteria are the verification contract `verify-implementation` runs against, so mid-feature scope changes are written back into them).
5. Re-reviews every suggested model in a dedicated second pass against the quality-first rubric — Opus is the default; Sonnet only for fully-specified single-component work; Haiku only for purely mechanical edits; any underestimation signal (shared contracts, cross-component work, concurrency/caching/migrations/auth, modified existing behavior, open questions) forces Opus; when in doubt between two tiers, the higher one wins. The plan's own per-phase recommendations are input, not authority.
6. Verifies consistency (every feature in the table has a file; numbering reflects dependency order; parallel groups match the dependency data) and reports the created tree with a one-line summary per feature, including any model assignment the second pass changed.

**Produces planning documents only — does not implement anything.**

## What It Does

### Planning documents, not implementation

The skill's scope ends when the spec files are written. A finished feature file tells an implementation agent (or a developer) exactly what to build, in what order, and how to tell it's done — without re-reading the entire plan. Implementation is a separate step driven from those files.

### Seam detection

The skill reuses the plan's own natural boundaries — Phases, PR boundaries, or per-component sections — as feature seams rather than inventing an arbitrary decomposition. It splits a phase into two features only when the work is genuinely separable; it merges thin phases into one when they don't stand alone.

Good seams: deployable component boundaries, schema/contract changes before the code that consumes them, independently shippable capabilities (backup vs rollback vs reporting). Bad seams: a single-edit feature, or a feature hiding three unrelated acceptance criteria.

### Dependency ordering

Features are numbered in build/deploy order — contracts before the agents that consume them, shared libraries before dependent projects, migrations before app code. The numeric prefix is the build order, not a cosmetic label.

Concurrency is marked separately: the *Parallel group* column groups features with no dependencies between one another, so an implementation fleet can run a whole group concurrently without re-deriving the dependency graph.

### Consolidated catalogs

Cross-cutting shared data — wire-contract/enum tables, JSON settings keys, named-pipe message kinds, SignalR hub methods, error codes — lives in `REQUIREMENTS.md`, not scattered across feature files. Feature files reference shared catalogs by name, so they can't drift.

## What It Produces

### `docs/plans/<initiative>/REQUIREMENTS.md`

The initiative index. Sections:

| Section | Content |
|---------|---------|
| Context | Problem and goal, condensed from the plan (1–3 paragraphs) |
| Blast radius | Which projects/components/files are touched; lockstep vs backward-compat notes |
| Locked decisions | The plan's confirmed design decisions; the "why" behind the feature breakdown |
| Cross-cutting catalogs | Consolidated shared data — enums, contract tables, message types, error codes |
| Deploy / build ordering | The order features must land in, and why |
| Features table | Number, title (linked to the feature file), dependencies, parallel group (assigned mechanically: 1 + highest dependency group; same group = may run concurrently), suggested model (quality-first: Opus by default, cheaper tiers only for work that fully qualifies, re-reviewed in a second pass), and status (`todo` / `in progress` / `done` / `blocked` — the initiative's status board, updated as features close) |
| Test strategy | Unit vs integration, real vs mocked, CI vs local |
| Open questions / risks | Anything the plan left unresolved, carried forward explicitly |

### `docs/plans/<initiative>/features/NN - <Feature Name>.md`

One file per unit of work. Sections:

| Section | Content |
|---------|---------|
| Header | Initiative, dependencies, parallel group, suggested model with rationale |
| Requirement | What the feature delivers and why, in behavioral terms |
| Interface contract | **Consumes** (upstream types/endpoints/state, and which feature produces each) and **Produces** (the public surface downstream features cite by name) |
| Technical implementation | Ordered steps — real file paths, new types/methods, sequence within the feature; complete steps, no `// TODO`/placeholder |
| Acceptance criteria | Objectively checkable "done when…" bullets; a feature that modifies existing behavior names the regression test covering the changed path |
| Dependencies & notes | Upstream/downstream features, risk, rollback notes |
| Standing instructions for the implementer | Fixed text, verbatim in every file: don't resolve open questions by assumption — ask or return the feature; verify external library/API behavior against current docs, not internal knowledge; the acceptance criteria are the verification contract `verify-implementation` checks against, so a mid-feature scope change is written back into them |

## Usage Examples

### Example 1: Convert a plan-mode output

```
You: [approves a plan in plan mode]
You: convert this plan into features

Skill:
  Initiative: stf-555-store-release-rollback
  Created docs/plans/stf-555-store-release-rollback/
  ├── REQUIREMENTS.md
  └── features/
      ├── 01 - Contracts protocol v3 bump.md
      ├── 02 - Store Agent backup engine.md
      ├── 03 - Store Agent rollback engine.md
      ├── 04 - Gateway rollback orchestration.md
      └── 05 - Web Server outcome reporting.md

  01 — Contracts: add BackupRequest/BackupResponse + RollbackRequest/RollbackResponse to the shared contract project. Everything else depends on this.
  02 — Store Agent: implement the backup engine that responds to BackupRequest and writes the snapshot.
  03 — Store Agent: implement the rollback engine that responds to RollbackRequest and restores from snapshot.
  04 — Gateway: orchestrate backup/rollback across stores — fan-out, collect results, aggregate status.
  05 — Web Server: surface the outcome (success/partial/failure) to the operator UI.

  ⚠ Open question carried from plan: rollback ordering across stores not specified — feature 04 notes this as a risk.
```

### Example 2: Convert a saved plan file

```
You: split up docs/plans/2026-06-10-auth-rewrite.md into feature specs

Skill:
  Read docs/plans/2026-06-10-auth-rewrite.md
  Initiative: auth-rewrite
  Created docs/plans/auth-rewrite/
  ├── REQUIREMENTS.md
  └── features/
      ├── 01 - Database schema migration.md
      ├── 02 - Auth service rewrite.md
      ├── 03 - API gateway middleware.md
      └── 04 - Frontend session handling.md
```

## The Workflow

| Step | Action |
|------|--------|
| 1. Locate source | Read the plan from a file path the user gave, an existing `docs/plans/` file, or the approved plan in the conversation. Ask if unclear. |
| 2. Derive initiative | Kebab-case name from plan title (ticket prefix included); create `<plan-location>/<initiative>/` and `features/` subdirectory (repo's own plan location first, `docs/plans/` default). Folder already exists ⇒ re-run: read the existing REQUIREMENTS.md, preserve Status values, ask before overwriting any feature past `todo` |
| 3. Decompose | Reuse the plan's own phase/component seams; split or merge only when warranted; number in dependency/deploy order |
| 4. Write REQUIREMENTS.md | Context, blast radius, locked decisions, consolidated catalogs, deploy ordering, feature table, test strategy, open questions |
| 5. Write feature files | One `features/NN - <name>.md` per feature — requirement, Consumes/Produces interface contract, ordered steps with real file paths (no placeholders), checkable acceptance criteria, dependencies |
| 6. Verify & report | Cross-check table vs files; report created tree with one-line summaries; flag ambiguities from the source plan |

## Configuration

### Frontmatter

```yaml
name: convert-plan-to-feature
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
```

`AskUserQuestion` is what the re-run path uses to ask before overwriting a feature file that is already past `todo`.

### Folder convention

The skill checks the repository's own plan location first (its CLAUDE.md and existing folders — e.g. some repos keep plans in `docs/up next/`) and uses it when one exists; otherwise it writes to `docs/plans/<initiative>/`, falling back to a top-level `plans/` directory when `docs/plans/` does not exist. The original plan file is never moved or deleted — `REQUIREMENTS.md` links back to it as the provenance record. When the initiative is fully done, follow the repository's docs contract for the folder — many repos prune implemented plans (git history is the record).

## Install

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

## Related

- [`update-dependencies`](../update-dependencies/README.md) — if your plan includes a dependency upgrade step, run this skill to scope the feature first, then invoke `/update-dependencies` within that feature's branch.

## Learn More

- [All Skills](../../README.md)
