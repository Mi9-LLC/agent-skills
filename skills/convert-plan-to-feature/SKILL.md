---
name: convert-plan-to-feature
description: >-
  Break an approved plan into separately-trackable, per-feature implementation
  specs under a dedicated `docs/plans/<initiative>/` subfolder — a REQUIREMENTS.md
  index plus one `features/NN - <name>.md` file per unit of work, each with
  requirements, technical steps (real file paths), dependencies, and acceptance
  criteria. Use this WHENEVER the user has a finished/approved plan (from plan
  mode, or an existing plan file under docs/plans/) and wants it decomposed,
  split, broken down, or "turned into features/tickets/specs" for separate
  tracking. Trigger on phrases like "convert this plan into features", "split the
  plan up", "break this into per-feature files", "turn the plan into
  implementation specs", "make a feature breakdown", "/convert-plan-to-feature",
  or any request to take a single big plan and produce one trackable file per
  feature. Reach for this aggressively once a plan exists and the user signals
  they want it decomposed — don't hand-roll an ad-hoc folder layout when this
  skill encodes the conventions.
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
---

# Convert Plan → Per-Feature Specs

Take one approved plan and explode it into a folder of independently-trackable
feature specs. The plan answered *what* and *why*; this skill produces the
*per-unit-of-work execution surface* a team (or a fleet of implementation agents)
can pick up one file at a time without re-reading the whole plan.

**This skill produces planning documents only — it does not implement anything.**
Decomposing and writing the specs *is* the deliverable; stop there. Implementation
is a separate, later step driven from the feature files this skill produces.

## Why this shape

- **A dedicated `docs/plans/<initiative>/` subfolder** keeps each initiative
  self-contained, so concurrent efforts never overwrite each other's plans.
- **`REQUIREMENTS.md` as the index** holds everything cross-cutting (context,
  blast radius, shared catalogs, deploy ordering, the feature list) in one place,
  so a feature file can stay focused on *its* slice without duplicating it.
- **One file per feature** makes each unit of work separately assignable,
  reviewable, and closeable. A reviewer reads `03 - Gateway orchestration.md` in
  isolation and knows the file paths, the order of operations, what it depends on,
  and how to tell it's done.

## Workflow

### 1. Locate the source plan

The plan comes from one of two places — detect which:

- **A path the user gave**, or an existing file under `docs/plans/` (e.g.
  `docs/plans/2026-06-09-2016-store-release-rollback.md`). Read it end to end.
- **The approved plan in this conversation** (plan-mode output or a design the
  user just confirmed). Use the latest confirmed version, not an early draft.

If neither is clearly present, ask which plan to convert — don't guess. If a saved
plan file exists, prefer it over your memory of the conversation; it's the source
of truth.

### 2. Derive the initiative name and create the folder

- Initiative name = **kebab-case** distilled from the plan's title/subject, ticket
  prefix included when present (e.g. "Store Release Backup & Rollback (STF-555)" →
  `stf-555-store-release-rollback`). Keep it short and recognizable.
- Create `docs/plans/<initiative>/` and `docs/plans/<initiative>/features/`.
  (Convention: put plans under `docs/plans/` when the directory exists, or a
  top-level `plans/` as a fallback.)
- **Everything goes inside the `<initiative>/` subfolder.** Never write
  `REQUIREMENTS.md` or `features/` directly at the `docs/plans/` root — that's what
  keeps concurrent initiatives from colliding and is the whole point of the layout.
- Leave the original plan file where it is. `REQUIREMENTS.md` links back to it as
  the provenance record — don't move or delete it.

### 3. Decompose into features

A **feature** is a coherent, independently-implementable unit of work with its own
acceptance criteria — not an arbitrary slice.

**Reuse the plan's own seams first.** Well-formed plans already group work into
Phases, PR boundaries, or per-component sections (Contracts / Store Agent /
Gateway / Web Server). Those are your starting features. Split a phase into two
features only when it bundles genuinely separable work (e.g. "backup engine" and
"rollback engine" are two features even if one phase); merge phases only when one
is too thin to track alone.

Good seams to split on:

- **Deployable component / project boundary** (Contracts vs Gateway vs Store Agent
  vs installer).
- **Schema/contract changes vs the code that consumes them** — the contract bump
  is usually feature 01 because everything depends on it.
- **Independently shippable capability** (backup, rollback, reporting) even within
  one project.

Avoid: features so small they're a single edit, or so large they hide three
unrelated acceptance criteria. If you can't write a crisp "done when…" for it,
it's mis-cut.

**Order matters.** Number features in dependency/deploy order — contracts before
the agents that use them, installer-common before MSI projects, migrations before
the app code. The numeric prefix *is* the build order.

### 4. Write `REQUIREMENTS.md`

This is the index and the home for everything shared. Use this structure:

