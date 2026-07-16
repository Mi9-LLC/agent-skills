---
name: stdlib-first
description: >-
  Reuse-before-build discipline for writing NEW TypeScript/Node or C#/.NET
  code. Trigger at two decision moments: (1) about to write a new function,
  utility, helper, wrapper, service, or algorithm in TS or C# — "write a helper
  to X", "implement retry / date-parsing / validation logic", "create a
  service/module for Y"; (2) adding or choosing a dependency — "should we add
  lodash/Polly", "which library for X". Walks a strict reuse ladder —
  built-in/standard library first, then (C#) first-party Microsoft.Extensions.*,
  then a library the project already uses, custom code last — plus precise
  types, specific error classes, and doc comments; always asks before adding a
  new package. Do NOT trigger for code review, debugging existing behavior,
  trivial edits (a typo, rename, or one-line fix), or languages other than
  TypeScript/C#.
---

# stdlib-first

Reuse before you build. When writing new TypeScript/Node or C#/.NET code, walk the ladder below and take the FIRST rung that solves the problem — a custom implementation is the last resort, not the default.

## The reuse ladder

Before writing any new function or helper, walk this ladder and take the FIRST rung that solves the problem:

1. **A built-in language feature or standard-library API.**
   - TS/Node: Array/Object/Map/Set methods, `structuredClone`, `fetch`, `URL`, `fs/promises`, `path`, `crypto`, `util`, `stream`, `timers/promises`.
   - C#: LINQ, records, pattern matching, System.Text.Json, System.IO, System.Net.Http, System.Threading.Tasks.
2. **C# only: a first-party `Microsoft.Extensions.*` package** — already referenced, or ask before adding (same rule as rung 3).
3. **A widely-adopted library the project ALREADY uses** — check `package.json` / `Directory.Packages.props` / `*.csproj` first. If the right library isn't installed, ask before adding it.
4. **Only if none of the above apply: write a custom implementation.**

Never hand-roll file I/O, path manipulation, HTTP requests, date parsing, data validation, JSON handling, or retry logic when a rung 1–3 option exists.

## Language rules

TypeScript:
- Strict mode on; no `any` — use `unknown` for untrusted external data; prefer discriminated unions over loose optional fields.
- Domain failures throw custom error classes extending Error — never bare `new Error(...)`.
- One-line JSDoc on non-obvious functions.

C#:
- Nullable reference types on; avoid `object`/`dynamic`; records for immutable data; specific numeric/collection types over broad ones.
- Domain failures throw specific exceptions (ArgumentException, InvalidOperationException, or a custom Exception subclass) — never bare `new Exception(...)`.
- `async`/`await` with a `CancellationToken` for I/O; no sync-over-async (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`).
- XML doc comments (`///`) on non-obvious public members.

## Adding a dependency

Never add a package silently. When the right tool is a library the project does not yet use (rung 2 or 3), stop and ask the user first — use AskUserQuestion, naming the candidate package, what it replaces, and the hand-rolled alternative — and proceed only on their answer. A dependency is a long-term maintenance commitment the user owns, not an implementation detail.

## Worked examples

- **Deep-clone a settings object (TS).** Rung 1: `structuredClone(settings)`. Not a recursive `cloneDeep` helper; not adding lodash for one call. (If the object holds functions or class instances `structuredClone` can't copy, that is a genuine rung-4 case — say so.)
- **Parse a URL query string (TS).** Rung 1: `new URL(href).searchParams` or `URLSearchParams`. Never a regex splitter.
- **Group orders by customer (C#).** Rung 1: LINQ `orders.GroupBy(o => o.CustomerId)`. Not nested loops maintaining a `Dictionary<string, List<Order>>` by hand.
- **Retry a flaky HTTP call (C#).** Rung 3: the project already references Polly (check `Directory.Packages.props`) → use it. Not referenced → ask before adding it; don't silently write a `for` + `Task.Delay` loop either — the user's answer decides which.
- **Validate an incoming payload (TS).** Rung 3: the project already uses zod → define a schema. Only if no validation library exists and the user declines adding one: a hand-written type guard against `unknown` (rung 4).

## When NOT to apply

- Code review or critique asks — review against the target repo's own standards, not this ladder.
- Debugging existing behavior — diagnose first; don't rewrite working code to fit the ladder mid-debug.
- Trivial edits — a typo, rename, or one-line fix has no reuse decision in it.
- Other languages — this codifies TS/Node and C#/.NET practice only.

## Canonical copy & repo bootstrap

This skill is the canonical source of the `## Coding standards` block checked into Mi9 repos' root `CLAUDE.md` files — the `<!-- source: Mi9-LLC/agent-skills → skills/stdlib-first -->` comment in those blocks points here.

- **Updating the rules:** change this skill first, then re-sync the repo blocks from it.
- **Bootstrapping a new TS/C# repo:** if the repo's `CLAUDE.md` has no `## Coding standards` section, offer to insert the tailored block — TS repos get the ladder minus the C#-only rung (remaining rungs renumbered) and the TypeScript rules only; C# repos get the full 4-rung ladder and the C# rules only.
