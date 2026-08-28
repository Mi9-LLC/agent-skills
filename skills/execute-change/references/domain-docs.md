# Domain docs — `CONTEXT.md` and ADR formats

Read by the step-1 author subagent (its prompt names this file as
`{{DOMAIN_DOCS}}`). The lead uses the three-condition ADR test below
during the design interview; it never writes these files itself — the
interview records terms and decisions in the brief, and step 1 writes
them into the run root so they are committed with the change artifacts.

## `CONTEXT.md` — the project glossary

One file at the repo root. It is a glossary and nothing else: no
implementation details, no specs, no decisions (those go in ADRs).

```md
# {Context name}

{One or two sentences: what this context is and why it exists.}

## Language

**Order**:
A customer's request to buy specific items at the quoted prices.
_Avoid_: Purchase, transaction

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request
```

Rules:

- **One word per concept.** When several words exist for the same thing,
  pick the best one and list the others under `_Avoid_`.
- **Short definitions.** One or two sentences. Define what the thing IS,
  not what it does.
- **Project terms only.** General programming concepts (timeouts, error
  types, utility patterns) do not belong, even when the project uses them
  a lot. Before adding a term ask: is this unique to this project's
  domain, or a general programming concept? Only the first belongs.
- **Group under subheadings** only when natural clusters emerge; a flat
  list is fine.
- **Merge, do not duplicate.** When the file exists, add new entries in
  place and replace an existing entry for the same term. Keep the file's
  existing order and headings.
- Create the file only when there is at least one term to write.

A repo with a `CONTEXT-MAP.md` at the root has several contexts, each
with its own `CONTEXT.md` at the path the map names; write the term into
the context the change belongs to. If that is unclear, report it as an
open question instead of guessing.

## ADRs — architecture decision records

Files live in `docs/adr/`, numbered in sequence: `0001-slug.md`,
`0002-slug.md`, … Scan the folder for the highest existing number and add
one; the first ADR is `0001`. Create the folder only when there is an ADR
to write.

```md
# {Short title of the decision}

{1–3 sentences: the context, what was decided, and why.}
```

That is the whole format. The value is in recording that a decision was
made and why, not in filling out sections. Optional additions, only when
they add real value:

- `status:` frontmatter (`proposed | accepted | deprecated | superseded by
  ADR-NNNN`) when a decision may be revisited;
- **Considered options** when the rejected alternatives are worth
  remembering;
- **Consequences** when there are downstream effects a reader would not
  expect.

### When a decision deserves an ADR

All three must be true:

1. **Hard to reverse** — changing it later costs real work.
2. **Surprising without context** — a future reader would look at the
   code and ask why it was done this way.
3. **A real trade-off** — there were viable alternatives and one was
   chosen for specific reasons.

Easy to reverse → skip it, it will just be reversed. Not surprising →
nobody will ask why. No real alternative → there is nothing to record
beyond "we did the obvious thing."

What usually qualifies: architectural shape (event-sourced writes,
monorepo); how two parts of the system talk to each other (events, not
synchronous HTTP); technology choices with lock-in (database, message
bus, auth provider — not every library, only the ones that would take
months to swap); ownership and boundary decisions ("customer data is
owned by X; others reference it by ID only"); deliberate departures from
the obvious path ("raw SQL instead of the ORM because …"), which stop the
next engineer from "fixing" something intentional; constraints not
visible in the code (compliance, a partner's latency contract); and a
rejected alternative whose rejection is not obvious, so it is not
proposed again in six months.

---

Adapted from the `domain-modeling` skill in `mattpocock/skills`
(`CONTEXT-FORMAT.md` and `ADR-FORMAT.md`; MIT License, © 2026 Matt
Pocock).
