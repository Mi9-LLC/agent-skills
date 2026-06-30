# Root-cause tracing

Bugs usually surface deep in the call stack — a file written to the wrong place, a
database opened with the wrong path, an exception thrown three layers below where the
bad value was created. The instinct is to fix it where the error appears. That's
fixing a symptom.

**Core principle:** trace backward through the call chain to the original trigger,
then fix at the source.

## When to use this

- The error fires deep in execution, not at the entry point.
- The stack trace shows a long call chain.
- It's unclear where the invalid data came from.
- You need to find *which* test or code path triggers the problem.

If you genuinely can't trace backward (a true dead end — no stack, no chain), fixing
at the symptom point is the fallback. Otherwise, trace.

## The tracing process

1. **Observe the symptom.** Read the actual error.
   `Error: git init failed in C:\repo\packages\core`

2. **Find the immediate cause** — the code that directly produced it.
   `Process.Start("git", "init") // in projectDir` (C#)
   `await execFile('git', ['init'], { cwd: projectDir })` (TS)

3. **Ask what called this**, and keep walking up:
   `WorktreeManager.CreateSessionWorktree(projectDir, sessionId)`
   `← Session.InitializeWorkspace()`
   `← Session.Create()`
   `← the test, at Project.Create()`

4. **Check the value at each level.** Here `projectDir` arrives as an empty string.
   An empty `cwd` resolves to the current working directory — the source tree. That's
   why `git init` ran in the wrong place.

5. **Find where the bad value was born.** The test read a `tempDir` field before the
   per-test setup had populated it, so it was still `""`. *That* is the root cause —
   not the `git init` call where it blew up.

**Fix at the source** (make the field throw if read before setup, or validate it),
not at the symptom.

## When you can't trace by reading: instrument

When the chain is too tangled to follow by eye, capture the call stack at the
dangerous operation, run once, and read where it came from.

C# / xUnit:

```csharp
void GitInit(string directory)
{
    // Temporary diagnostic — remove once localized.
    Console.Error.WriteLine(
        $"DEBUG git init: dir='{directory}' cwd='{Directory.GetCurrentDirectory()}'\n{Environment.StackTrace}");
    Process.Start("git", $"init \"{directory}\"");
}
```

TS/JS / Vitest:

```ts
function gitInit(directory: string) {
  // Temporary diagnostic — remove once localized.
  console.error('DEBUG git init:', {
    directory,
    cwd: process.cwd(),
    stack: new Error().stack,
  });
  // ...run git init
}
```

Three rules for diagnostics in tests:

- **Write to stderr** (`Console.Error` / `console.error`), not a logger — a logger
  may be suppressed during test runs.
- **Log before the dangerous operation**, not in the catch after it fails — you want
  the state going in.
- **Include context:** the directory, the current working directory, relevant
  environment variables, and the captured stack.

Run and read the captured stacks for the test file and line that triggers the call.
Look for the pattern — same test? same parameter every time? **Remove the
diagnostics once you've localized the source.**

## Finding which test pollutes shared state

Sometimes something appears during a test run (a stray `.git`, a leftover temp file,
a mutated singleton) but you don't know which test created it. The technique, in
prose — no script needed:

1. **Run the suspect test alone**, then run it as part of the full suite. If it's
   clean alone but dirty in the suite, another test is polluting shared state that
   this one then trips over (the order matters).
2. **Bisect by ordering.** Run the first half of the suite, then the second half, and
   see which half reproduces the pollution. Narrow by halves until one test is left.
   Most runners let you do this directly:
   - xUnit: filter with `dotnet test --filter "FullyQualifiedName~Some.Namespace"`
     to include/exclude groups; xUnit randomizes collection order, so also try
     pinning order to make it deterministic while bisecting.
   - Vitest: `npm test -- path/to/file.test.ts` to run subsets; `--sequence.shuffle`
     to surface order-dependence, or disable shuffle to reproduce a specific order.
3. **The polluter is the test that leaves the artifact behind.** Fix it to clean up
   after itself (or to not create the artifact), and prefer per-test isolation
   (fresh temp dir, fresh fixture) so the order can never matter again.

## Then add defense-in-depth

Once you've fixed the source, make the bug structurally impossible by validating at
each layer the bad value passed through. See `defense-in-depth.md` in this directory.

## The principle, restated

Never fix only where the error appears. Trace back to the original trigger, fix it
there, and add validation at each layer between source and symptom so it can't
recur.
