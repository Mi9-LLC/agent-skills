---
name: sonar-issue-check
description: >-
  Use this skill to look up and REPORT SonarCloud or SonarQube findings already
  analyzed for the current repo — list, pull, show, summarize, or dump the
  issues, without changing any code. By default report the NEW issues in the
  current branch's or PR's new code (the pre-commit / pre-PR "did I introduce a
  bug, vulnerability, or code smell?" check); report the full backlog on that
  branch/PR on request. Trigger for ANY read-only ask to see Sonar results, even
  when phrased "just give me the list" or "just tell me what Sonar found, don't
  fix anything": e.g. "what did sonarcloud flag on my branch", "pull the sonar
  bugs for PR 412", "did I introduce any new code smells", "check sonar before I
  push", or the quality-gate status on a branch/PR. Do NOT trigger when the user
  wants to FIX or clear the issues (that edits code — use sonar-issue-fix), run
  the Sonar scan itself, set up SonarLint in the editor, or configure
  quality-gate thresholds.
allowed-tools: Bash, Read
---

# Sonar issue check

This skill runs a bundled Node script that reads SonarCloud (or self-hosted
SonarQube) issues for the current repository and prints a terminal summary — no
Sonar web UI needed, and no MCP server or extra install required. The script
has zero npm dependencies (it uses Node's built-in `fetch`), so it runs anywhere
Node is available. Each person just needs their own Sonar token.

## What it reports

- **Default:** unresolved issues introduced in the **new code** of the current
  git branch. This is the "did I just introduce a problem?" check you run
  before committing or opening a pull request.
- **`--all`:** every unresolved issue on the analyzed branch/PR, not just the
  new-code period — use this for a full backlog export.

## Prerequisites — the token

Requires **Node.js 18 or later** (the script uses Node's built-in `fetch`).

The script reads `SONAR_TOKEN` from the environment first (handy in CI), then
from a local `.env` file (`.env`, then `env/.env`, or whatever `--env-file`
points at). Keep the token out of git — `.env` files are conventionally
git-ignored, so each person keeps their own token private. If it is missing,
tell the user to:

1. Sign in to their Sonar instance (e.g. https://sonarcloud.io) → avatar (top
   right) → **My Account** → **Security**.
2. Generate a **User Token**, copy it (shown only once).
3. Set it as an environment variable, or add it to `.env`:
   - bash: `export SONAR_TOKEN=<token>`
   - PowerShell: `$env:SONAR_TOKEN = "<token>"`
   - `.env` file: add a line `SONAR_TOKEN=<token>`

## Configuration — how it finds the project

The script auto-detects everything from the repo, so the common case needs no
arguments:

- **Project key & organization** — read from `sonar-project.properties`
  (`sonar.projectKey`, `sonar.organization`), the canonical file the
  SonarScanner itself uses. If that file is absent it falls back to the
  SonarLint binding in `.vscode/settings.json` (`projectKey`). Override with
  `--project` / `--org` (or `SONAR_ORG`).
- **Host** — `sonar.host.url` from `sonar-project.properties`, else
  `SONAR_HOST_URL`, else `https://sonarcloud.io`. Override with `--host`.
- **Branch / PR** — the current git branch by default.

**SonarCloud vs self-hosted SonarQube:** the `organization` parameter is sent
only when targeting SonarCloud (or when you pass `--org`), because self-hosted
SonarQube has no organizations concept. For a self-hosted server just point
`--host` at it. On SonarCloud, if no organization is configured anywhere, the
script derives it from the project-key prefix (keys are conventionally
`<org>_<repo>`) and notes "derived from key" in its header — pass `--org` if
that guess is wrong.

## How to run

```bash
node ${CLAUDE_SKILL_DIR}/scripts/extract-sonar-issues.mjs
```

Pick the variant that matches what the user asked for:

| User intent | Command |
|-------------|---------|
| New issues before commit/PR (default) | *(no extra flags)* |
| A specific pull request | `--pull-request <id>` |
| A specific branch | `--branch <name>` |
| Full unresolved backlog on the branch/PR | `--all` |
| Only bugs & vulnerabilities | `--types BUG,VULNERABILITY` |
| Only high-severity issues | `--severities BLOCKER,CRITICAL`<br>(legacy severity names — Sonar deprecated `severities` and `types` in Aug 2023 for MQR impact severities/qualities, but the API still honors both flags; the script also reports each issue's MQR `impacts`) |
| Include resolved/closed issues too | `--include-resolved` |
| Target a different project than auto-detected | `--project <key>` |
| Target a different organization than auto-detected | `--org <org>` |
| Read the token from a custom `.env` file | `--env-file <path>` |
| Self-hosted SonarQube | `--host https://sonar.mycompany.com` |
| Save full results to a file | `--out sonar-issues.json` |
| Use as a hard gate (non-zero exit on findings) | `--fail-on-issues` |

Run with `-h` to see every option.

## Interpreting the result

- The script prints the host, project, the target (branch or PR), the scope,
  counts by severity and type, and one line per issue as `file:line` + message +
  rule. The JSON dump (`--out`) also carries each issue's MQR `impacts` array
  (software quality + severity) when the server provides it.
- If the user asks to see the full JSON after a run with `--out`, Read that
  file directly rather than re-running the script.
- After running, give the user a short verdict, not a raw dump: lead with
  whether the branch is clean, then call out the highest-severity new issues and
  where they are. If there are many, group by severity and summarize the rest.
- **Important timing note** — Sonar only knows about code that its scan has
  already analysed. Right after a local `git commit` (before the branch is
  pushed and the CI scan runs), this check still reflects the *previous* push.
  For truly live, in-editor feedback as you type, SonarLint connected mode is
  the right tool; this skill is best run *after pushing a branch* or once a pull
  request exists.

## When NOT to use this skill

- Running the actual Sonar scan (that happens in your CI pipeline, not here) —
  this skill only *reads* results.
- Local lint / type / test gates — those are your project's own commands (e.g.
  `npm run lint`, `npm test`), not this skill.