```markdown
# <Initiative Title>

> Source plan: [<filename>](<relative-or-absolute-path>)
> Generated: <YYYY-MM-DD>

## Context
<1–3 paragraphs: the problem and the goal, lifted/condensed from the plan.>

## Blast radius
<Which projects/components/files this touches; lockstep vs backward-compat notes.>

## Locked decisions
<The plan's confirmed design decisions, condensed. The "why" behind the features.>

## Cross-cutting catalogs
<Consolidated, NOT scattered into feature files: wire-contract/enum tables, JSON
settings keys, MSI property IDs, named-pipe message kinds, SignalR hub methods,
machine-role tokens, error/log codes. Feature files reference these by name.>

## Deploy / build ordering
<The order features must land in, and why. Mirror the feature numbering.>

## Features
| # | Feature | Depends on | Suggested model |
|---|---------|-----------|-----------------|
| 01 | [Contracts: protocol v3 bump](features/01%20-%20Contracts%20protocol%20v3%20bump.md) | — | Sonnet |
| 02 | [Store Agent: backup engine](features/02%20-%20Store%20Agent%20backup%20engine.md) | 01 | Opus |
| … | | | |

## Test strategy
<Unit vs integration, real vs mocked, CI vs local — from the plan.>

## Open questions / risks
<Carry forward anything the plan left unresolved. Don't silently drop unknowns.>
```

Keep the cross-cutting catalogs *here* and reference them from features by name.
Duplicating an enum table into five feature files guarantees they drift.

### 5. Write one file per feature

File name: `features/NN - <Feature Name>.md` (zero-padded number, spaces around the
dash, matching the prompt's `[feature number] - [feature name].md` shape). Use this
template:

```markdown
# Feature NN — <Feature Name>

**Initiative:** <initiative name> · **Depends on:** <feature #s or "none"> ·
**Suggested model:** <Opus/Sonnet/Haiku — with a one-line rationale>

## Requirement
<What this feature must deliver and why, in the user's terms. The behavioral
contract, not the implementation.>

## Interface contract
<**Consumes:** the upstream artifacts/types/endpoints/state this feature needs to
already exist — name each and which feature (#) produces it. **Produces:** the new
public surface this feature exposes for downstream features — types, method
signatures, endpoints, message kinds, settings keys, DB columns. Downstream features
cite these by name. If a feature consumes something no listed feature produces (and
it doesn't already exist), that's a gap — flag it rather than assume it.>

## Technical implementation
<Ordered, concrete steps. Real file paths (and line numbers when known). New types,
methods, signatures. The sequence within the feature. Reference shared catalogs in
REQUIREMENTS.md by name rather than re-pasting them. Call out any ordering
constraints with the broader deploy sequence. **Write complete steps — no
placeholders:** no `// TODO`, no "… rest unchanged", no "implement X here". If a
detail is genuinely unknown, log it under *Dependencies & notes* as an open question
instead of stubbing it into a step.>

1. …
2. …

## Acceptance criteria
<Objectively checkable "done when…" bullets. Behavioral + verifiable: builds clean,
specific tests pass, a named scenario produces a named outcome. Not "works".>

- [ ] …
- [ ] …

## Dependencies & notes
<Upstream features that must land first, downstream features that consume this,
and any risk/rollback note specific to this slice.>
```

Carry the plan's fidelity into the right feature: per-phase model recommendations
become the feature's *Suggested model*; PR-boundary notes become *Dependencies*;
test items become *Acceptance criteria*. Don't invent detail the plan didn't have —
if the plan was vague on a point, the feature file inherits that gap as an open
question rather than a fabricated spec.

### 6. Verify and report

- Re-read your output cold: every feature has file paths, dependencies, and
  checkable acceptance criteria; cross-cutting catalogs are consolidated in
  REQUIREMENTS.md, not scattered; deploy ordering is explicit.
- No placeholders survived: every step is concrete (no `// TODO` / "rest
  unchanged"); any genuine unknown is logged as an open question, not stubbed.
- Interface contracts line up: everything a feature lists under *Consumes* is
  *Produced* by an earlier-numbered feature (or already exists). A consume with no
  producer is a gap — fix the cut or flag it.
- Confirm every feature in the REQUIREMENTS.md table has a matching file and vice
  versa, and that the numbering reflects dependency order.
- Report the created tree and a one-line summary per feature. Flag anything the
  source plan left ambiguous instead of papering over it.

## Example

**Input:** an approved plan "Store Release Backup & Rollback (STF-555)" with phases
for Contracts, Store Agent, Gateway, and Web Server.

**Output:**

```
docs/plans/stf-555-store-release-rollback/
├── REQUIREMENTS.md
└── features/
    ├── 01 - Contracts protocol v3 bump.md
    ├── 02 - Store Agent backup engine.md
    ├── 03 - Store Agent rollback engine.md
    ├── 04 - Gateway rollback orchestration.md
    └── 05 - Web Server outcome reporting.md
```

`REQUIREMENTS.md` holds the wire-contract catalog, blast radius, and deploy order;
each feature file scopes one slice with its own steps and acceptance criteria.
