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

### What happens

1. Derives a kebab-case initiative name from the plan title (ticket prefix included when present).
2. Creates `docs/plans/<initiative>/` and `docs/plans/<initiative>/features/`.
3. Writes `REQUIREMENTS.md` — the shared index: context, blast radius, locked decisions, cross-cutting catalogs, deploy/build ordering, feature table with suggested models, test strategy, and open questions.
4. Writes one `features/NN - <Feature Name>.md` per unit of work — requirement, a Consumes/Produces interface contract, ordered implementation steps with real file paths (no placeholders), objectively checkable acceptance criteria, and dependency/risk notes.
5. Verifies consistency (every feature in the table has a file; numbering reflects dependency order) and reports the created tree with a one-line summary per feature.

**Produces planning documents only — does not implement anything.**

## What It Does

### Planning documents, not implementation

The skill's scope ends when the spec files are written. A finished feature file tells an implementation agent (or a developer) exactly what to build, in what order, and how to tell it's done — without re-reading the entire plan. Implementation is a separate step driven from those files.

### Seam detection

The skill reuses the plan's own natural boundaries — Phases, PR boundaries, or per-component sections — as feature seams rather than inventing an arbitrary decomposition. It splits a phase into two features only when the work is genuinely separable; it merges thin phases into one when they don't stand alone.

Good seams: deployable component boundaries, schema/contract changes before the code that consumes them, independently shippable capabilities (backup vs rollback vs reporting). Bad seams: a single-edit feature, or a feature hiding three unrelated acceptance criteria.

### Dependency ordering

Features are numbered in build/deploy order — contracts before the agents that consume them, shared libraries before dependent projects, migrations before app code. The numeric prefix is the build order, not a cosmetic label.

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
| Features table | Number, title (linked to the feature file), dependencies, suggested model |
| Test strategy | Unit vs integration, real vs mocked, CI vs local |
| Open questions / risks | Anything the plan left unresolved, carried forward explicitly |

### `docs/plans/<initiative>/features/NN - <Feature Name>.md`

One file per unit of work. Sections:

| Section | Content |
|---------|---------|
| Header | Initiative, dependencies, suggested model with rationale |
| Requirement | What the feature delivers and why, in behavioral terms |
| Interface contract | **Consumes** (upstream types/endpoints/state, and which feature produces each) and **Produces** (the public surface downstream features cite by name) |
| Technical implementation | Ordered steps — real file paths, new types/methods, sequence within the feature; complete steps, no `// TODO`/placeholder |
| Acceptance criteria | Objectively checkable "done when…" bullets |
| Dependencies & notes | Upstream/downstream features, risk, rollback notes |

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
| 2. Derive initiative | Kebab-case name from plan title (ticket prefix included); create `docs/plans/<initiative>/` and `features/` subdirectory |
| 3. Decompose | Reuse the plan's own phase/component seams; split or merge only when warranted; number in dependency/deploy order |
| 4. Write REQUIREMENTS.md | Context, blast radius, locked decisions, consolidated catalogs, deploy ordering, feature table, test strategy, open questions |
| 5. Write feature files | One `features/NN - <name>.md` per feature — requirement, Consumes/Produces interface contract, ordered steps with real file paths (no placeholders), checkable acceptance criteria, dependencies |
| 6. Verify & report | Cross-check table vs files; report created tree with one-line summaries; flag ambiguities from the source plan |

## Configuration

### Frontmatter

```yaml
name: convert-plan-to-feature
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
```

### Folder convention

The skill writes to `docs/plans/<initiative>/` by default. If `docs/plans/` does not exist in the repository, it falls back to a top-level `plans/` directory. The original plan file is never moved or deleted — `REQUIREMENTS.md` links back to it as the provenance record.

## Install

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill convert-plan-to-feature
```

## Related

- [`update-dependencies`](../update-dependencies/README.md) — if your plan includes a dependency upgrade step, run this skill to scope the feature first, then invoke `/update-dependencies` within that feature's branch.

## Learn More

- [All Skills](../../README.md)
