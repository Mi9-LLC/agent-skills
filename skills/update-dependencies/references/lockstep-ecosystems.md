# Lockstep ecosystems

Package families whose members must move **together** — bumping one across a major while leaving its companions behind causes peer-dependency chaos (unmet peers, duplicated transitive copies, runtime type mismatches). Treat each family as a single unit in Step 4.

## Known families

| Family | Members that move together | Notes |
|---|---|---|
| OpenTelemetry | `@opentelemetry/*` (API, SDK, instrumentation, exporters) | The API and SDK packages are tightly peer-coupled. **If mirrored in root overrides, update the overrides in the same change** — a stale override silently pins or advances the whole tree. |
| Fastify | `fastify` + `@fastify/*` plugins | Each plugin declares a peer range on the `fastify` core major; bumping the core major requires bumping every plugin that supports it. |
| React | `react` + `react-dom` + `@types/react` + `@types/react-dom` | Runtime and DOM packages share a version line; the `@types/*` packages track the same major. |
| Vitest | `vitest` + `@vitest/*` (e.g. `@vitest/ui`, `@vitest/coverage-*`) | The sub-packages pin an exact peer on the matching `vitest` version. |
| Drizzle | `drizzle-orm` + `drizzle-kit` | The ORM and its migration CLI must stay on the same line or schema/codegen drifts. |
| Angular | `@angular/*` packages + `@angular/cli` | All Angular scoped packages release on the same version line; move them together. |
| typescript-eslint | `@typescript-eslint/*` packages + the `typescript-eslint` meta-package | The meta-package and all scoped sub-packages share a version line; mixing versions causes parser/plugin mismatches. |
| Tailwind v4 | `tailwindcss` + `@tailwindcss/vite` + `@tailwindcss/postcss` + `@tailwindcss/cli` | The integrations are co-versioned with the core; mismatched versions cause build-pipeline failures. |

## Recognizing unlisted families

The table is not exhaustive. Treat packages as a lockstep family when any of these hold:

- **Same npm scope, versioned in sync** — e.g. several `@scope/*` packages that always release on the same version number.
- **Plugin suites around a core** — a core package plus a set of `@core/plugin-*` or `core-plugin-*` packages that declare a peer dependency on the core.
- **`*-core` / `*-cli` (or `*-kit`) pairs** — a runtime library shipped alongside its tooling counterpart.
- **Tight peer-dependency webs** — when in doubt, run `npm view <pkg> peerDependencies` and look for hard pins or narrow ranges on sibling packages; those siblings belong in the same group.

When you identify a family this way, also check whether any member is mirrored in the root overrides (`pnpm.overrides` / `overrides` / `resolutions`) and update the override in the same change.

## Not a lockstep family

- **eslint** — eslint plus its plugin/config ecosystem is a peer-range web, not same-version lockstep. Plugins declare peer ranges against eslint but do not need to match each other's versions. When crossing an eslint major, verify each plugin's declared peer range supports the target major before bumping.
