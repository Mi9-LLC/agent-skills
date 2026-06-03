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

## Recognizing unlisted families

The table is not exhaustive. Treat packages as a lockstep family when any of these hold:

- **Same npm scope, versioned in sync** — e.g. several `@scope/*` packages that always release on the same version number.
- **Plugin suites around a core** — a core package plus a set of `@core/plugin-*` or `core-plugin-*` packages that declare a peer dependency on the core.
- **`*-core` / `*-cli` (or `*-kit`) pairs** — a runtime library shipped alongside its tooling counterpart.
- **Tight peer-dependency webs** — when in doubt, run `npm view <pkg> peerDependencies` and look for hard pins or narrow ranges on sibling packages; those siblings belong in the same group.

When you identify a family this way, also check whether any member is mirrored in the root overrides (`pnpm.overrides` / `overrides` / `resolutions`) and update the override in the same change.
