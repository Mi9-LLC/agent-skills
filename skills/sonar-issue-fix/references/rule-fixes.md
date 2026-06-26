# Rule fix recipes

Per-rule, behavior-identical fixes for common SonarCloud / SonarQube
**JavaScript/TypeScript** rules (rule keys like `typescript:S3776`). Each recipe
satisfies the Sonar rule **and** stays within typical house-style conventions —
always re-check the target project's own rules (`CLAUDE.md` / `AGENTS.md` /
linter config) before applying. When you fix a rule not listed here, read the
rule's own description, confirm the fix is behavior-identical and
house-style-clean, then add a recipe — this catalog is meant to grow (and to
gain sections for other languages).

The golden rule: **the output must not change.** Every recipe below is a pure
refactor of form, not behavior.

## Mechanical rules

### S7748 — "Don't use a zero fraction in the number"
`0.0` → `0` (and `1.0` → `1`, etc.). Identical numeric value.
```ts
tax.exciseTaxAmount ?? 0.0      // before
tax.exciseTaxAmount ?? 0        // after
```

### S7758 — "Prefer String.fromCodePoint() over String.fromCharCode()"
```ts
String.fromCharCode(0)    // before
String.fromCodePoint(0)   // after  (same U+0000)
```

### S7755 — "Prefer .at(…) over [….length - index]"
```ts
arr[arr.length - 1]?.foo   // before
arr.at(-1)?.foo            // after  (same element)
```

### S7780 — "Prefer String#replaceAll() over split().join()"
For global literal replacement, and to strip trailing/leading chars (also dodges
S5852 ReDoS warnings on anchored regex):
```ts
s.split(nullByte).join('')           // before
s.replaceAll(nullByte, '')           // after
str.replace(/x/g, 'y')               // before
str.replaceAll('x', 'y')             // after
```

### S6572 — "The value of the enum member should be explicitly defined"
Triggered when *some* members are explicit and others rely on auto-increment.
Give every member its current implicit value explicitly — **do not change any
number**, and **do not remove the explicit values to "simplify"** (that just
re-introduces this rule):
```ts
enum DeploymentResult {
    Empty = 0,
    NoReleaseFound,        // before: implicit 1
    NoReleaseFound = 1,    // after:  explicit, same value
    // …continue for every member…
}
```

### S6551 — "value will use Object's default stringification ('[object Object]')"
Make the object case explicit so it no longer silently relies on
`[object Object]`. Keep the positive guard first (no negated primary branch):
```ts
const asString = (value: unknown): string => (isNil(value) ? '' : String(value));   // before
const asString = (value: unknown): string => {                                       // after
    if (isNil(value)) {
        return '';
    }
    return typeof value === 'object' ? JSON.stringify(value) : String(value);
};
```
Note: this only changes the *degenerate* object case (which was garbage either
way); primitive inputs are unaffected, so snapshots/outputs don't move.

### S7735 — "Unexpected negated condition"
Flip so the positive case comes first. Applies to `if`, ternaries, and **all**
negations (`!x`, `!isNil()`, `!isEmpty()`, `!== null`, …). Preserve exact
semantics — only reorder the branches, don't change the comparison operator's
meaning:
```ts
x !== null ? doA() : doB()    // before (negated primary)
x === null ? doB() : doA()    // after  (positive primary, same result)
```
For an `if` with no `else`, invert the guard and early-return instead of
negating. A conjunction like `a && !isNil(b)` as a ternary/if condition is
generally fine (it's not a *pure* negation) — flip only when the whole primary
condition is a negation.

## Structural rules

### S3776 — "Cognitive Complexity from N to the 15 allowed"
This is a refactor, not a one-liner. **If the function has no tests, write
characterization tests first** (see `refactor-playbook.md`). Decomposition
patterns that reliably drop complexity:

- **Branch once, assemble a variant object.** A function full of
  `isProduct ? a : b` ternaries (each +1) collapses to a single branch that
  returns one of two fully-built objects: `const fields = isProduct ?
  buildProductFields(x) : buildNonProductFields(x)`, then spread `...fields`.
  This is usually the dominant win. Build only the chosen variant — building
  both eagerly may dereference fields that only exist on one kind.
- **Extract nested conditionals into named helpers.** An inner if/else-if chain
  or an IIFE becomes a small `resolveX()` returning the value.
- **Compute a repeated guard once.** A condition repeated across several fields
  (e.g. `quantity < 0 && …` five times) → hoist `const isReturn = quantity < 0`
  or extract the whole group into one helper returning the related fields.

Keep each extracted helper itself under 15. In a typed language, annotate the
assembled record with a structural type assertion (TypeScript's
`satisfies <RecordType>`) so the compiler proves no field was dropped or renamed.
