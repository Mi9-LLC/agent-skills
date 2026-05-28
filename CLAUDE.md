# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is the **Mi9 LLC public catalog of Claude Code Agent Skills**, hosted on GitHub at `github.com/Mi9-LLC/agent-skills`. Teammates and external users install individual skills with:

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill <skill-name>
```

It is **not** application code. There is no build, test, or lint pipeline — the entire repo is Markdown skill definitions. Do not invent commands; there are none to run.

## Layout

Flat skills layout, matching the canonical [`anthropics/skills`](https://github.com/anthropics/skills) example:

- `skills/<name>/SKILL.md` — the **skill definition** (YAML frontmatter with `name`, `description`, `allowed-tools` + Markdown body that's loaded into the model when the skill triggers).
- `skills/<name>/references/` — on-demand reference docs the skill reads itself when it needs the detail. Keep these out of `SKILL.md` so the always-loaded body stays small.

There are no plugin manifests, no `.claude-plugin/` directory, and no top-level catalog file. Adding any of those would mix two distribution mechanisms — see "Distribution mechanism" below for why we don't.

## Current skills

- **`security-vulnerability-scan`** (`skills/security-vulnerability-scan/`) — OWASP Top 10:2025 static scanner. **Read-only on the target source tree**; writes only `audit/<YYYY-MM-DD>/report.md`. Never modifies source files, configs, lockfiles, or `.gitignore` of the repo being scanned.
- **`live-app-security-audit`** (`skills/live-app-security-audit/`) — Runtime audit of a deployed live URL. Seven checks: security headers, TLS, frontend-bundle secret search, localStorage tokens, unauthenticated endpoints, login rate-limit, username enumeration. **Read-only on the user's source tree**; writes only `audit/<YYYY-MM-DD>/live-audit.md` (mirrors `security-vulnerability-scan`'s path, so both reports live side-by-side). Active probes (rate-limit, enumeration) require explicit target-authorization at Step 0; uses RFC-reserved `.invalid` emails for probes. Designed as the runtime counterpart to `security-vulnerability-scan`.
- **`anti-sycophancy`** (`skills/anti-sycophancy/`) — Behavioral skill that swaps Claude into critical-thinking-partner mode for review/feedback/decision asks. Argues the strongest opposing case first, names untested assumptions, surfaces weaknesses before strengths, ends with a sit-with question. **No file output, no tool access** — purely shapes how Claude responds. Trigger description carved by `skill-creator`'s description-optimization loop against an Opus 4.7 eval set.

## Contributing

1. Create or edit a directory under `skills/<skill-name>/`. Include a `SKILL.md`; put long-form reference docs under `references/`.
2. Open a PR against `main`. Teammates pick up changes on their next `npx skills add … --skill <name>`.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at.

## Distribution mechanism

This repo distributes **only** via `npx skills`. The earlier Bitbucket-hosted `mi9-plugins` marketplace (using `.claude-plugin/marketplace.json` + `/plugin install`) was retired because the Claude Code TUI's `/plugin install` flow hit a "source type not supported" bug that blocked teammates from installing through the UI. The skills-only model bypasses that flow entirely.

If we ever need to ship non-skill components (agents, hooks, MCP servers, LSP) from the same repo, the two options are:

1. Add a `.claude-plugin/marketplace.json` back alongside the flat `skills/` tree (dual-mode — `anthropics/skills` itself does this), or
2. Split into a second repo.

Not in scope today; flagged for future reconsideration.
