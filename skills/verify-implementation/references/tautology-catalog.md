# Tautology catalog — tests that cannot fail

**A test that cannot be made to fail is not a guard.** These are the failure
modes to recognize when reading test bodies, how to construct a mutation for
common test shapes, and the acceptance bar a mutation proof must meet. All
three catalogued failure modes passed human review on a real repository
before the mutation-proof rule existed — they read plausibly; the defect is
only visible in the body, or only under mutation.

## The three catalogued failure modes

### 1. The system under test is never wired up

The test asserts against an application, module, or fixture that never
registered the thing being tested. The observed case: an HTTP test asserted
on routes the test app never registered — every request hit the framework's
fallback, and the assertions were loose enough to pass on the fallback
response.

*Tell:* the fixture builds its own app/module instance; trace whether the
code under test is actually attached to it. *Mutation:* delete the route (or
handler registration) in production code — a wired test fails, an unwired
test still passes.

### 2. Comparing the code to itself

The test computes the expected value by calling the same code path it is
testing — directly, via a second call under a different variable name, or by
re-implementing the production logic inline in the test.

*Tell:* the "expected" side of the assertion traces back to the same function
or to a copy of its body. *Mutation:* change the production logic's result
(off-by-one a constant, invert a branch) — a real test fails; a
self-comparing test computes the same wrong value on both sides and passes.

### 3. Asserting the runtime's own semantics

The test asserts something the language or standard library guarantees
regardless of the code under test — that a list contains what was just
appended to it, that serialization round-trips a plain object, that a mock
returns what it was configured to return.

*Tell:* the assertion would hold in an empty project with the production code
deleted. *Mutation:* delete or gut the production function — if the test
still passes, it was testing the runtime, not the code.

## Constructing a mutation for common test shapes

Pick the mutation that targets what the test *claims* to guard:

| Test shape | Mutation |
|---|---|
| Pure function / unit assert-on-return | Off-by-one a boundary constant, invert the branch condition, or swap two arguments in the production code |
| HTTP / endpoint test | Remove the route registration, or change the status code / a response field the test names |
| Behavior-change guard ("now excludes cancelled items") | Revert exactly the behavioral line the work introduced — the guard exists to fail on precisely this revert |
| Snapshot / characterization test | Change one output-affecting line — the snapshot must diff; if it doesn't, the snapshot isn't capturing the behavior |
| Error-path test | Make the production code succeed where the test expects the error (remove the throw / validation) |
| Event / message / queue test | Drop the publish call, or mutate one field of the emitted payload |
| Concurrency / retry test | Make the code single-attempt (remove the retry loop) — a real retry test fails on the first induced failure |

One mutation per proof is enough when it targets the guarded behavior.
Mutating an unrelated line and watching the test pass proves nothing either
way.

**Scope each run to the targeted test file, or the single test** (`vitest run
path/to/file.test.ts -t "name"`, `dotnet test --filter`, `pytest path::test`).
The proof only needs that one test to fail; running the whole suite once per
mutation multiplies the slowest step in the review by the number of proofs.
The full suite belongs to the Step 3 gate pass, run once.

## The acceptance bar for a mutation proof

A proof consists of exactly three parts:

1. **The mutated line** — the production line changed, before and after.
2. **The verbatim failure output** — the test runner's actual failure
   message, copied, not paraphrased (e.g. `expected 2, received 1`).
3. **Confirmation of revert** — the mutation was undone and the production
   code is byte-identical to the reviewed state (`git diff` clean).

Anything less — "I verified the test fails", "the test is clearly
sensitive", a description of what *would* happen — is an assertion about a
test, not a proof, and does not clear pass 3 of the checklist.

Run mutations only where they are safe: on the local working tree, reverted
immediately, never committed, and never against shared state (a live
database, a deployed service).
