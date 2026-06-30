# Defense-in-depth validation

After fixing a bug caused by invalid data, adding a single check at the source feels
like enough. It isn't — that one check gets bypassed by a different code path, a
refactor, or a mock. Validate at **every** layer the data passes through and the bug
becomes structurally impossible, not merely fixed.

Single validation says "we fixed the bug." Layered validation says "we made the bug
impossible." Different layers catch different cases: entry validation stops most bad
input, business-logic validation catches edge cases, environment guards stop
context-specific danger, and diagnostics catch whatever slips through the first
three.

## The four layers

### Layer 1 — Entry-point validation

Reject obviously-invalid input at the API boundary.

C#:

```csharp
public Project CreateProject(string name, string workingDirectory)
{
    if (string.IsNullOrWhiteSpace(workingDirectory))
        throw new ArgumentException("workingDirectory cannot be empty", nameof(workingDirectory));
    if (!Directory.Exists(workingDirectory))
        throw new DirectoryNotFoundException($"workingDirectory does not exist: {workingDirectory}");
    // ...proceed
}
```

TS:

```ts
function createProject(name: string, workingDirectory: string) {
  if (!workingDirectory?.trim()) {
    throw new Error('workingDirectory cannot be empty');
  }
  if (!fs.existsSync(workingDirectory)) {
    throw new Error(`workingDirectory does not exist: ${workingDirectory}`);
  }
  // ...proceed
}
```

### Layer 2 — Business-logic validation

Ensure the data makes sense for *this* operation, deeper in the call chain.

C#:

```csharp
void InitializeWorkspace(string projectDir, string sessionId)
{
    if (string.IsNullOrEmpty(projectDir))
        throw new InvalidOperationException("projectDir required for workspace initialization");
    // ...proceed
}
```

TS:

```ts
function initializeWorkspace(projectDir: string, sessionId: string) {
  if (!projectDir) {
    throw new Error('projectDir required for workspace initialization');
  }
  // ...proceed
}
```

### Layer 3 — Environment guards

Refuse a dangerous operation in a context where it must never run. Example: during
tests, refuse to `git init` anywhere outside a temp directory, so a bad path can't
trash the source tree.

C#:

```csharp
void GitInit(string directory)
{
    if (Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") == "Test")
    {
        var normalized = Path.GetFullPath(directory);
        var tempRoot = Path.GetFullPath(Path.GetTempPath());
        if (!normalized.StartsWith(tempRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(
                $"Refusing git init outside temp dir during tests: {directory}");
    }
    // ...proceed
}
```

TS:

```ts
function gitInit(directory: string) {
  if (process.env.NODE_ENV === 'test') {
    const normalized = path.resolve(directory);
    const tempRoot = path.resolve(os.tmpdir());
    if (!normalized.startsWith(tempRoot)) {
      throw new Error(`Refusing git init outside temp dir during tests: ${directory}`);
    }
  }
  // ...proceed
}
```

### Layer 4 — Diagnostic instrumentation

Capture context before the dangerous operation, so if the first three layers are ever
bypassed you have the forensics. See `root-cause-tracing.md` for the stderr/stack
pattern. Keep this one lightweight (debug-level) rather than temporary — it's the
last line of defense.

## Applying the pattern

1. **Trace the data flow** — where does the bad value originate, where is it used?
   (See `root-cause-tracing.md`.)
2. **Map every checkpoint** the data passes through.
3. **Add validation at each layer** — entry, business logic, environment, diagnostic.
4. **Test each layer independently** — bypass layer 1 in a test and confirm layer 2
   still catches it. Each layer should hold on its own.

## Why all four

In practice each layer earns its place by catching something the others missed:
different code paths skip entry validation; mocks skip business-logic checks; edge
cases on a different OS need the environment guard; and the diagnostics are what tell
you a structural misuse is happening at all. Don't stop at one validation point.
