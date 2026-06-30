# Testing anti-patterns

**Read this when:** writing or changing tests, adding mocks, or tempted to add
test-only methods to production code.

## The principle

Tests must verify real behavior, not mock behavior. Mocks isolate the unit under
test; they are not the thing being tested. **Test what the code does, not what
the mocks do.** Driving the work test-first (write the test, watch it fail
against real code, then implement) is what keeps you out of every trap below — if
you find yourself asserting on a mock, you skipped watching the test fail against
the real thing.

## The three iron laws

```
1. Never test mock behavior.
2. Never add test-only methods to production classes.
3. Never mock without understanding the dependency.
```

## Anti-pattern 1: testing mock behavior

You mock a collaborator and then assert that the mock is there — so the test
passes when the mock is present and fails when it isn't, telling you nothing
about the real component.

Bad (Vitest + Testing Library):
```ts
// Asserts the mock exists, not that the page works
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
});
```

Fix — test the real component, or if it must be isolated, assert on the page's
own behavior rather than on the mock:
```ts
test('renders sidebar', () => {
  render(<Page />);                    // don't mock the sidebar
  expect(screen.getByRole('navigation')).toBeInTheDocument();
});
```

**Gate:** before asserting on anything mock-shaped, ask "am I testing real
behavior or just that the mock exists?" If the latter — delete the assertion or
unmock the collaborator.

## Anti-pattern 2: test-only methods in production

A method that exists only so tests can call it (cleanup, reset, teardown) ends up
on a production class, where it looks like real API and is dangerous if called
for real.

Bad (TS):
```ts
class Session {
  async destroy() {                    // only ever called from tests
    await this._workspaceManager?.destroyWorkspace(this.id);
  }
}
afterEach(() => session.destroy());
```

Fix — put the helper in test utilities; keep the production class clean:
```ts
// test-utils/session.ts
export async function cleanupSession(session: Session) {
  const ws = session.getWorkspaceInfo();
  if (ws) await workspaceManager.destroyWorkspace(ws.id);
}

// in the test
afterEach(() => cleanupSession(session));
```

The same applies in C#: don't add a `ResetForTests()` / `Dispose`-for-tests
member to a production type just so a fixture can call it. Put teardown in the
test fixture (`IAsyncLifetime.DisposeAsync`, a collection fixture, or a helper).

**Gate:** before adding a method to a production class, ask "is this only used by
tests?" If yes, move it to test utilities. Also ask "does this class actually own
this resource's lifecycle?" If no, it's the wrong class for the method.

## Anti-pattern 3: mocking without understanding

Over-mocking "to be safe" stubs out a method whose side effect the test actually
depended on — so the test passes (or fails) for the wrong reason.

Bad (Vitest):
```ts
test('detects duplicate server', async () => {
  // This mock skips the config write the duplicate check relies on
  vi.mock('ToolCatalog', () => ({
    discoverAndCacheTools: vi.fn().mockResolvedValue(undefined),
  }));

  await addServer(config);
  await addServer(config);             // should throw on the dup — but now won't
});
```

Fix — mock at the right level: stub only the slow/external part, preserve the
behavior the test needs:
```ts
test('detects duplicate server', async () => {
  vi.mock('MCPServerManager');         // mock only the slow server startup
  await addServer(config);             // config still written
  await addServer(config);             // duplicate detected ✓
});
```

**Gate:** before mocking a method, ask what side effects the real method has,
whether the test depends on any of them, and whether you actually understand
what the test needs. If you're unsure, run the test against the real
implementation first, observe what has to happen, then add the *minimum* mocking
at the lowest sensible level. Red flags: "I'll mock this to be safe", "this might
be slow, better mock it", mocking without knowing the dependency chain.

## Anti-pattern 4: incomplete mocks

A mock that includes only the fields you happened to think of. Downstream code
reads a field you omitted, so the test passes while the integration breaks.

Bad:
```ts
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  // missing: metadata that downstream code reads
};
// later: blows up on response.metadata.requestId
```

Fix — mirror the real response shape completely:
```ts
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  metadata: { requestId: 'req-789', timestamp: 1234567890 },
};
```

**Rule:** mock the *complete* data structure as it exists in reality, not just
the fields your immediate assertion touches. If you build a mock, you must
understand the whole structure — partial mocks fail silently when code reads an
omitted field. When uncertain, include every documented field.

## Anti-pattern 5: tests as an afterthought

"Implementation complete, no tests written, ready for testing." Testing is part
of implementation, not an optional follow-up — and a feature with no tests isn't
complete. This is exactly what the red-green-refactor order prevents.

## When mocks get too complex

Warning signs: the mock setup is longer than the test logic; you're mocking
everything to make the test pass; mocks are missing methods the real components
have; the test breaks whenever a mock changes. When you hit these, ask whether
you need the mock at all — an integration test with the real collaborators is
often simpler and more honest than an elaborate mock.

## Quick reference

| Anti-pattern | Fix |
|---|---|
| Assert on mock elements | Test the real component, or unmock it |
| Test-only methods in production | Move them to test utilities / the fixture |
| Mock without understanding | Understand the dependency first, mock minimally |
| Incomplete mocks | Mirror the real data shape completely |
| Tests as afterthought | Test-first; not complete until tested |
| Over-complex mocks | Consider an integration test instead |

## Red flags

- Assertions checking for `*-mock` test IDs
- Methods called only from test files
- Mock setup is more than half the test
- The test fails when you remove a mock
- You can't explain why the mock is needed
- Mocking "just to be safe"

## Bottom line

Mocks are tools to isolate, not things to test. If the test-first cycle reveals
you're testing mock behavior, you've gone wrong — test the real behavior, or
question why you're mocking at all.
