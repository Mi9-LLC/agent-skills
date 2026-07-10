---
name: update-dependencies
description: >-
  Safely update dependencies in any JavaScript/TypeScript project — npm, pnpm, yarn, or bun,
  single package or monorepo: discover outdated packages, research release notes for breaking
  changes, migrate code where needed, and verify with a clean rebuild. Use when the user asks
  to update, upgrade, or bump packages or dependencies, check for outdated modules, or bring
  the dependency tree up to date.
argument-hint: "[package-names...] (optional — limit the run to specific packages)"
disable-model-invocation: true
effort: high
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, WebSearch, WebFetch, Agent
---

# Update Dependencies

Update dependencies using a research-first workflow: bulk-update semver-safe versions, then handle each major bump individually — read its release notes, migrate the codebase for breaking changes, and verify before moving on. Works for any package manager (npm, pnpm, yarn Classic or Berry, bun) and any layout (single package or monorepo).

If arguments were provided (`$ARGUMENTS`), limit the entire workflow to those packages; otherwise process everything that is outdated.

## Current workspace state

Working tree status (must be empty before starting):

!`git status --porcelain`

## Ground rules

These are non-negotiable for every run:

1. **No assumptions.** If something is genuinely unclear — a migration path with multiple viable options, a breaking change that alters runtime behavior users depend on, a pin whose reason you can't determine — stop and ask the user with concrete options. Mechanical migrations don't need permission; decisions do.
2. **Your internal knowledge of package versions and APIs is outdated.** Never decide "latest version is X" or "the new API is Y" from memory. Always fetch the current state: the package manager's outdated command, `npm view`, and the package's own release notes / changelog / migration guide (GitHub Releases, `CHANGELOG.md`, official docs) via WebSearch/WebFetch.
3. **The project's declared runtime is the target.** Derive it once in Step 0 (`engines.node`, `.nvmrc`, or `.node-version`; fall back to the major of `node --version` and NOTE that fallback in the report). Do not adopt anything requiring a newer Node major: keep `@types/node` on the detected major (latest patch within it), and before any major bump check `npm view <pkg>@<version> engines` — if it requires a newer Node than the project targets, skip it and record why in the report.
4. **Never commit or push.** Leave changes on the work branch for the user to review.

## Step 0 — Detect environment

Run this before anything else; everything downstream depends on it. Read `references/package-managers.md` for the per-PM command mapping.

- **Package manager** (from the lockfile at repo root): `pnpm-lock.yaml` → pnpm; `package-lock.json` → npm; `yarn.lock` → yarn; `bun.lock` **or** `bun.lockb` → bun (Bun ≥1.2 emits the text `bun.lock`). If multiple lockfiles are present, or none, stop and ask the user which to use.
- **Yarn flavor** (only if yarn): distinguish Classic (v1) from Berry (≥2) via the root `packageManager` field or the presence of `.yarnrc.yml` — their command sets differ materially (see the reference). Default to Classic only if neither signal is present and `yarn --version` reports 1.x.
- **Workspace layout:** `pnpm-workspace.yaml`, or a `workspaces` field in the root `package.json` → monorepo; otherwise single-package.
- **Runtime target:** derive from `engines.node`, then `.nvmrc`, then `.node-version`. If none exist, fall back to the major of `node --version` and NOTE that fallback in the final report. `@types/node` is capped at the detected major.
- **Quality gates:** inspect root `package.json` `scripts` and take whichever of `build` / `typecheck` / `lint` / `test` exist, plus common aliases (`check`, `test:unit`). Gates that don't exist are skipped AND reported as missing in the final report.
- **Manifest discovery:** use the Glob tool with `**/package.json`, excluding `node_modules` and build-output dirs. Note which manifest declares each dependency; the root manifest carries `packageManager` and any overrides (`pnpm.overrides` / `overrides` / `resolutions`). For pnpm 11+, overrides may live in `pnpm-workspace.yaml` instead of (or in addition to) `package.json` — check both locations.
- **Build-output directories:** identify and record the project's actual build-output directories — check `.gitignore`, tsconfig/bundler `outDir` config, or common conventions (`dist`, `build`, `.next`, `.turbo`, `*.tsbuildinfo`) — for reuse in Step 6's clean rebuild.

## Preflight

1. **Verify clean tree.** If `git status --porcelain` is non-empty, stop and ask the user to stash or commit before proceeding.
2. `git fetch origin --prune`
3. **Detect the default branch:** `git symbolic-ref refs/remotes/origin/HEAD` (strip to the short name). If that fails, probe `origin/main`, then `origin/master`, then `origin/develop` in order. If still ambiguous, ask the user.
4. **Create the work branch:** `git checkout -B agent/update-dependencies/<timestamp>-<rand> origin/<default>`.

## Step 1 — Discover

Run the outdated command for the detected package manager — see `references/package-managers.md`. (pnpm example shown.)

```bash
pnpm outdated -r
```

Capture the full list: package, current → latest, and which workspace manifests declare it. Note that the outdated command of npm/pnpm exits non-zero when packages are outdated — that is the success case, not an error; never gate on its exit code.

## Step 2 — Classify and group

Split the outdated list into:

- **Safe:** patch and minor bumps.
- **Major:** anything crossing a major version — these get individual research.
- **Pinned/excluded:** `@types/node` above the detected major, anything whose new version requires a newer Node than the project targets, and anything the user asked to skip.

**Lockstep grouping.** Some package families must move together rather than one at a time — mixing majors within them causes peer-dependency chaos. Recognize a family by: packages in the **same npm scope versioned in sync**, and **documented companion packages**. See `references/lockstep-ecosystems.md` for known families. If a family is mirrored in root overrides, the overrides must be updated in the same change.

