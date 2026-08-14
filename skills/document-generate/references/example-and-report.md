# Report skeleton and worked example

Read on demand, not up front. Contents:

1. [Completion report skeleton](#1-completion-report-skeleton) — read at Step 9,
   when writing the final summary.
2. [Worked example](#2-worked-example) — an end-to-end run, read when an
   illustration of the whole workflow would help.

## 1. Completion report skeleton

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

## 2. Worked example

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
