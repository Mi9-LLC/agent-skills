# Quadrant templates and mechanics

Read top-to-bottom before writing the first doc. Contents:

1. [Reference template + rules](#1-reference)
2. [Explanation template + rules](#2-explanation)
3. [How-to template + rules](#3-how-to)
4. [Tutorial template + rules](#4-tutorial)
5. [Anti-mixing table](#5-anti-mixing-table)
6. [Example-verification techniques](#6-example-verification-techniques)
7. [Doc-framework table](#7-doc-framework-table)
8. [Collision policy detail](#8-collision-policy-detail)

## 1. Reference

Information-oriented. The reader is working and needs a fact — a signature,
a default, a constraint. Factual, complete, derived directly from code.

```markdown
# [Entity Name]

[One paragraph: what it is, what it does, when you'd use it.]

## API / Interface

[Complete listing of the public surface: functions, commands, config
options, parameters. Include types, defaults, and constraints, pulled
directly from code — never paraphrased loosely.]

## Options / Configuration

[If applicable: every option with its type, default, and effect.]

## Examples

[2–3 concrete examples showing actual usage — code or commands that run
as written.]

## Related

[Links: the how-to(s) that use this surface, the explanation that
motivates it.]
```

Rules:

- Accuracy over elegance. Every claim traceable to code read this session.
- Types, defaults, constraints — always. "Accepts a string" is not
  reference-grade; "accepts a string (max 256 chars, must match
  `^[a-z-]+$`)" is.
- 100% of the named target's public surface. A reference doc with gaps is a
  trap: the reader assumes what's listed is all there is.
- Examples work if copy-pasted (see section 6 for the evidence classes).
- No *why*. Rationale belongs in explanation — link to it.

## 2. Explanation

Understanding-oriented. The reader wants to know why it works this way.
This is the design rationale.

```markdown
# [Concept / Design Decision]

[Opening paragraph: the problem this design solves, stated for a smart
reader who hasn't seen the code.]

## The problem

[What goes wrong without this design. Real failure modes, not abstract
risks.]

## The approach

[How the design solves it. Diagrams help here — see the diagram rule
below.]

## Trade-offs

[What was given up. Every design trades something — name it explicitly:
"chose X over Y because Z".]

## Alternatives considered

[Only if discoverable from code comments, ADRs, or git history: what was
tried or rejected, and why.]
```

Rules:

- Lead with the problem, not the solution.
- Diagrams: ASCII by default — grep-able, diff-friendly, renders
  everywhere. Mermaid only when the repo's existing docs already use it.
  Diagrams are exempt from execution, but every box and label names a real
  identifier (traced) — no invented components.
- Name trade-offs explicitly. An explanation that only praises the design
  is marketing.
- Don't repeat reference material — link to it.
- Alternatives-considered is evidence-bound like everything else: only what
  comments, ADRs, or history actually show. No invented rejected designs.

## 3. How-to

Task-oriented. The reader knows the basics and wants to accomplish one
specific thing.

```markdown
# How to [accomplish specific task]

[One sentence: what you'll accomplish and the end result.]

## Prerequisites

[What the reader needs before starting — versions, installed tools,
config state. Be specific.]

## Steps

1. [Action verb] [specific instruction]

   ```bash
   [exact command]
   ```

   [Expected output or result, if non-obvious.]

2. [Next step…]

## Verification

[How to confirm it worked: a command, a URL, a test to run.]

## Troubleshooting

[Common failure modes and their fixes — pulled from tests and
error-handling code, not imagination.]
```

Rules:

- Title starts with "How to" — no exceptions; it's the reader's entry
  point when scanning.
- Every step is actionable. Never "consider whether…" — always "Run X" or
  "Add Y to Z".
- Verification is always present. The reader never wonders "did it work?".
- Troubleshooting is mandatory whenever the task can fail.
- One goal per how-to. A second goal is a second how-to.

## 4. Tutorial

Learning-oriented. Takes a newcomer from zero to a working example. The
hardest quadrant to write, and the most valuable.

```markdown
# [Tutorial title — what you'll build/learn]

[Opening paragraph: what you'll build and why it's useful. Concrete —
"You'll build a working X that does Y", not "This tutorial covers X".]

## What you'll need

[Prerequisites: tools, versions, prior knowledge. Link installation
guides rather than inlining them.]

## Step 1: [Set up the foundation]

[Start from a clean state. Show every command; briefly say what each does
on first encounter.]

```bash
[exact command]
```

[What just happened, in one or two sentences.]

## Step 2: [First working piece]

[The reader sees something work within the first 3 steps.]

…

## What you built

[Recap what the reader now has and what it can do. Link to the reference
and how-to docs. Suggest a next step.]
```

Rules:

- **Time to first visible result ≤ 3 steps.** Slower means restructure.
- Every step produces a visible change or output — no silent
  configuration steps.
- Exact commands the reader types. Never "run the appropriate command".
- If a step commonly fails, show the error and the fix inline.
- Ends with "What you built" — connect back to the real use case.

## 5. Anti-mixing table

Each quadrant serves one reader in one mode. Content that drifts across
quadrants is the most common Diataxis failure. What does NOT belong:

| Quadrant | Does not contain |
|---|---|
| Reference | Step-by-step walkthroughs; rationale or "why"; persuasion; tutorial-style narration ("now let's…") |
| Explanation | Exhaustive option lists; copy-paste command sequences; step-by-step instructions |
| How-to | Teaching digressions; design rationale; exhaustive option tables (link to reference instead) |
| Tutorial | Exhaustive option lists; alternative paths ("you could also…"); reference tables; deep rationale |

When drafting, if a paragraph feels like it belongs to a different reader
mode, it belongs in a different file — move it and leave a link.

## 6. Example-verification techniques

Every example meets one of three classes (SKILL.md's iron law). Choose the
**highest feasible class**: executed > traced > illustrative.

### Executed

The example ran during this run, side-effect-free. What qualifies:

- Read-only commands: `--help`, `--version`, `--dry-run`, list/show/status
  subcommands.
- Code snippets run through the project's own test runner or a scratch
  script — with **caches, coverage, and output paths isolated to the
  scratchpad** (e.g. the runner's cache-dir flag, `-p no:cacheprovider`
  for pytest, coverage off), so the run leaves no trace in the repo.
- Run `git status --short` **before and after**. The two must match. If
  the run incidentally created anything (snapshot files, coverage folders,
  logs), delete it and re-check.

What never qualifies: commands that write to the repo, mutate a database,
call paid or external APIs, install packages, or need credentials.

Report note format: `executed: <exact command>`.

### Traced

Every identifier, signature, type, default, and constraint in the example
was read at a real `file:line` this session — not remembered, not
inferred from a name. This is the floor for all API claims in prose.

Report note format: `traced: src/x.ts:41` (the line where the claim
lives; multiple lines allowed).

### Illustrative

The concrete values are synthesized — a sample API response, mid-tutorial
file state, a simplified diagram — but the **shape is traced**: every
field name, type, and identifier verified at a `file:line`. The doc itself
labels it, e.g. `Example response (illustrative — field shapes from
src/api.ts:88):`. Never used where execution was feasible — a runnable
snippet presented as illustrative is a downgrade the gate should have
caught.

Report note format: `illustrative (shape traced: src/api.ts:88)`.

## 7. Doc-framework table

Detected at Step 0 (docs-home resolution, rung 3). Follow the framework's
format and register every new page in its nav — a page missing from the
sidebar is invisible no matter how good it is.

| Framework | Identifying config | Sidebar/nav to update | Format quirks |
|---|---|---|---|
| Docusaurus | `docusaurus.config.js` / `.ts` | `sidebars.js` / `sidebars.ts` (skip if autogenerated from folder structure) | `.md`/`.mdx`; front-matter `id`, `title`, `sidebar_position`; MDX parses JSX — escape raw `<` and `{` in prose |
| MkDocs | `mkdocs.yml` | the `nav:` section of `mkdocs.yml` itself | plain `.md`; paths in `nav:` are relative to `docs_dir` (default `docs/`); admonitions use `!!! note` |
| VitePress | `.vitepress/config.ts` / `.js` / `.mts` | `themeConfig.sidebar` in that same config | `.md` with Vue templating — `{{ }}` inside text needs `v-pre` or escaping; front-matter `title`, `outline` |
| Nextra | `next.config.js` importing `nextra` + a `theme.config` | `_meta.json` (or `_meta.js`) in the docs page folder | `.mdx` by default; pages live under `pages/` or `content/`; JSX parsing applies |

If the framework's config doesn't match any row (Sphinx, Hugo, Jekyll,
something bespoke), follow the same two moves — mimic an existing page's
format, find and update whatever file drives the nav — and say in the
report which convention was inferred from what.

## 8. Collision policy detail

A partition-plan row whose file already exists is an `extend` row. That
includes files this skill wrote in a previous or interrupted run — there
is no special resume mode; the new plan simply lists them as `extend` and
the merge below regenerates them to standard. It also includes an existing
doc that covers the target under a different name in the docs home: plan
that quadrant as `extend` on the existing file — two half-docs about the
same entity is the failure this policy exists to prevent.

Extend mechanics:

1. **Read the whole existing file first.** Never write into a file you
   haven't fully read this session.
2. **Merge under its structure.** Keep its heading order and voice. Add
   the template sections it's missing; merge new content into sections
   that already exist rather than duplicating them. Never delete an
   existing doc file, and never rewrite one wholesale — extension, not
   replacement.
3. **Preserve authored prose — except where it contradicts the code.**
   The user's wording, ordering, and emphasis survive. When the existing
   file mixes quadrant content (say, design rationale sitting inside a
   half-written API page), the prose may move verbatim to the file of the
   quadrant it belongs to — relocation is fine, deletion is not, and every
   move is stated in the report. The one carve-out:
   **code wins every factual or API claim, in any file this skill
   extends** — a name, default, type, or behavior statement that
   contradicts code read this session gets corrected in place. This is
   what makes extending safe: nothing true is lost, nothing false is
   preserved.
4. **Report every correction.** Each correction goes in the report's
   `Corrections:` field: what the file said, what the code says (with
   `file:line`), what the doc says now. A correction made silently is
   indistinguishable from an accidental rewrite.

The same code-wins rule covers the README: a stale claim sitting next to
the link line being added gets corrected and reported, not mirrored into
the new docs and not left contradicting them.
