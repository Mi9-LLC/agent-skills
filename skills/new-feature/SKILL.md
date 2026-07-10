---
name: new-feature
description: >-
  Investigative Q&A workflow that turns a fuzzy feature request into a
  fully-specified design before any code is written. Research the relevant code
  + current (as-of-today) best practices first, then surface every ambiguous
  design decision as categorized questions with [REC]-marked default options,
  locking decisions as the user confirms. Leave zero ambiguous areas before
  transitioning to planning. Use this skill whenever the user proposes a new
  feature, capability, significant refactor, or any non-trivial change — even if
  they don't explicitly ask for design questions. Trigger phrases include "new
  feature", "design / scope / plan a feature", "add capability", "analyze
  options", "think hard about", "investigate", "before we implement", "what do
  you think about adding X", or any request where the user wants to reason
  through a design before coding. Do NOT trigger for tiny, obvious one-line
  changes (a rename, a trivial fix) with no real design surface. Invoke
  aggressively for substantive requests.
disallowed-tools: Edit, Write, NotebookEdit
---

# New Feature Investigation

A disciplined Q&A workflow that transforms a fuzzy feature request into a fully-specified design, ready for the planning phase. The core idea: eliminate every ambiguous decision *before* any code is written, using marked recommendations to keep the conversation fast while giving the user full control.

## Why this workflow

Design decisions made implicitly during coding cause two failure modes:

1. **Architectural dead-ends** discovered mid-implementation, forcing rewrites.
2. **Subtle misalignments with user intent** that surface only after delivery.

This skill forces those decisions to the surface early, while course correction is cheap. The `[REC]` marker is the efficiency mechanism — users can skim, say "agreed with all recommended", and keep moving. Questions they disagree on get real attention. Without recommendations, every question requires the user to do independent analysis from scratch, which is exhausting and slow.

## Core workflow

### Phase 1 — Research before the first question

Do this silently, before asking anything. Gather:

1. **Codebase context.** Read the files that touch the feature area. Use `Glob` + `Grep` to find surrounding code. Use the `Agent` tool with `subagent_type: Explore` for broad codebase questions where you'll need more than ~3 queries to understand. Read the CLAUDE.md / AGENTS.md files at repo root + relevant subfolders — they encode invariants the user won't repeat in the conversation. Check auto-memory files for prior architectural decisions.

2. **Current best practices (as-of today).** Use `WebSearch` or the `Context7` MCP tools for library documentation. Don't assume training-data knowledge — protocols, APIs, frameworks, and security patterns evolve. This is especially critical for anything touching OS APIs, security, concurrency, modern language features, or third-party services.

3. **Implicit constraints.** Read related plans in `docs/plans/`, recent git history, and any project-specific handoff documents. Previous architectural decisions likely still apply; asking the user to re-explain them is a sign of skipped research.

Open the conversation with a one-sentence plan so the user knows what you're doing, e.g., "Verifying existing orchestration logic before listing decision points." Then research. Then ask the first category.

### Phase 2 — Round-by-round Q&A

Structure every set of open questions as a **category** (letters A, B, C, ...) containing numbered **sub-items** (A1, A2, ...). Ask one category per message. Inside a category, enumerate options with `[REC]` marking the recommended default and a short reason:

```
## Question N — Category X, <topic>

**X1. <sub-item label>.**
  - (a) Option one — short consequence.
  - (b) **[REC]** Option two — why this is recommended.
  - (c) Option three — consequence.

**X2. <next sub-item>.**
  - **[REC]** Direct recommendation — why.
  - (Alt: alternative approach — when it'd apply.)

Confirm X1–X<n>.
```

Key rules:

- **Every multiple-choice question gets a `[REC]`.** Commit to a default. "I'm not sure" is a signal to research more, not to punt.
- **Even questions with no alternatives show a `[REC]` with reasoning.** This confirms you thought about it and the user hasn't overlooked a subtlety.
- **Short, parallel option phrasing.** The user should skim in seconds.
- **Group tightly-coupled sub-items in the same category.** If answering X1 changes how X2 is worded, ask them together.
- **End every category message with `Confirm X1–Xn`** so acknowledgements are unambiguous.

### Phase 3 — Full punch list on demand

After the first few categories, the user typically asks for the full scope of remaining decisions. Produce a **punch list** — every outstanding design decision, grouped by category, one terse line each:

```
### F. Contract changes
- **F1.** Add new enum values.
- **F2.** Schema version bump decision.
- **F3.** Forward path to upstream systems.
- **F4.** Backward-compat strategy during rollout.

### G. Installer
- **G1.** State folder creation mechanism.
- **G2.** Install location.
- **G3.** Self-update preservation.
```

Then keep asking one category at a time. The punch list gives the user scope visibility without drowning them in answers, and lets them redirect the order if they want.

### Phase 4 — Lock-in summaries after each answer

Open each new message with a one-line summary of what was just locked. This anchors the conversation state and lets the user spot capture errors immediately:

