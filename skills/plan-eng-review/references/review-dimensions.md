# Review dimensions — checklists, calibration, and the report contract

Read this when you reach Steps 3–6 of `plan-eng-review`. The iron law from
SKILL.md governs everything here: a checklist item becomes a headline
finding only with presence evidence (a quote of the plan, or a verified
`file:line`) or absence evidence (the obligation-creating plan text plus
the negative search that came back empty). No evidence → appendix note or
open question, never a headline.

## 1. Architecture

Evaluate the plan's design across:

- **Boundaries and coupling** — which components the plan couples that are
  separate today; whether a new module's dependencies point the right way;
  anything reaching across a layer (UI importing data access, one service
  reading another service's tables).
- **Data flow and bottlenecks** — where data enters, transforms, and lands;
  any single queue, endpoint, or table every new path funnels through.
- **Scaling and failure points** — what happens at 10× the plan's implied
  volume; which new dependency (external API, cache, queue) becomes the
  thing that takes the feature down.
- **Security surface** — auth on every new endpoint, access control on
  every new query, what crosses an API boundary (input validation, output
  over-exposure), secrets handling for new integrations.
- **Build / publish / deploy path** — for every new artifact (package,
  container, binary, migration): how it is built, published, and deployed,
  and in what order relative to the code that needs it.

**Per-new-codepath failure scenario (mandatory).** For each new codepath or
integration, describe one realistic production failure — timeout,
nil/undefined reference, race condition, stale data, partial write,
dependency outage, malformed input — and note whether the plan accounts for
it. Every scenario becomes a row in the report's failure-modes table.

## 2. Code quality of the planned code

The code does not exist yet: judge what the plan commits to, and quote the
plan's own words as evidence.

- **DRY against the existing codebase** — be aggressive: every helper,
  validation, mapping, or client the plan writes fresh gets checked against
  Step 2's reuse findings.
- **Organization** — do new files and modules land where their neighbors
  live, or does the plan invent a new layout for one feature?
- **Error-handling strategy** — does the plan say what happens on failure
  for each new operation, or only describe the happy path? "Handle errors"
  with no strategy (retry? surface to the user? log and continue?) is a
  finding.
- **Over-engineering** — abstractions with one caller, configuration for
  values that never vary, patterns imported for symmetry rather than need.
- **Under-engineering** — the inverse: a quick hack where the plan itself
  says a second caller is coming; stringly-typed data crossing module
  boundaries.
- **Tech-debt hotspots** — does the plan build on a module that is already
  a known churn or complexity hotspot without accounting for it?

## 3. Tests — the heaviest dimension

### Framework pre-detection

1. Read `CLAUDE.md` for a `## Testing` section — authoritative when
   present.
2. Otherwise sniff the stack: `package.json` (jest / vitest / playwright /
   cypress), `pyproject.toml` / `requirements.txt` (pytest), `Gemfile` /
   `.rspec` (rspec), `go.mod` (go test), `Cargo.toml` (cargo test),
   `*.csproj` (xUnit / NUnit) — plus `test/`, `tests/`, `spec/`,
   `__tests__/` directories.

Name the framework in the report; planned tests are judged against what
the project actually runs.

### Trace every new codepath

For each new or changed function, endpoint, event handler, or component:

1. Follow the data from the entry point through every branch.
2. Map conditional logic — if/else, switch, guard clauses, early returns.
3. Identify error paths — try/catch, rescue, error boundaries, rejected
   promises.
4. Track callees — do the functions it calls have untested branches the
   change now exercises?
5. Hit the edges — null/undefined input, empty collection, invalid type,
   boundary values.

### Trace user flows

Beyond code paths, walk the real journeys the plan touches:

- The complete flow (e.g. "click Pay → validate → API call → success or
  failure state").
- Unexpected interactions — double-click, navigate away mid-operation,
  submit with stale data, slow connection, concurrent actions.
- Error states the user sees — clear message or silent failure? Can they
  recover?
- Empty/zero/boundary states — zero results, thousands of results,
  max-length input.

### The coverage picture

Rate each traced path by what the plan actually commits to — behavioral
definitions, not vibes:

| Mark | Meaning (planned coverage) |
|---|---|
| `★★★` | Plan commits to behavior + edge + error tests for this path |
| `★★` | Plan commits to a happy-path test only |
| `★` | Indirect — the path runs under some other planned test; nothing asserts on it specifically |
| `GAP` | Nothing planned exercises this path |

Render the picture compactly (fenced block, both columns), and close with
the summary line:

```
CODE PATHS                                USER FLOWS
src/services/import.ts                    CSV import
├── parseRows()                           ├── [★★] Upload valid file
│   ├── [★★★] valid + malformed rows      ├── [GAP] Upload during running import
│   └── [GAP] empty file                  └── [GAP] Navigate away mid-import
└── persistBatch()
    └── [★ via upload e2e] happy path

COVERAGE: 3/6 paths with planned coverage · ★★★:1 ★★:1 ★:1 · GAP:3
```

Every `GAP` row is an absence finding — it needs the obligation quote and
the negative search like any other.

### REGRESSION RULE (verbatim, no exceptions)

> If the plan modifies existing behavior and no existing test covers the
> changed path, a regression test goes into **Required plan changes**. Not
> a question, not a decision — never asked, never waived.

"No existing test covers it" is itself an absence finding: cite the search
(what you Grepped for, in which test globs, and the empty result).

### E2E vs unit assignment

Tag each planned (or required) test:

| Tag | When |
|---|---|
| `[→E2E]` | The flow spans 3+ components; mocking would hide the real failure; or it is an auth, payment, or destructive flow |
| *(unit)* | Pure functions, single-function edge cases, internal helpers |
| `[→EVAL]` | The plan changes an LLM call or prompt template — name the eval suite that must run |

A plan that tests a 3+-component flow purely with mocks earns a finding:
the mocks hide exactly the integration failures the flow exists to survive.

## 4. Performance

Only where the plan plausibly touches these — no generic advice:

- **N+1 and data access** — a query inside a loop the plan introduces; a
  fetch-per-row where a batch API exists; a new list with no pagination.
- **Memory** — unbounded accumulation (reading a whole file or table to
  process one row), caches without eviction.
- **Caching** — repeated identical reads the plan could cache; and the
  inverse, a cache the plan adds with no invalidation story.
- **Hot-path complexity** — quadratic work on a path the plan itself says
  runs per-request or per-row.

## 5. Calibration and the report contract

### Severity

| Severity | Meaning |
|---|---|
| CRITICAL | Implemented as written, the plan breaks existing behavior, loses data, or ships a silent failure — or cannot work as specified |
| HIGH | A real defect the plan would ship; must be addressed before implementation |
| MED | A plausible problem or meaningful debt; address it, but the plan functions without |
| LOW | Polish; note it, never block on it |

### Confidence — display rules

| Score | Rule |
|---|---|
| 9–10 | Verified against the code this session; show normally |
| 7–8 | High-confidence pattern match; show normally |
| 5–6 | Possible false positive; show with an explicit caveat ("medium confidence — verify X") |
| 3–4 | Suspicion only; appendix, never a headline |
| 1–2 | Speculation; headline only if the severity is catastrophic (CRITICAL), flagged `LOW-CONFIDENCE`, with the catastrophic rationale stated — otherwise drop |

### Finding format

```
- [SEVERITY] (confidence: N/10) <evidence: plan quote, `file:line`, or
  obligation quote + negative search> — <what is wrong and why it matters>.
  [REC] <the recommended action>
```

### Verdict rules

Checked top-down; the first matching row wins. Judgment never overrides
the table.

| Condition | Verdict |
|---|---|
| ≥1 CRITICAL GAP row in failure modes, or ≥1 unresolved decision | NEEDS REVISION |
| Else: Required plan changes non-empty | APPROVED WITH CHANGES |
| Else | APPROVED |

### Report skeleton

Interior headings are `###` and lower — never `##` — and evidence quotes
are blockquotes or inline code, never column-0 `## ` lines. The report ends
the file, closing marker last. A section with nothing to report states
"None." on one line rather than being omitted; only the appendix may be
omitted when empty.

```markdown
## ENG REVIEW REPORT

*Run N — YYYY-MM-DD — <plan file, or "pasted plan — terminal only">*

VERDICT: <APPROVED | APPROVED WITH CHANGES | NEEDS REVISION> — <one sentence>.

### Scope-reduction opportunities
- <candidate> — <what cutting it saves; why the goal survives without it>

### What already exists
- Plan proposes <X>; <equivalent> already exists at `path/file.ts:NN` —
  reuse instead of rebuilding.

### Architecture
- [HIGH] (confidence: 8/10) <evidence> — <description>.
  [REC] <action>

### Code quality
- …

### Tests
- …

### Performance
- …

### Required plan changes
- [ ] <change the plan must make before implementation> (from: <finding>)

### Failure modes
| Failure | Test? | Handled? | User-visible? | Gap |
|---|---|---|---|---|
| <new codepath>: <realistic failure> | no | no | silent | **CRITICAL GAP** |

### Test coverage summary
<coverage picture + `COVERAGE: N/M` line + E2E/unit/eval split>

### Decisions
- <fork>: <what was chosen> (CHOSE <option> — user, run N)
- <risk>: accepted (ACCEPTED-RISK — user, run N)

### NOT in scope
- <deferred item> — <one-line rationale>

### Appendix — low-confidence notes
- (confidence: 3/10) <suspicion, stated as suspicion>

NO UNRESOLVED DECISIONS
```

The closing marker is exactly one of `NO UNRESOLVED DECISIONS` or
`UNRESOLVED DECISIONS:` followed only by its bullets (one per open fork).
It appears exactly once, the two variants never co-occur, and nothing
follows it.
