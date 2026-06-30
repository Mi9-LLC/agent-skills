# Complexity-refactor playbook (characterization tests first)

Decomposing a cognitive-complexity (`S3776`) function on **untested** code is the
riskiest fix this skill does — especially on wire-frozen code (financial record
builders, serializers, protocol encoders, anything whose byte output is a
contract). The safety net is a characterization test that locks current output
*before* you touch the function. This file captures how to do that and the
gotchas that bite.

## The loop

1. **Locate the seam.** Find the function and every branch it forks on (item
   kind, null/non-null, sign, flags). Your fixtures must exercise each branch or
   the refactor of that branch is unprotected.
2. **Build representative fixtures.** One or two inputs that together hit every
   branch. You don't need realistic data, just data that forks the code without
   throwing. Use fixed dates/strings so output is deterministic (no current-time
   or random sources).
3. **Snapshot the current output.** `expect(fn(fixture)).toMatchSnapshot()` (or
   your framework's equivalent). Run it once to write the baseline, and confirm
   green. This is the frozen contract.
4. **Refactor** (see patterns in `rule-fixes.md` under S3776).
5. **Re-run.** Snapshots must be **byte-identical**. A changed snapshot means
   changed behavior — fix the code, never update the snapshot to match.

## Why snapshots are safe even when field order changes

A field-assembly refactor often reorders the keys in the returned object. That's
safe *if* both of these hold — verify them for your stack before relying on it:

- **The snapshot serializer sorts object keys.** Many do (Jest/Vitest's default
  `pretty-format` serializer sorts keys), so reordering fields in the returned
  object does not change the snapshot. Confirm your serializer's behavior.
- **The real serialization is order-independent.** If wire/output serialization
  iterates a fixed **schema** order (mapping over a `*_SCHEMA` array, a column
  list, a proto definition) rather than object insertion order, then insertion
  order is irrelevant to the output bytes too. Check how your serializer orders
  fields; if it iterates insertion order, key reordering *is* observable and you
  must preserve it.

Net: when both hold, only field *values* matter. The snapshot catches value
changes; a structural type assertion (TypeScript's `satisfies <RecordType>`)
catches dropped/renamed/extra keys at compile time. Together they are a tight net
around a field-assembly refactor.

## Test gotchas

- **Import-time crashes during test collection.** If importing the module under
  test transitively pulls in something that throws at load — a DB client, a
  singleton that connects on import, a side-effecting module — the whole suite
  fails to *collect* (you'll see something like "0 tests / Failed Suite" rather
  than an assertion failure). Sever the offending chain by mocking those modules
  at module level with your framework's mock API:
  ```ts
  // Vitest example — adjust paths/names and use your framework's equivalent:
  vi.mock('../../path/to/Logger.js');
  vi.mock('../../path/to/errors.js');
  vi.mock('../../path/to/Cache.js');   // e.g. anything that opens a Redis/DB connection on import
  ```
  Look for an existing test in the repo that already imports the same area and
  copy its mock setup — someone usually solved this before.
- **Follow the project's own test conventions.** Read `CLAUDE.md` / `AGENTS.md`
  and an existing nearby test file: how `describe` blocks are named, whether
  mocks/imports go at module level, where fixtures live.
- **Injecting control characters via the edit tools is lossy.** A literal
  control byte (e.g. a null) written through an editing tool's JSON argument can
  be decoded into a real control character in the file — bad for git/Sonar and
  hard to see in review. To get genuine control bytes at *runtime* with clean
  ASCII *source*, construct them in the test: `const nullByte =
  String.fromCodePoint(0)` and build the string with a template literal — don't
  paste raw control bytes into the file.

## Worked example (abstracted)

This skill was distilled from clearing ~18 new-code issues on a single feature
branch. Two of them were `S3776` cognitive-complexity findings on **wire-frozen,
untested** record-builder functions (complexity ~51 and ~20) — the kind of code
where a byte change is a production incident. The sequence:

1. Wrote a characterization test with two fixtures covering every branch the
   builders forked on (product / fee / return / voided / alt-unit / tax-exempt /
   loyalty) → snapshot green.
2. Decomposed each builder by the dominant variant split — e.g.
   `buildProductFields` / `buildNonProductFields` plus small resolver helpers
   (`resolvePriceCode`, `buildReturnFields`) — each helper kept under the
   complexity limit and the assembled record annotated with `satisfies`.
3. Re-ran the snapshots: **byte-identical**. Then lint + type-check + tests green.

The snapshot tests stayed in the suite as permanent regression coverage for code
that previously had none — the durable payoff of doing the refactor tests-first.
