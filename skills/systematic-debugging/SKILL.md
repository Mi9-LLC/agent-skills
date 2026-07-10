---
name: systematic-debugging
description: >-
  Use this skill when debugging any failure before proposing a fix — a bug, test
  failure, flaky test, regression, build break, crash, slow/latency symptom, or
  unexpected behavior. It enforces a four-phase discipline: investigate the root
  cause first, analyze the pattern/context, test ONE hypothesis at a time, then
  fix the cause (not the symptom) behind a failing test. Hard rule: no fix
  without root-cause investigation first, and after 3 failed fixes, stop and
  question the architecture instead of trying a 4th. Trigger for "why is this
  broken", "why is this slow", "this test is flaky", "my fix didn't work", "this
  keeps failing", "it works locally but not in CI", "latency" or "performance
  regression", a crash/stack trace, or any repeated failed-fix loop. Do NOT
  trigger for trivial, self-evident edits with no failure to diagnose — a typo,
  a rename, an obvious one-line correction.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# Systematic debugging

Random fixes waste time and create new bugs. Quick patches mask the real issue and
it comes back. The discipline here is the opposite of guess-and-check: find out
**why** something breaks before you change a line, then fix it once, at the source,
behind a test that proves it.

**The iron law:** no fix without root-cause investigation first. If you haven't
finished Phase 1, you are not allowed to propose a fix — not even a "quick one to
try."

This is faster, not slower. Systematic debugging fixes most bugs first try in
minutes; thrashing on guesses burns hours and leaves new bugs behind. The
temptation to skip the process is strongest exactly when you should not: under time
pressure, when the fix "looks obvious," and after you've already tried a couple of
things that didn't work.

## When to use it

For any technical failure: a failing test, a flaky test, a production bug, a build
break, a crash, a regression, "works on my machine but not in CI," unexpected
output. Use it **especially** when you're under pressure, when one quick fix seems
obvious, when a previous fix didn't work, or when you don't fully understand what's
happening yet.

Don't skip it because the bug "seems simple" — simple bugs have root causes too,
and the process is fast for them. The only things that don't need this are trivial,
self-evident edits where there's no failure to diagnose (a typo, a rename).

## The four phases

Complete each phase before starting the next.

### Phase 1 — Root-cause investigation

Before attempting any fix:

1. **Read the error carefully.** Don't skim past it. The full message and stack
   trace often name the exact cause — file, line, error code. Read all of it.
2. **Reproduce it consistently.** Can you trigger it reliably? What are the exact
   steps? Every time, or intermittently? If you can't reproduce it, gather more
   data — don't guess.
3. **Check what recently changed.** `git diff`, recent commits, new dependencies,
   config or environment differences. A regression has a culprit commit.
4. **In a multi-component system, instrument the boundaries.** When the failure
   crosses layers (request → service → database; CI → build → test; React → API →
   backend), add temporary logging at each boundary: what data enters, what exits,
   whether config/env propagated. Run it once to see *which layer* breaks, then
   investigate that layer. Don't theorize about which component is at fault —
   measure it. Remove the instrumentation once you've localized the failure.
5. **Trace the bad value back to its source.** When the error fires deep in the
   call stack, the fix usually doesn't belong there. Trace backward — what called
   this with the bad value, and what called *that* — until you reach where the bad
   value was born. Fix it there. See `references/root-cause-tracing.md` for the
   full backward-tracing technique.

### Phase 2 — Pattern and context analysis

Understand the shape of the problem before fixing:

1. **Find working examples.** Locate similar code in the same codebase that *works*.
   What's the difference between it and the broken path?
2. **Read the reference completely.** If you're following a pattern, library API, or
   reference implementation, read it in full — every line. Don't skim and adapt
   from a half-understanding; that's how you reintroduce the bug.
3. **List every difference.** Between working and broken, name them all, however
   small. Don't dismiss anything with "that can't matter" — that's usually exactly
   what matters.
4. **Map the dependencies.** What config, environment, services, or assumptions does
   the broken path rely on?

### Phase 3 — Single hypothesis, tested minimally

Apply the scientific method. One variable at a time.

1. **State one hypothesis, specifically.** "I think X is the root cause because Y."
   Write it down. Vague hypotheses ("something with the state") aren't testable.
2. **Test it with the smallest possible change.** Change one thing. Don't fix three
   suspects at once — if it goes green you won't know which one mattered, and you
   may have added a new bug.
3. **Verify before continuing.** Worked? Move to Phase 4. Didn't? Form a *new*
   hypothesis — do not pile a second fix on top of the first — and that failed
   test counts toward the 3-attempt limit in Phase 4.
4. **If you don't understand something, say so.** "I don't understand why X happens"
   is a valid, useful state. Research it or ask — don't fake certainty and fix
   blind.

