# Update Dependencies Skill

> Research-first dependency updates for any JavaScript/TypeScript project — reads the release notes, migrates the code, verifies with a clean rebuild

## Quick Start

### Invocation

This skill is **manual-only** (`disable-model-invocation: true`). Claude will never run it on its own — you invoke it explicitly:

```bash
# Update everything that's outdated
/update-dependencies

# Limit the run to specific packages (and their lockstep ecosystem)
/update-dependencies zod
/update-dependencies react vitest
```

The optional arguments scope the entire workflow to those packages and their lockstep ecosystems; with no arguments the skill processes everything the package manager reports as outdated.

### What happens

1. Creates a safety branch (`agent/update-dependencies/<timestamp>-<rand>`) from the auto-detected default branch — never touches your working branch directly.
2. Discovers outdated packages, splits them into **safe** (patch/minor), **major**, and **pinned/excluded**.
3. Applies all safe bumps in one pass and proves the build is green.
4. Handles each major (or lockstep group) individually: fetches the real release notes, migrates the code for breaking changes, verifies, and moves on — or reverts and reports if it cannot go green.
5. Clean rebuild, final quality gates, and a structured report. **No commits, no pushes.**

## What It Does

### Research-first, not memory-first

The core principle: **a model's training knowledge of package versions and APIs is stale.** The skill never decides "the latest version is X" or "the new API is Y" from memory. For every major bump it fetches the package's own release notes, changelog, or migration guide (GitHub Releases, `CHANGELOG.md`, official docs) and checks each breaking change against actual usage in the codebase before changing anything.

### Hybrid update strategy

- **Safe (patch/minor)** — bulk-updated together, verified once.
- **Major** — one lockstep group at a time, with a green gate between groups so any failure is attributable to a specific change.
- **Lockstep ecosystems** that must move together: `@opentelemetry/*`, `fastify` + plugins, `react`/`react-dom` + types, `vitest` + `@vitest/*`, `drizzle-orm` + `drizzle-kit`. The skill also applies heuristics to detect unlisted families (matching scope prefixes, known companion packages) — see `references/lockstep-ecosystems.md`.

### Autonomous migration with guardrails

When a major has breaking changes that touch the codebase, the skill migrates the code autonomously, delegating to a general-purpose sub-agent fed the relevant migration-guide excerpts (or to a project-defined expert agent if one exists). Two guardrails:

- **Won't-go-green** — reverts that group's bumps and reports the blocking error rather than stalling the whole run.
- **Behavioral decisions** (changed runtime defaults, a removed feature with several replacements, anything altering what ships to production) — stops and asks you first.

### Runtime target detection

The skill detects the project's Node.js target from `engines.node`, `.nvmrc`, or `.node-version` in priority order, falling back to the running `node --version` major if none of those is present. This target drives two behaviors:

- `@types/node` is capped at the detected runtime major — a newer `@types/node` major will not be installed.
- Before any package major bump, the skill runs `npm view <pkg> engines` to check whether the new version requires a Node.js version beyond the project's target. If it does, that bump is skipped and recorded in the report.

## Usage Examples

### Example 1: Full update run

```
You: update all our packages to the latest versions and make sure everything still builds and tests pass

Skill:
  ✓ Branch agent/update-dependencies/20260603-0915-3f2a created from origin/main
  ✓ ~38 safe bumps applied (axios 1.7→1.9, zod 3.22→3.24, …) — build/typecheck/lint/test green
  → 7 major groups handled individually:
      • TypeScript 6 — added "types":["node"] to tsconfig (TS6 defaults types to [])
      • Vitest 3 — updated snapshot format, adjusted reporter config
      • @opentelemetry/* — relocated HTTP instrumentation config to explicit constructor option
      • ESLint 10, date-fns 4, lucide-react 1, uuid 11 — no code change needed
  ✓ Clean rebuild green; 2 test failures proven pre-existing (reproduced on baseline)
  ⏸ Skipped: @types/node 24 (project targets Node 22), pnpm 10 (asked first)
```

### Example 2: Safe-only run, report the rest

```
You: check which dependencies are outdated and update just the safe ones — don't touch breaking changes yet, just tell me what they are

Skill:
  ✓ ~42 in-range patch/minor bumps applied and verified green
  📋 9 majors NOT applied — reported with breaking changes from cited release notes:
      • zod 4 — new parse-result shape, z.string().email() behavior change
      • eslint 10 — flat config only, CJS plugin API removed
      • typescript 6 — new tsconfig defaults, stricter generic inference
      • … (release notes linked per entry)
  ⚠ Transparency: overrides ">=4.0.0" force-resolved a transitive dep across a breaking boundary — disclosed
```

### Example 3: Scoped single-package run

```
You: bump vitest to the latest major and fix whatever breaks

Skill:
  → Scope limited to vitest + @vitest/* (lockstep group)
  ✓ Verified against the registry: latest major is 3; project on ^2.1.4
  ✓ Fetched vitest 3 migration guide — snapshot serialiser updated, no public API removals affecting this codebase
  ✓ Updated vitest.config.ts: reporters array simplified to new short form
  ✓ build/typecheck/lint/tests green
```