```
A1–A4 locked with your amendments:
- A1: atomic write via tmp-then-rename.
- A2: per-module storage.
- ...
```

If the user revised a recommendation, call out the revision explicitly in the summary. If the user introduced a new constraint, restate it so you both agree on what it means.

### Phase 5 — Transition to planning

When the punch list is empty:

1. Announce it explicitly: "All questions closed."
2. Collect any info needed to write the plan file — often the user's local wall-clock time for filename conventions like `YYYY-MM-DD-HHMM-slug.md`. Check the project's CLAUDE.md for conventions.
3. Enter plan mode per project conventions. Many repos require switching to Opus and producing a plan with a recommended Claude model per phase (Opus / Sonnet / Haiku) and a brief rationale.
4. Do not start writing code until the plan is approved.

## Recommendation hygiene

A good `[REC]` is:

- **Grounded in the research you already did.** Reference specific files, docs, or prior decisions briefly.
- **Context-aware.** "Keep per-module because the existing schema already separates them" beats "per-module is cleaner".
- **Honest about tradeoffs.** If the recommendation has downsides, name them so the user can override intelligently.
- **Not the most conservative choice by default.** Choose what's actually best given the context, not what minimises your risk of being wrong.

Bad recommendation:
> (b) **[REC]** Safer option.

Good recommendation:
> (b) **[REC]** Atomic write via tmp-then-rename. `File.Move(..., overwrite: true)` is atomic on NTFS; matches the existing `DeployStateStore` pattern; zero contention risk because the caller already holds the module lock.

## Question design patterns

**Enumerate, don't open-ask.** "How should we handle errors?" is dead weight. Force yourself to enumerate 2–4 concrete options with consequences, then pick one as `[REC]`.

**Batch tightly-coupled sub-items.** Questions that inform each other belong in the same category message. Asking them separately risks the user giving contradictory answers.

**Verify claims inline when stakes are high.** If you're about to recommend something based on a memory or a CLAUDE.md note, check the current code first. Recommendations based on stale memory are worse than no recommendation.

**Ask for concrete examples when you need them.** If the user's answer requires you to know a specific process name, command line, or config value to make a good recommendation, ask for it. Don't guess.

## Examples from practice

### Example — a single question with enumerated options

Full worked example (Windows session-token launch flow): `references/examples.md`. Shorter version, same shape:

> ## Question 3 — Category B, retry policy
>
> **B1. Retry strategy for a transient write failure.**
>   - (a) Fail fast — surface the error immediately. Simple, but pushes retry logic onto the caller.
>   - (b) **[REC]** Exponential backoff, 3 attempts, capped at 2s. Matches the existing `HttpClient` policy elsewhere in this codebase; covers the transient-failure window without masking a real outage.
>   - (c) Infinite retry with backoff. Risks masking a genuine outage as a hang.

Every sub-item has enumerated options, one carries `[REC]` with a concrete reason. User can skim, agree, or redirect.

### Example — punch list

> ### A. Capture / persistence
> - **A1.** Concurrent-capture safety — two deploys near-simultaneously. File lock vs atomic write.
> - **A2.** Per-module vs per-machine identity storage.
> - **A3.** Corrupt JSON recovery.
> - **A4.** Retention on auto-heal overwrite.

Terse, one line per sub-item, no answers yet. Lets the user see the full scope.

### Example — lock-in summary

> A1–A4 locked:
> - A1: atomic write via `.tmp` then `File.Move(overwrite: true)`.
> - A2: per-module storage (matches existing schema).
> - A3: treat corrupt JSON as "no record" + warn + fall through to sniff.
> - A4: discard old on overwrite; warning message to Gateway carries old→new audit trail.

Short, explicit, easy to correct if any was captured wrong.

## What not to do

- **Don't skip research and let the user fill in what you could have discovered.** "What process does the app spawn?" is a reasonable question only *after* you've read the deployment class and still can't tell. Otherwise it reads as laziness.
- **Don't proceed to planning while any category is unresolved.** The goal is "no non-clear areas before implementation".
- **Don't dump all question categories at once.** The user can't respond coherently to 40 open decisions. One category per message; let answers shape later questions.
- **Don't hedge recommendations with "it depends".** If it depends, enumerate the conditions and recommend per condition.
- **Don't use this skill for tiny, obvious tasks.** "Rename this variable" doesn't need categorized questions. Use this when the feature has real design surface — new modules, protocol changes, cross-service behavior, security-sensitive code, etc.
- **Don't let the conversation run without summaries.** Users lose track of what's been locked. The one-line summary at the top of each response anchors state.

## Signals to pause and re-research

If the user gives an answer that surprises you, stop and verify. Signals:

- Their answer contradicts something you read in the codebase → re-read; the code may have changed, or your reading was wrong.
- Their answer reveals a constraint you didn't know → research how that constraint affects other open categories before continuing.
- They reject a `[REC]` with reasoning you hadn't considered → adjust subsequent recommendations in that thread.

Treat every answer as potential new context, not just a vote on one question.
