---
name: test-driven-development
description: >-
  Use this skill ONLY when the user has opted into test-first development for the
  work at hand — they explicitly ask for TDD / test-driven / "write the test
  first" / red-green-refactor, OR they are starting a brand-new feature, module,
  or component and say they want it built test-driven. It guides the disciplined
  cycle: write a failing test, watch it fail for the right reason, write the
  minimal code to pass, refactor — and it pushes back on the rationalizations for
  skipping that order. Trigger on: "let's TDD this", "build X test-first", "write
  the tests first", "do this with red-green-refactor", "implement Y test-driven".
  Do NOT trigger on ordinary coding: every code edit, routine bug fix, small tweak,
  refactor of existing code, config change, or "add tests" after the fact. This is
  a deliberate methodology the user opts into for a specific piece of work — never
  a default mode imposed on all changes. If unsure whether they want it, ask.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Test-driven development

This is an **opt-in methodology**, not a global rule. Use it for the specific
piece of work the user has chosen to drive with tests — typically a fresh
feature, module, or component they want built test-first. Outside that explicit
request, write code the normal way. Do not impose TDD on every edit, bug fix, or
trivial change, and do not delete someone's existing code to "redo it properly"
unless they asked for that.

Inside an opted-in session, though, run the discipline honestly. The whole value
of TDD comes from the order — test first, watch it fail, then implement — and
that order is exactly what's tempting to shortcut. The body below is for holding
that line once the user has asked you to.

## The core principle

Write the test first. Watch it fail. Write the minimal code to pass. Then
refactor.

**If you didn't watch the test fail, you don't know whether it tests the right
thing.** A test written after the code passes immediately, and passing
immediately proves nothing — it could be asserting the wrong thing, testing your
implementation instead of the behavior, or silently missing the edge case you
forgot. Seeing red first is the proof the test has teeth.

## The rule, while opted in

```
No production code for the opted-in work without a failing test first.
```

Wrote the implementation before the test? Set it aside and drive it from a test
instead — don't keep it open and "adapt" it line-by-line while you type the
test, because that's just testing-after with extra steps. Implement fresh from
what the test demands.

## Red-green-refactor

A short loop, repeated once per behavior:

1. **RED** — write one minimal failing test for the next behavior.
2. **Verify RED** — run it, confirm it fails *for the right reason*.
3. **GREEN** — write the simplest code that makes it pass.
4. **Verify GREEN** — run it, confirm it passes and nothing else broke.
5. **REFACTOR** — clean up with the tests staying green.
6. Repeat for the next behavior.

### RED — write the failing test

One behavior, a name that describes that behavior, real code over mocks. If the
name needs an "and", it's two tests — split it.

Good (Vitest, TS/JS):
```ts
import { expect, test } from 'vitest';
import { retryOperation } from './retry';

test('retries a failing operation until the third attempt succeeds', async () => {
  let attempts = 0;
  const op = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  const result = await retryOperation(op);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```