### Phase 4 — Fix the cause, behind a test

1. **Write a failing test that reproduces the bug first.** The smallest repro that
   fails for the right reason. It must fail *before* the fix and pass *after* —
   that's your proof you fixed the actual bug and not something adjacent. If there's
   no test framework for this code yet, a tiny standalone repro script counts.

   ```bash
   # C# / xUnit — run just the new test:
   dotnet test --filter "FullyQualifiedName~OrderTotalTests.NegativeQuantity_Throws"

   # TS/JS / Vitest — run just the new test:
   npm test -- src/order/total.test.ts -t "negative quantity throws"
   ```

   Confirm it's **red** before you touch the code.

2. **Make one fix, at the root cause.** Address the cause you identified in Phase 1
   — not the symptom. One change. No "while I'm here" cleanups, no bundled
   refactor riding along.
3. **Verify.** The new test passes, and the full suite still passes — you didn't
   break anything else.

   ```bash
   dotnet test                 # C# — whole suite
   npm test                    # TS/JS — whole suite
   ```

4. **If the fix doesn't work, STOP and count.** How many fixes have you tried for
   this bug? If fewer than 3: return to Phase 1 and re-investigate with what you
   just learned. **If 3 or more: stop fixing and question the architecture** (next
   point). Do not attempt fix #4 on the same theory.

5. **After 3 failed fixes, question the architecture — don't try a 4th.** Three
   failures on the same problem is a signal, not bad luck. The tell-tale signs:
   each fix reveals a new instance of the problem somewhere else; each fix needs
   "a big refactor" to do properly; each fix creates a new symptom elsewhere. That
   pattern means the *design* is wrong, not your hypothesis. Stop and ask the hard
   questions: is this approach fundamentally sound, or are we continuing out of
   inertia? Should we change the structure instead of patching symptoms? Raise it
   with the user before any further fix attempt.

## Red flags — stop and return to Phase 1

If you catch yourself thinking any of these, you've left the process:

- "Quick fix now, investigate later."
- "Let me just try changing X and see."
- "I'll change a few things and run the tests."
- "Skip the test, I'll eyeball it."
- "It's probably X, let me fix that." / "I see the problem" (seeing the symptom
  isn't understanding the cause).
- "I don't fully get it but this might work."
- "The reference is long, I'll adapt the pattern from memory."
- Listing fixes before you've traced the data flow.
- "One more fix attempt" — when you've already tried two or more.
- Each fix uncovering the same problem in a new place.

Signals from the user that you're off-track: "Is that actually happening?" (you
assumed without verifying), "Will that show us where it breaks?" (you should have
instrumented), "Stop guessing," "We're still stuck?" When you hear these, return to
Phase 1.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "It's simple, I don't need the process." | Simple bugs have root causes too. The process is fast for them. |
| "Emergency — no time for process." | Systematic debugging is faster than guess-and-check thrashing. |
| "Just try this one thing first, then investigate." | The first fix sets the pattern. Do it right from the start. |
| "I'll write the test after I confirm the fix works." | Untested fixes don't stick. The failing-test-first proves you fixed the real bug. |
| "Fixing several things at once saves time." | You can't tell which one worked, and you've likely added a new bug. |
| "The reference is too long, I'll adapt it." | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it." | Seeing the symptom is not understanding the root cause. |
| "One more fix attempt." (after 2+ failures) | 3+ failures means an architecture problem. Question the design, don't fix again. |

## When investigation finds no root cause

If a genuine, complete investigation shows the issue is environmental, timing-
dependent, or external (not in your code), then: you've finished the process;
document what you ruled out; implement appropriate handling (retry, timeout,
clearer error); and add logging so a future occurrence is diagnosable. But be
honest — most "there's no root cause" conclusions are really incomplete
investigations. Make sure you actually did Phase 1 before settling for this.

## Supporting techniques

Read these from this skill's `references/` when the situation calls for them:

- `references/root-cause-tracing.md` — trace a bug backward through the call stack
  to the original trigger, instead of fixing where the error surfaces. Includes how
  to instrument when you can't trace by reading, and how to find which test pollutes
  shared state.
- `references/defense-in-depth.md` — after you've found and fixed the root cause,
  add validation at each layer the bad data passes through so the same bug becomes
  structurally impossible to reintroduce.
- `references/condition-based-waiting.md` — fix flaky tests by waiting for the
  actual condition instead of guessing with arbitrary sleeps/timeouts.

## Attribution

Adapted from the `systematic-debugging` skill in
[`obra/superpowers`](https://github.com/obra/superpowers) (MIT, © 2025 Jesse
Vincent). Decoupled from that project's other skills, hooks, and dispatcher;
made Windows-clean (no unix-only shell to run); examples given for both .NET/xUnit
and TS/JS/Vitest. See `LICENSE`.