## Step 3 — Apply safe updates

Update all patch/minor bumps in one pass, then prove the baseline is green before touching any major. Use the in-range bulk-update command for the detected PM (pnpm example):

```bash
pnpm up -r            # within declared ranges
pnpm install
pnpm build && pnpm typecheck && pnpm lint && pnpm test   # run the gates that exist
```

The in-range bulk update only moves versions within declared ranges, so re-run the outdated command afterwards: any remaining non-major bump held back by a `~` or exact range needs an explicit bump-to-version (the per-PM "explicit bump" form in the reference — e.g. `pnpm up -rL <pkg>@<target>`), or it will silently never update.

**Manifest-rewrite behaviour differs by PM:** see the manifest-rewrite note in `references/package-managers.md` (read in Step 0). Review the manifest diff after the bulk pass regardless of PM.

**Release-age gating:** some package managers hold back freshly published versions by policy (pnpm 11 defaults to a 1-day `minimumReleaseAge`; npm has `min-release-age` settings; yarn has `--no-time-gate`; bun has `install.minimumReleaseAge`). If a version that should be available appears missing or held back, this is policy, not an error — report it in the final report and do not attempt to force past it.

**yarn Berry has no in-range-only bulk command** — `yarn up` resolves to latest and crosses majors, which would break this step's safe-baseline guarantee. On a Berry repo, skip the bulk pass and instead bump each non-major outdated package explicitly (`yarn up <pkg>@<target>`), then treat every major via Step 4 as usual.

If a "safe" bump breaks something (semver violations happen), treat that package like a major: research its release notes and either migrate or revert it. Do not start majors on a red baseline.

## Step 4 — Handle majors, one group at a time

For each major bump (or lockstep group) — in a monorepo, process **upstream workspace libraries before their downstream consumers** (no-op for a single package):

1. **Research first.** Fetch the release notes / changelog / migration guide for every version between current and target. You can parallelize this across background sub-agents — research the next group while migrating the current one — but never skip it. Identify each breaking change and check whether this codebase actually uses the affected API (`Grep` for the symbols).
2. **No breaking changes that touch our usage** → run the explicit bump-to-version for the PM, install, verify, move on.
3. **Breaking changes that touch our usage** → update the package, then migrate the code autonomously. Spawn a **general-purpose sub-agent** and feed it the relevant freshly fetched migration-guide excerpts — its training knowledge is as outdated as yours. If the host project defines a matching domain expert agent, delegate to it instead. Keep changes surgical: only what the migration requires.
4. **Verify after each group:** the existing build + typecheck + lint + test gates for the affected packages. A green gate before the next group is what makes failures attributable.
5. **Can't get it green** after a genuine migration effort → revert that group's version bumps, install, confirm green again, and record the revert with the blocking error in the report. Don't let one stubborn package stall the whole run.
6. **Behavioral decisions** (changed runtime defaults, removed feature with several replacements, anything that alters what ships to production) → ask the user before migrating. That is rule 1, not an exception to autonomy.

## Step 5 — Root metadata

- **`packageManager` / corepack** (only when the project pins a package manager; corepack applies to pnpm and yarn only): check `npm view <pm> version`; if newer, update the pin (e.g. `corepack use pnpm@latest`). **Important:** corepack is only available where explicitly installed — it was bundled with Node.js experimentally through Node 24, but is **not** bundled with Node 25+. If the project uses `devEngines.packageManager` (supported by npm ≥10.9 and pnpm 11), prefer updating that field as the modern pin. If corepack is not on PATH, fall back to the on-PATH PM binary and note it in the report.
- **Overrides** — `pnpm.overrides` (pnpm pre-11: `package.json`; pnpm 11+: `pnpm-workspace.yaml` only — a `pnpm.overrides` left in `package.json` is silently ignored, not still-active; treat it as needing migration), `overrides` (npm; root manifest only), `resolutions` (yarn). Confirm every override still matches the now-installed versions. Overrides fail in both directions — a stale exact override silently pins transitive deps to old versions, and a loose range override (e.g. `>=0.27.2`) silently advances them across breaking boundaries (for 0.x packages even a minor is breaking). Check what the lockfile actually resolved for each override, not just the manifests, and disclose any override-driven jump in the report.

## Step 6 — Clean rebuild

Prove everything works from scratch, not just incrementally. If the project defines a `clean` script, run it; otherwise remove `node_modules` and the detected build-output directories manually (e.g. `dist`, `.turbo`, `*.tsbuildinfo` — use what Step 0 actually found, not a fixed list). Then:

```bash
pnpm install     # the PM's install command
pnpm build       # the project's build gate, if it exists
```

## Step 7 — Final quality gates

Run the gates detected in Step 0 (skip the ones that don't exist):

```bash
pnpm typecheck && pnpm lint && pnpm test
```

Failures caused by the updates are yours to fix (return to the Step 4 playbook). Pre-existing failures you can PROVE existed before the run (e.g., reproduce them on the base commit) are not — report them explicitly to the user as a list; never silently "fix" unrelated code, and never dismiss a failure without that proof.

## Step 8 — Report

End with:

1. **Updated** — table of package, old → new version, manifests touched.
2. **Migrated** — each breaking change handled, with the code changes made (files + what changed and why).
3. **Skipped / reverted** — package, reason (requires a newer runtime than the project targets, failed migration with the blocking error, user-excluded).
4. **Warnings** — deprecation notices, peer-dependency complaints, anything the user should watch. Include any quality gates missing in Step 0, and the runtime-fallback note if `node --version` was used to derive the target.
5. **Branch** — base (the detected default branch), branch name, changed-file count, and suggested next commands (`git diff`, `git status`). No commits were made; say so.
