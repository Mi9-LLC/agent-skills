---
name: document-generate
description: >-
  Write documentation FILES — Diataxis tutorials, how-to guides, reference
  pages, and explanations — for a named feature, module, file, or whole project,
  grounded in end-to-end code research done before a word of prose; also adds a
  short cross-link line in the README or docs index. Use whenever the user wants
  docs produced or refreshed: "write docs for this", "generate documentation",
  "document this feature / module / project", "create a tutorial for X", "write
  a how-to for X", "add reference docs", "update the docs to match the code". Do
  NOT trigger for: answering a how-does-X-work question in conversation (just
  answer it — no files are wanted), authoring CLAUDE.md or AGENTS.md agent
  context (scaffold-claude), designing a feature that is not built yet
  (new-feature), or decomposing an approved plan into feature specs
  (convert-plan-to-feature).
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# document-generate

Research the whole, then write the parts. Take one named feature, module, or
project, read its implementation and its tests end-to-end, decide what a
reader needs in each of the four Diataxis quadrants, get the partition plan
approved, and only then write the documentation files — every example
verified, every claim traceable to code read this session.

**Write surface: documentation files in the resolved docs home, plus minimal
cross-link lines in the README and any existing docs index or sidebar —
nothing else. CLAUDE.md and AGENTS.md are never edited (agent context is
`scaffold-claude`'s job). Nothing is committed or pushed. And no doc file is
written before the partition plan is approved.**

Bash is for read-only research and side-effect-free example execution only —
never `git commit`, never `git push`, never anything that mutates the repo.

## Why this skill exists

Documentation written without research describes half the feature — the half
that happened to come up. Documentation written without structure mixes a
tutorial's hand-holding into the reference table and buries the API surface
inside a narrative. And examples typed from imagination don't run. Each
failure mode has a specific counter here: archaeology before prose, one
Diataxis quadrant per reader mode, and an evidence class for every example.

The four quadrants:

- **Tutorial** — learning-oriented: takes a newcomer to a working result.
- **How-to** — task-oriented: accomplishes one specific goal.
- **Reference** — information-oriented: the complete, factual surface.
- **Explanation** — understanding-oriented: why it works the way it does.

## The iron law — no unverified example, no untraceable claim

Every example and factual claim in the docs meets one of three evidentiary
classes, in strict preference order:

1. **Executed** — the example actually ran, side-effect-free, during this
   run.
2. **Traced** — every identifier, signature, type, default, and constraint
   in it was read at a real `file:line` this session. API claims in prose
   always meet at least this bar.
3. **Illustrative** — concrete values are synthesized (a sample API
   response, the state a multi-file tutorial reaches mid-way, a simplified
   diagram), but the *shape* is traced: every field and identifier in it
   verified at a `file:line`, and the doc labels the example illustrative.
   Never used where execution was feasible.

The law binds anything presented as copy-pasteable code or literal API
surface. Explicitly-labeled pseudo-code and ASCII/Mermaid diagrams are
exempt from execution, but their identifiers must still be real (traced). An
example that meets no class gets rewritten until it does, or cut — and if
cutting it would gut a quadrant the partition matrix prescribes, surface
that tension at the approval gate; never silently thin an approved plan.
Verification notes go in the completion report, not the doc files.

## Workflow

### Step 0 — Scope, artifact, and docs home

**Which artifact is wanted.** A bare "document this project / this repo"
with no signal about the artifact means one clarifying question before any
research: human-facing docs (this skill), a CLAUDE.md / agent-context file
(`scaffold-claude`), or a session handoff (`session-handoff`)? Ask once,
then proceed on the answer.

**Diff- and PR-anchored asks.** "Update the docs for this PR" / "document
the changes I just made" — don't auto-proceed from the diff. Ask the user to
name the features or modules to document, and say why: documentation
describes the code as it exists now; a diff can point at targets, but it is
not the documentation source.

**The target.** A named feature, module, or file — or the whole project on
an explicit whole-project ask. Never silently widen scope: documenting the
named target completely beats documenting the project thinly.

**Docs home resolution**, first match wins:

1. **Target-local convention** — the target's package/module tree or its
   siblings already keep docs somewhere (a per-package `docs/`, a
   `references/` pattern): mirror the nearest sibling.
2. **Repo-level `docs/`** — follow its existing layout and naming.
3. **Doc-framework config** (Docusaurus / MkDocs / VitePress / Nextra —
   identification table in the references file): follow its format and
   register new pages in its sidebar/nav.
4. None of the above → plain Markdown under a new root `docs/`.

Genuinely ambiguous — two live conventions, or an unclear target — ask.

### Step 1 — Codebase archaeology (never skipped)

The quality of the docs is bounded by this step, and no documentation prose
is written before it completes.

1. Map the structure with Glob (works on every platform; no shell piping).
2. Read the entry points: README, the manifest (package.json /
   pyproject.toml / *.csproj / go.mod), main entry files, existing docs.
3. Read the target's implementation **end-to-end** — not just signatures.
4. Read the target's tests — they encode intended behavior and edge cases.
5. Read what the target depends on and what depends on it.
6. Harvest design-intent comments: `NOTE:`, `WHY:`, `DESIGN:`.
7. Build the concept map:

   ```
   Target: [feature/module name]
   Purpose: [one sentence — what problem it solves]
   Key concepts: [the 3–5 things a reader must understand]
   Public surface: [functions, commands, options, endpoints]
   Dependencies / dependents: [what it needs; what relies on it]
   Edge cases: [from tests and error paths]
   Design decisions: [non-obvious "why" choices]
   ```

8. Close with: "Researched N files, K public-surface items, M concepts,
   J design decisions."

### Step 2 — Diataxis partition and the approval gate

Classify each entity to document and apply the decision matrix:

| Entity type | Tutorial? | How-to? | Reference? | Explanation? |
|---|---|---|---|---|
| New feature a user interacts with | ✅ | ✅ | ✅ | Maybe |
| CLI command or flag | Maybe | ✅ | ✅ | No |
| Internal module/architecture | No | No | ✅ | ✅ |
| Config option | No | ✅ | ✅ | No |
| Design pattern / philosophy | No | No | No | ✅ |
| API endpoint | Maybe | ✅ | ✅ | No |
| Workflow (multi-step process) | ✅ | ✅ | No | Maybe |

Emit the partition plan — one row per entity-quadrant pair the matrix
prescribes, with the action and the exact file path:

```
Partition plan:
  entity        quadrant     action  file
  csv parser    reference    new     docs/reference-csv-parser.md
  csv parser    how-to       new     docs/how-to-parse-large-files.md
  csv parser    explanation  extend  docs/design.md (exists — merge)
```

**Collisions are `extend` rows.** A planned file that already exists — from
a previous run or under a different name — becomes an `extend` row, not a
new file. Merge mechanics live in `references/quadrant-templates.md` §8,
"Collision policy detail".

**Iron-law tensions surface here.** If a matrix-prescribed quadrant cannot
be produced to the evidence standard (execution infeasible and the shape
untraceable), flag that row in the plan with the proposed resolution —
illustrative-labeled examples, or dropping the quadrant — and let the user
decide at the gate. Never silently thin the plan after approval.

**The gate.** One AskUserQuestion, batched: approve as-is / adjust / cancel.
"Adjust" gets one follow-up asking which rows to drop, re-quadrant, or
re-path. Split into more calls only if the tool's four-question limit forces
it. **If the question cannot be asked or goes unanswered, stop: write
nothing, and report exactly what was blocked.** There is no doc-count
threshold below which the gate is skipped.

A re-run after an interruption is just a normal run: partially-written files
surface as `extend` rows in the new plan and are regenerated to standard.

### Steps 3–6 — write, in this order

Read [`references/quadrant-templates.md`](references/quadrant-templates.md)
now — the four templates, per-quadrant rules, and the anti-mixing table live
there. Write reference first: it establishes the vocabulary every other
quadrant links to. Then explanation, then how-to, then tutorial. The
completion report states the order actually followed.

- **Step 3 — Reference.** Covers 100% of the target's public surface, with
  types, defaults, and constraints at the grade of "accepts a string (max
  256 chars, `^[a-z-]+$`)" — never just "accepts a string". No *why*; that
  belongs in explanation.