Good (xUnit, C#):
```csharp
[Fact]
public async Task RetriesFailingOperation_UntilThirdAttemptSucceeds()
{
    var attempts = 0;
    Func<Task<string>> op = () =>
    {
        attempts++;
        if (attempts < 3) throw new InvalidOperationException("fail");
        return Task.FromResult("success");
    };

    var result = await Retry.OperationAsync(op);

    Assert.Equal("success", result);
    Assert.Equal(3, attempts);
}
```

Both test *real behavior* (the retry count, the eventual result), not that a
mock was called N times. A test that only asserts a mock's call count is testing
the mock, not the code — see `references/testing-anti-patterns.md`.

### Verify RED — watch it fail (mandatory)

Run the one test. Use whatever the project uses; on Windows these run the same
in PowerShell or Git Bash:

```
# TS / JS (Vitest)
npx vitest run path/to/retry.test.ts

# C# (xUnit) — filter to the one test
dotnet test --filter "FullyQualifiedName~RetriesFailingOperation"
```

Confirm: it **fails** (not errors), and it fails because the feature is missing
— not because of a typo, bad import, or wrong path.

- Passes already? You're describing behavior that already exists — fix the test
  to target what's actually new.
- Errors instead of failing? Fix the error (import, compile, path) and re-run
  until you get a clean assertion failure.

### GREEN — minimal code

Write the simplest thing that makes the test pass. No options you don't need, no
config knobs, no "while I'm here" features — that's YAGNI. Don't refactor
neighboring code or "improve" beyond what the test asked for.

```ts
export async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i === 2) throw e;
    }
  }
  throw new Error('unreachable');
}
```

### Verify GREEN — watch it pass (mandatory)

Re-run the test, then the surrounding suite:

```
npx vitest run            # TS / JS — full suite
dotnet test               # C# — full suite
```

Confirm: the new test passes, the rest still pass, and the output is pristine
(no errors or warnings). If the new test fails, fix the **code**, not the test.
If something else broke, fix it now before moving on.

### REFACTOR — clean up

Only once green. Remove duplication, improve names, extract helpers — without
adding behavior and without leaving the suite. Re-run after each change.

## What makes a good test

| Quality | Good | Bad |
|---|---|---|
| **Minimal** | One behavior per test. "and" in the name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear** | Name states the behavior | `test('test1')` |
| **Intent-revealing** | Shows the API you wish you had | Obscures what the code should do |

## Common rationalizations (and the rebuttal)

When you catch yourself reaching for one of these *inside opted-in work*, it's
the moment the discipline matters. None of them justify skipping the failing
test.

| Excuse | Reality |
|---|---|
| "Too simple to test" | Simple code still breaks. The test costs 30 seconds. |
| "I'll write the tests after" | Tests written after pass immediately and prove nothing. |
| "Tests-after achieve the same goal" | Tests-after answer "what does this do?" Tests-first answer "what *should* this do?" — and aren't biased by your implementation. |
| "I already tested it manually" | Manual testing is ad-hoc: no record, can't re-run, easy to forget cases under pressure. |
| "Deleting the code I wrote is wasteful" | Sunk cost. Code you can't trust is technical debt; keeping it is the waste. |
| "Keep it as reference, write the test first" | You'll adapt it line-by-line — that's testing-after. Drive fresh from the test. |
| "I need to explore first" | Fine. Explore, throw the spike away, then start with TDD. |
| "This test is hard to write" | Hard to test usually means hard to use. Listen to it; simplify the design. |
| "TDD will slow me down" | TDD is faster than debugging-after-the-fact in production. |
| "TDD is dogmatic; I'm being pragmatic" | The pragmatic win *is* test-first: bugs caught before commit, regressions caught immediately, behavior documented, refactoring made safe. |

## Stop and reconsider if you see

- Production code for the opted-in work written before its test
- A new test that passes immediately
- You can't explain *why* the test failed
- "I'll add the tests later" / "I already tested it manually"
- "Keep it as reference" / "adapt the existing code"
- "Just this once" / "this case is different because…"

Any of these means the test-first order slipped. Re-establish it: write the
failing test, watch it fail, then drive the code from it.

## When you're stuck

| Problem | Move |
|---|---|
| Don't know how to test it | Write the API you wish existed; write the assertion first; if still stuck, ask the user. |
| Test is too complicated | The design is too complicated. Simplify the interface. |
| You must mock everything | The code is too coupled. Introduce dependency injection. |
| Test setup is huge | Extract helpers; if still huge, simplify the design. |

## Bug fixes (when the user opts in to TDD for the fix)

Reproduce the bug as a failing test first, then follow the cycle. The test both
proves the fix and guards against regression. (This applies when the user wants
the fix done test-driven — not as a mandate on every bug.)

## Testing anti-patterns

When you add mocks or test utilities during the cycle, read
[references/testing-anti-patterns.md](references/testing-anti-patterns.md) to
avoid the common traps:

- Asserting on mock behavior instead of real behavior
- Adding test-only methods to production classes
- Mocking without understanding the dependency you're mocking
- Incomplete mocks that diverge from the real data shape

## Verification checklist (for the opted-in work)

- [ ] Each new behavior has a test
- [ ] You watched each test fail before implementing
- [ ] Each test failed for the expected reason (feature missing, not a typo)
- [ ] You wrote the minimal code to pass
- [ ] All tests pass; output is pristine
- [ ] Tests exercise real code (mocks only where unavoidable)
- [ ] Edge cases and error paths are covered

## Attribution

Adapted from [`obra/superpowers`](https://github.com/obra/superpowers)
(`test-driven-development`), MIT License, © 2025 Jesse Vincent — see `LICENSE`.
Changes for this catalog: **reframed as an opt-in methodology** (the original
mandates test-first for all production code; here it triggers only when the user
asks for TDD or wants a new feature built test-driven), **decoupled** from the
superpowers hook/dispatcher and sibling skills (links point only to this skill's
own `references/`), and reworked with **.NET/xUnit and TS/Vitest examples** and
Windows-friendly commands in place of the originals.
