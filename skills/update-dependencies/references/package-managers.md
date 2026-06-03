# Package-manager command mapping

The authority the skill relies on at runtime. Five package managers; **yarn is split Classic (v1) vs Berry (≥2)** because their command sets differ materially. If a command form here looks wrong for the installed version, verify with WebSearch/WebFetch and `<pm> --version` — training data goes stale.

## Quick reference table

| Capability | pnpm | npm | yarn Classic (v1) | yarn Berry (≥2) | bun |
|---|---|---|---|---|---|
| Lockfile name | `pnpm-lock.yaml` | `package-lock.json` | `yarn.lock` | `yarn.lock` | `bun.lock` (≥1.2 text) or `bun.lockb` (binary) |
| List outdated | `pnpm outdated -r` | `npm outdated` | `yarn outdated` | **no `outdated`** — see notes | `bun outdated` |
| In-range bulk update | `pnpm up -r` | `npm update` | `yarn upgrade` | `yarn up "*"` (resolves to latest — see notes) | `bun update` |
| Explicit bump-to-version | `pnpm up -rL <pkg>@<ver>` | `npm install <pkg>@<ver>` | `yarn upgrade <pkg>@<ver>` | `yarn up <pkg>@<ver>` | `bun update <pkg>@<ver>` or `bun add <pkg>@<ver>` |
| Install | `pnpm install` | `npm install` | `yarn install` | `yarn install` | `bun install` |
| Overrides mechanism | `pnpm.overrides` | `overrides` | `resolutions` | `resolutions` | `overrides` (npm-style) |
| Overrides manifest | root `package.json` | **root `package.json` only** | root `package.json` | root `package.json` | root `package.json` |
| Workspace config | `pnpm-workspace.yaml` | `workspaces` in root `package.json` | `workspaces` in root `package.json` | `workspaces` in root `package.json` | `workspaces` in root `package.json` |
| Workspace/recursive flag | `-r` (recursive) | `--workspaces` / `-w <name>` (no `-r`) | `--workspaces` (limited) | `-R` recursive / `-A` all workspaces | runs across the workspace by default |
| Corepack | applies | N/A (ships with Node) | applies | applies | N/A (self-managed) |

## Per-PM notes and pitfalls

### Outdated exit codes
- **`npm outdated` and `pnpm outdated` exit NON-ZERO when packages are outdated.** That is the success case. Never gate on the exit code — capture and parse stdout instead.
- `bun outdated` prints a table of current/update/latest.

### Does the in-range bulk update rewrite `package.json` ranges?
- **pnpm:** `pnpm up` stays within declared ranges and does **not** rewrite the manifest ranges by default (use `-L`/`--latest` to cross ranges, and `-r` for recursive across workspaces). So after `pnpm up -r`, re-run `pnpm outdated -r` and bump anything still held back with `pnpm up -rL <pkg>@<ver>`.
- **npm:** `npm update` updates the lockfile and, since npm v7+, also saves the resolved version to `package.json` for direct dependencies (within the existing range). npm has **no `-r` flag**; for monorepos use `--workspaces` (all) or `-w <name>` (one). `overrides` live in the **root manifest only**.
- **yarn Classic (v1):** `yarn upgrade` respects the ranges in `package.json` and does **not** rewrite them; `yarn upgrade <pkg>@<ver>` (or `--latest`) is the explicit form.
- **yarn Berry (≥2):** `yarn up <pkg>` resolves to the **latest** matching version and **rewrites the manifest range** (it is the counterpart to Classic's `yarn upgrade --latest`, not to a within-range update). Use `-R` to force transitive ranges to re-resolve, `-A` to apply across all workspaces. There is no true "in-range only" bulk command in Berry — treat `yarn up` as a latest-resolving operation and review the manifest diff.
- **bun:** `bun update` updates within declared ranges; `bun update <pkg>@<ver>` / `bun add <pkg>@<ver>` for an explicit version. `bun update --latest` crosses ranges.

### Yarn `outdated` is Classic-only
`yarn outdated` exists **only in Yarn Classic (v1)**. Berry removed it. For Berry, discover outdated packages with non-interactive alternatives:
- `yarn npm info <pkg> --fields version --json` per direct dependency (compare against the installed version), or
- a dry-run of `yarn up "*"` / `yarn up <pkg>` to see what would resolve (Berry's `yarn up` reports the resolution it would write).

Avoid `yarn upgrade-interactive` in an agent context — it is an interactive TUI and will hang.

### Overrides location
- pnpm: `pnpm.overrides` in the root `package.json`.
- npm: `overrides` in the **root** `package.json` only — nested-package `overrides` are ignored.
- yarn (both flavors): `resolutions` in the root `package.json`.
- bun: `overrides` in `package.json` (bun reads npm-style `overrides`). Note the known migration gotcha: converting a `package-lock.json` that carries `overrides` to a bun lockfile may drop them — verify the resolved lockfile, not just the manifest.

### Corepack
- **pnpm and yarn:** managed via corepack; pin with the `packageManager` field and apply with `corepack use <pm>@<ver>`.
- **npm:** ships with Node — **N/A** for corepack.
- **bun:** self-managed — **N/A** for corepack.

### Bun lockfile note
Bun ≥1.2 emits a text `bun.lock` (JSONC) by default; older projects may still carry the binary `bun.lockb`. Either lockfile signals bun. The lockfile is always written on install, even when already up to date.
