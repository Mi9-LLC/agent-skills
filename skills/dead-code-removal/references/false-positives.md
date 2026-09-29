# False-positive checklist

Clear every entry that applies before calling an item VALID. Each one has produced a wrong
"unused" verdict in a real repository.

## Every language

1. **A barrel or index file that contains logic.** An `index` file that imports its siblings and
   dispatches to them (a factory, a `switch` over strategy names) keeps all of them alive, even
   though only the index imports them. Read the index before calling its siblings orphaned.
2. **Paths that differ by one segment.** `server/shared/index.ts` and `server/modules/shared/index.ts`
   can have opposite answers. Resolve each import to a real file; never match on a path suffix.
   This is the main risk when deleting barrel files. Use an import resolver that follows the
   path aliases, and run it once on a file that is known to be used: if that control file shows
   no importers, the resolver is wrong, and its "no importers" for the file to delete proves
   nothing.
3. **Used inside its own file.** A type used as a parameter type, a return type, or the base of an
   `extends` in the same file is live. Only its `export` keyword is unused. Delete the keyword,
   keep the declaration.
4. **Something that extends or implements it.** An interface or class with no direct reference can
   still be the base of another type. Delete them together or not at all.
5. **The same name defined twice.** A name search finds the other definition and makes a dead
   symbol look alive, or the other way round. Resolve every hit to its definition.
6. **Registries keyed by strings.** Factories, rule registries, dependency-injection containers,
   plugin lists and route tables reach code by a string or a registration call. Search for the
   registration, not only the import.
7. **Computed dynamic imports.** `import(\`./pages/${name}\`)` reaches files no static search sees.
   Lazy routes, lazy components and plugin loaders are the usual places.
8. **Configuration files.** Build, test, lint and bundler configs name files and packages
   (`vitest.config`, `vite.config`, `eslint.config`, `tsconfig` paths, `.csproj` items). So do CI
   files.
9. **Deploy scripts, Dockerfiles and environment variables.** A script or an env var can be the
   only thing that reaches a file or a code path. Read the literal lists of variables a deploy
   script sets; do not assume a `.env` file reaches the running container.
10. **The package's public surface.** An entry in a `package.json` `exports` map, or a public type
    of a published package, can have consumers outside the repository. Check whether the package
    is published (a `private` flag, a publish config, a registry in `.npmrc`, a publish step in CI)
    before treating its exports as internal. For an internal workspace package, its exports
    are fair game.
11. **Composed routers.** A tRPC, Express, Fastify or ASP.NET router assembled from sub-routers can
    expose a function that no name search connects to a route. Read every composed sub-router by
    hand before deleting something an API route could reach.
12. **Tests.** A reference from a test is a reference, but not proof of use. Report test-only
    items as their own list; the user decides.
13. **Files git does not track.** A document under an ignored folder cannot be changed in a commit.
    Check `git ls-files` or `git check-ignore` before listing a document to edit.
14. **Other repositories.** When a package or a table definition could be shared, search the sibling
    repositories on disk for imports of it, source files only.

## TypeScript and JavaScript

- ESM imports end in `.js` while the source file is `.ts` or `.tsx`. Resolve both.
- Resolve `tsconfig` `paths` aliases (`@/`, `@server/`) and directory imports that resolve to an
  `index` file.
- `vi.mock('<path>')` and `jest.mock('<path>')` name modules as strings.
- In a monorepo, a workspace package import (`@scope/pkg`) resolves through its `exports` map to a
  built file; follow it back to the source.
- JSX usage (`<Component />`) is a reference; a search for `Component(` misses it.

## C# and .NET

- Reflection, attribute discovery (controllers, hosted services, `[JsonConverter]`), and
  assembly scanning in DI registration reach types with no direct reference.
- `InternalsVisibleTo` makes `internal` members visible to other assemblies, usually test projects.
- Razor views, `appsettings.json` bindings and source generators reference members by name.
- The IDE0051 and IDE0052 analyzers see private members only; they say nothing about public ones.