## The Workflow

| Step | Action |
|------|--------|
| Preflight | Refuse dirty tree; fetch; create `agent/update-dependencies/<ts>-<rand>` from auto-detected default branch (`git symbolic-ref refs/remotes/origin/HEAD`; fallback probe: main → master → develop) |
| 0. Detect | Package manager (npm/pnpm/yarn Classic/yarn Berry/bun) from lockfile + workspace config; workspace layout (single-package or monorepo); runtime target (`engines.node` / `.nvmrc` / `.node-version` / `node --version` major); available quality gates (`build`, `typecheck`, `lint`, `test` scripts — missing ones reported) |
| 1. Discover | Run the package manager's outdated command |
| 2. Classify | Safe / major / pinned-excluded; group lockstep ecosystems |
| 3. Safe updates | Bulk upgrade, re-check outdated, verify green |
| 4. Majors | One group at a time: research release notes → migrate or revert → verify |
| 5. Root metadata | `packageManager` / corepack pin; `overrides`/`resolutions` audit in both directions (stale pins hold deps back; loose ranges can jump across breaking boundaries) |
| 6. Clean rebuild | Remove install artifacts, clean install, build |
| 7. Quality gates | typecheck, lint, test — with pre-existing-failure proof (reproduced on base commit) |
| 8. Report | Updated / Migrated / Skipped-Reverted / Warnings / Branch |

## Configuration

### Frontmatter

```yaml
name: update-dependencies
disable-model-invocation: true   # manual-only — invoke with /update-dependencies
effort: high                     # multi-step research + migration
argument-hint: "[package-names...] (optional — limit the run to specific packages)"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, WebSearch, WebFetch, Agent
```

### Project-specific knobs the skill respects

- **Runtime target** — derived from `engines.node`, `.nvmrc`, `.node-version`, or the running Node.js major. `@types/node` is capped at this major; packages requiring a newer runtime are skipped and reported.
- **`overrides` / `resolutions`** (root `package.json`) — the skill checks what the lockfile actually resolved for each override in both directions: a stale exact pin holds deps back; a loose range can silently advance transitive deps across breaking boundaries.

## Troubleshooting

### "Working tree not clean" — skill stops at preflight

Expected. The preflight refuses to run on a dirty tree. Stash or commit your changes first:

```bash
git stash    # or git commit
/update-dependencies
```

### A major won't go green

The skill reverts that group and reports the blocking error rather than leaving a broken build. Read the **Skipped / Reverted** section of the report — it names the package and the exact error so you (or a follow-up `/update-dependencies <pkg>` run) can tackle it in isolation.

### Pre-existing test failures show up in the report

The skill distinguishes failures it caused from failures that already existed by reproducing them on the base commit. Pre-existing failures are reported as a list, never silently "fixed." If you see them, they were already there before the update run.

### corepack / package manager pin won't activate (Windows EPERM)

On some Windows setups corepack cannot write the pinned package manager binary into `Program Files`. This applies when the project pins pnpm, yarn, or another manager via the `packageManager` field in `package.json`. The skill falls back to the on-PATH binary and notes it. To fix permanently, run `corepack enable` from an elevated shell once.

## FAQ

**Q: Will it commit or push my changes?**
A: No. It only ever leaves changes on the safety branch for you to review. The report ends with `git diff` / `git status` suggestions.

**Q: Why does Claude never trigger this automatically?**
A: `disable-model-invocation: true`. Updating dependencies is destructive and long-running, so it only happens when you explicitly type `/update-dependencies`.

**Q: How is this different from bumping everything to latest at once?**
A: Bumping everything to latest at once leaves you to discover what broke across a pile of simultaneous changes. This skill researches each major's release notes, migrates the code, and verifies between groups — so breakage is contained and attributable, not a heap of unrelated failures.

**Q: Does it really read release notes, or guess from training data?**
A: It fetches them. The skill's first rule is that model knowledge of versions/APIs is outdated; every major's breaking changes come from the package's own current release notes/changelog, cited in the report.

**Q: Can I update just one package?**
A: Yes — `/update-dependencies <name>`. The run is scoped to that package and its lockstep ecosystem.

**Q: What if a breaking change affects production behavior?**
A: The skill stops and asks you before migrating anything that changes runtime defaults, removes a feature with multiple replacements, or otherwise alters what ships.

**Q: Which package managers are supported?**
A: npm, pnpm, yarn Classic (v1), yarn Berry (v2+), and bun — auto-detected from the lockfile and workspace config.

**Q: Does it work in a monorepo?**
A: Yes. It auto-detects the workspace layout, applies updates across all workspace packages (upstream libraries before their downstream consumers), and audits the root-level `overrides`/`resolutions`.

## Related

- [`security-vulnerability-scan`](../../README.md#security-vulnerability-scan) — scans dependencies for known vulnerabilities. Complements version updates: run this skill to move to safe versions, then `security-vulnerability-scan` to verify no new CVEs were introduced (or to find ones the old versions were hiding).

## Learn More

- [All Skills](../../README.md)