- **Step 4 — Explanation.** Leads with the problem, names trade-offs
  explicitly ("chose X over Y because Z"), and links to reference instead of
  repeating it.
- **Step 5 — How-to.** Title starts with "How to", every step is actionable,
  a Verification section always, Troubleshooting whenever the task can fail.
- **Step 6 — Tutorial.** Visible result within 3 steps, every step shows a
  change, exact commands the reader types, ends with "What you built".

### Step 7 — Cross-link and discoverability

- Cross-quadrant links: reference ↔ how-to both ways; tutorial links to
  both.
- One link line per new doc in the README's documentation section. **If the
  README has no such section, append a minimal `## Documentation` section —
  heading plus link lines, nothing else — and say so in the report.**
- Update the docs index / sidebar when one exists (a doc framework's
  `nav`/sidebar config counts).
- CLAUDE.md and AGENTS.md: never.
- Every new doc reachable within 2 clicks from the README.
- Broken-link check: every `](path)` target in the new and extended docs
  exists on disk.

### Step 8 — Quality gates

Fix failures before reporting — don't report them as caveats.

- **Accuracy** — every example appears in the report's verification list
  with its evidence class; every API description matches code read this
  session; no stale names from renamed or removed entities.
- **Completeness** — reference covers 100% of the named target's public
  surface; how-tos cover the top tasks a reader would attempt; the tutorial
  reaches a working result in ≤3 steps.
