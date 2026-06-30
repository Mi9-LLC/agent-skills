# Condition-based waiting

Flaky tests usually guess at timing with an arbitrary delay — "wait 50ms, the async
thing should be done by then." That's a race: it passes on a fast machine and fails
under load or in CI. The fix is to wait for the *actual condition* you care about,
not for a guess about how long it takes.

## When to use this

- A test has an arbitrary delay (`Task.Delay(50)`, `Thread.Sleep`, `setTimeout`,
  `sleep`).
- A test is flaky — passes sometimes, fails under load or in parallel.
- A test times out when the suite runs in parallel.
- You're waiting for an async operation to finish before asserting.

**Don't** replace the wait when the test is genuinely about *timing behavior*
(debounce, throttle, a polling interval). In that case keep the delay but document
*why* it's that exact duration.

## Core pattern

Wait for the condition, not the clock.

TS/JS / Vitest — Vitest ships `vi.waitFor`:

```ts
// BEFORE — guessing at timing (flaky):
await new Promise(r => setTimeout(r, 50));
expect(getResult()).toBeDefined();

// AFTER — wait for the condition:
await vi.waitFor(() => expect(getResult()).toBeDefined());
```

C# / xUnit — poll for the condition with a timeout:

```csharp
// BEFORE — guessing at timing (flaky):
await Task.Delay(50);
Assert.NotNull(GetResult());

// AFTER — wait for the condition:
await WaitFor(() => GetResult() is not null, "result to be set");
Assert.NotNull(GetResult());
```

## A reusable poller (C#)

If your test stack has no built-in `waitFor`, this is the whole pattern — poll the
condition, give up after a timeout with a clear message:

```csharp
static async Task WaitFor(Func<bool> condition, string description, int timeoutMs = 5000)
{
    var sw = Stopwatch.StartNew();
    while (!condition())
    {
        if (sw.ElapsedMilliseconds > timeoutMs)
            throw new TimeoutException($"Timeout waiting for {description} after {timeoutMs}ms");
        await Task.Delay(10); // poll every 10ms
    }
}
```

The TS equivalent if you're not on Vitest's `vi.waitFor`:

```ts
async function waitFor<T>(
  condition: () => T | undefined | null | false,
  description: string,
  timeoutMs = 5000,
): Promise<T> {
  const start = Date.now();
  for (;;) {
    const result = condition();
    if (result) return result;
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timeout waiting for ${description} after ${timeoutMs}ms`);
    }
    await new Promise(r => setTimeout(r, 10)); // poll every 10ms
  }
}
```

## What to wait on

| Scenario | Condition to poll |
|----------|-------------------|
| Wait for an event | an event with the expected type has arrived |
| Wait for state | the state machine reached the expected state |
| Wait for a count | the collection has at least N items |
| Wait for a file | the file exists on disk |
| Compound | several conditions are all true |

## Common mistakes

- **Polling too fast** (every 1ms) wastes CPU — poll every ~10ms.
- **No timeout** means an infinite hang if the condition never holds — always set a
  timeout with a message that says what you were waiting for.
- **Caching stale state** before the loop — read the value *inside* the loop so each
  check sees fresh data.

## When an arbitrary delay is actually correct

When you're testing timed behavior itself, first wait for the triggering condition,
then wait the known duration, and comment why:

```ts
await vi.waitFor(() => toolStarted());     // 1. wait for the trigger condition
await new Promise(r => setTimeout(r, 200)); // 2. 200ms = 2 ticks at 100ms — documented, not guessed
```

The requirements for a justified delay: (1) you waited for a real condition first,
(2) the duration comes from known timing rather than a guess, and (3) there's a
comment explaining the number.
