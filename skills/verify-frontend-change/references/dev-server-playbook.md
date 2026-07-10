# Dev-server playbook

How to find, start, monitor, and clean up the dev server for the verification loop.
Read this at Step 1 (and Step 0's "is one already running?" check).

## 1. Find the dev command

Look in `package.json` `scripts`, in this order of preference:

1. `dev` — the convention for Vite, Next.js, Nuxt, Astro, SvelteKit, Remix
2. `start` — CRA, Angular (`ng serve`), and many hand-rolled setups (but in some
   repos `start` runs the *production* server — read the script body, not just the name)
3. `serve` — some Vue CLI / custom setups

Pick the package manager from the lockfile, not from habit:

| Lockfile | Run with |
|---|---|
| `pnpm-lock.yaml` | `pnpm dev` (or `pnpm run <script>`) |
| `yarn.lock` | `yarn dev` |
| `bun.lock` / `bun.lockb` | `bun run dev` |
| `package-lock.json` (or none) | `npm run dev` |

**Monorepo:** if the root `package.json` has `workspaces` (or `pnpm-workspace.yaml`
exists), find the frontend package (the workspace whose `package.json` has the
framework dependency and a `dev` script) and run its script from the root with a
filter — `pnpm --filter <pkg> dev`, `npm run dev -w <pkg>`, `yarn workspace <pkg> dev` —
or `cd` into that package. Verify against the app the change lives in, not whichever
workspace starts first.

**Non-JS frontends** follow the same loop with their own server command:
ASP.NET Core `dotnet watch run` (or `dotnet run`), Rails `bin/dev`, Django
`python manage.py runserver`, Laravel `php artisan serve`, Phoenix `mix phx.server`.

## 2. Check whether a server is already running

Before starting one, probe the framework's default (or configured) port with an HTTP
request — `curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/` from the
Bash tool, or from PowerShell
`curl.exe -s -o NUL -w "%{http_code}" http://localhost:<port>/` (`NUL`, not
`/dev/null`, which curl.exe can't write to — and `curl.exe`, since bare `curl` is an
`Invoke-WebRequest` alias). Common defaults: Vite 5173, Next/CRA/Remix/Astro 3000
(Astro ≥3 uses 4321), Angular 4200, Nuxt 3000, Django 8000. A configured override
(`vite.config.* server.port`, `-p` flag in the script, `.env` `PORT`) beats the default.

- **Responds and it's this app** (sanity-check: the returned HTML matches this project —
  title, bundle path, or a known string): reuse it. Note that you did **not** start it,
  so you must not kill it at cleanup. HMR has likely already picked up the edit, but the
  loop still does its own full reload — HMR hides boot errors and can hold stale module
  state.
- **Responds but it's some other project** squatting on the port: start your own server;
  most dev servers auto-increment to a free port — which is why you must read the URL
  from the server's output, never assume the default.
- **No response**: start it.

## 3. Start it in the background and wait for ready

Run the dev command as a background task (Bash tool with `run_in_background: true`).
Never run it in the foreground — it blocks forever. Then wait for readiness by
**reading the server's output**, polling every few seconds up to ~120s:

- Vite: `Local:   http://localhost:5173/`
- Next.js: `✓ Ready in …` then `Local: http://localhost:3000`
- CRA: `Compiled successfully!`
- Angular: `Local:   http://localhost:4200/`
- Nuxt / Astro / SvelteKit / Remix: a printed `Local:` / `localhost:<port>` URL

**Take the URL from this output verbatim** — when the default port is busy, Vite and
friends silently move to the next one (5174, 5175, …), and navigating to the stale
default would have you verifying somebody else's app. Confirm with the same `curl`
probe as above before opening the browser.

**If the process exits or prints a fatal error instead** (port conflict it couldn't
resolve, missing dependency, config syntax error, crash in a module your change
touched): that is a Step 1 failure. Read the full error output, fix the cause, and
rerun the loop from Step 1. `node_modules` missing entirely → run the package
manager's install first; that's environment setup, not a failure of the change.

## 4. Cleanup

- **You started the server** → stop the background task when the verdict is delivered
  (kill the background shell), unless the user asked to keep it running or is clearly
  mid-session with it. Say which you did.
- **You reused an existing server** → leave it exactly as you found it. Never kill a
  process you didn't start.
- A rerun of the loop after a fix does **not** need a server restart unless the fix
  touched server-side config (`vite.config.*`, `next.config.*`, `.env`, proxy setup,
  dependencies) or the server crashed — HMR covers source edits, and the loop's fresh
  full page load (Step 2) re-executes the app from scratch either way. When in doubt,
  restart: a clean boot is cheap and removes a variable.

## Windows notes

- Use `curl.exe` (not the PowerShell `curl` alias, which is `Invoke-WebRequest` on
  Windows PowerShell 5) for probes, and discard output to `NUL`, never `/dev/null`.
- Port check alternative: `Test-NetConnection -ComputerName localhost -Port 5173`
  (PowerShell) when `curl` isn't available.
- Kill a stray port-holder only if you started it: find the PID with
  `netstat -ano | findstr :<port>`, then `taskkill /PID <pid> /F`. Never do this to a
  server you didn't start.