- **Voice** — written for a smart reader who hasn't seen the code; jargon
  glossed on first use; active voice; "You can now…", never "The system
  provides…".

### Step 9 — Report; never commit

End with a structured summary:

```
Documentation generated:
  Scope: [target]
  Files: [N new] / [M extended]
  Quadrants: reference [n], explanation [n], how-to [n], tutorial [n]
  Order followed: reference → explanation → how-to → tutorial
  Quality gates: accuracy PASS / completeness PASS / voice PASS
  Examples verified:
    - executed: [exact command]
    - traced: src/x.ts:41
    - illustrative (shape traced: src/x.ts:88)
  Corrections: [every place existing docs or README contradicted the code —
    what it said, what the code says, what the doc says now]
  Not done (outside write surface): [suggested edits to files this skill
    won't touch, e.g. a stale code comment or a CLAUDE.md line]
```

**Secrets.** Examples never contain live-format credentials — placeholder
format only (`sk-...EXAMPLE`, `AKIA...EXAMPLE`). A live-format string found
in source while documenting is never copied into a doc: put a placeholder in
the doc and note the finding in the report.

**Never commits, never pushes — staging included.** No `git add`, no
`git commit`, no `git push`. This skill needs Edit and Bash to do its job,
so unlike this catalog's read-only skills there is no `disallowed-tools`
belt enforcing its never-rules — they are workflow discipline, and they bind
exactly as written.

## When NOT to use this skill

- **"How does X work?" asked in conversation** — answer it in the
  conversation. No files are wanted; produce none.
- **CLAUDE.md / AGENTS.md / agent context** — `scaffold-claude`.
- **Designing a feature that doesn't exist yet** — `new-feature`; this skill
  documents code as it exists.
- **Splitting an approved plan into feature specs** —
  `convert-plan-to-feature`.
- **An automated stale-docs sweep across a diff** — not in this catalog;
  Step 0 redirects a diff-anchored ask to named targets.

## Worked example

Ask: "document the retry helper in src/retry.ts".

Archaeology closes with a concept map:

```
Target: retry helper (src/retry.ts)
Purpose: wraps an async fn with capped exponential backoff
Public surface: retry(fn, opts) — opts.maxAttempts (default 3),
  opts.baseDelayMs (default 100), opts.retryOn (default: all errors)
Edge cases: maxAttempts=0 throws RangeError (retry.test.ts:71)
```

Partition: a public API surface → the API-endpoint row (how-to ✅,
reference ✅, tutorial Maybe — not warranted for a single helper,
explanation No):

```
entity        quadrant   action  file
retry helper  reference  new     docs/reference-retry.md
retry helper  how-to     new     docs/how-to-retry-flaky-calls.md
```

Gate approved as-is → two files written, one link line added to the
README's `## Documentation`. Report excerpt:

```
Examples verified:
  - executed: node examples/retry-demo.mjs
  - traced: src/retry.ts:12 (RetryOptions fields and defaults)
Corrections:
  - README said the default maxAttempts is 5; src/retry.ts:14 says 3.
    README line corrected; both new docs state 3.
```

---

Adapted from the `/document-generate` skill in
[`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT, © 2026 Garry
Tan). Rebuilt for this catalog: the commit / push / PR-body-update tail is
dropped (this skill never commits); the `gstack-redact` binary becomes the
placeholder-credentials rule; the confirm-only-above-5-docs threshold
becomes an always-on partition-plan approval gate; the accuracy checkbox
becomes the executed / traced / illustrative evidence rule; the
boil-the-ocean default narrows to complete-for-the-named-target; upstream's
recommended inline-summaries-plus-standalone-files output narrows to
standalone files plus minimal link lines; and the gstack machinery
(preamble, telemetry, brain sync, question tuning, learnings, checkpoint
mode, context recovery, `/document-release` chaining) is dropped.
