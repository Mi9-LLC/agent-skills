# Mi9 Skills

Mi9 LLC public catalog of Claude Code Agent Skills.

> **⚠️ Important:** Make sure you trust a skill before installing or running it. Skills can execute commands and read your files when triggered.

## Skills at a glance

| Skill | What it does |
|---|---|
| [`security-vulnerability-scan`](#security-vulnerability-scan) | [OWASP Top 10:2025](https://owasp.org/Top10/2025/) static scan of any codebase; writes `audit/<YYYY-MM-DD>/report.md`. |
| [`anti-sycophancy`](#anti-sycophancy) | Behavioral mode for review/feedback/decision asks. Argues the opposing case first, names untested assumptions, refuses reflexive agreement. No file output. |

---

## `security-vulnerability-scan`

**What it does.** OWASP Top 10:2025-aligned static vulnerability scanner. Detects common security issues across the relevant stack — web frameworks, IaC, container configs, dependency lockfiles, secrets — and writes a structured assessment to disk.

**Use it for.** PR reviews, periodic full-repo sweeps, onboarding to an unfamiliar codebase, or any "is there anything obvious" check. Designed to overtrigger rather than miss a real risk.

**Triggers on phrases like.** "review this code", "security review", "audit this app", "scan for vulnerabilities", "OWASP check", "find secrets", "harden security", "pentest this", "assess risk", "audit dependencies" — and casual variants ("what's broken here", "is this safe to ship").

**What it produces.**
- A Markdown report at `<project-root>/audit/<YYYY-MM-DD>/report.md` with severity-ranked findings (Critical / High / Medium / Low), OWASP A0X:2025 + CWE mappings, file:line citations, attack scenarios, remediations, and a prioritized fix list.
- **Read-only on the target source tree.** Never modifies source files, configs, dependencies, lockfiles, `.env*`, or `.gitignore` of the repo being scanned. The only write is `audit/`.
- If the working directory is empty, the skill asks for a GitHub URL and clones with `gh` before scanning.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill security-vulnerability-scan
```

**Full definition:** [`skills/security-vulnerability-scan/SKILL.md`](skills/security-vulnerability-scan/SKILL.md) (plus per-category reference docs under `references/`).

---

## `anti-sycophancy`

**What it does.** Behavioral skill that swaps Claude into critical-thinking-partner mode. Instead of agreeing reflexively or hedging, Claude argues the strongest opposing case first, names the load-bearing untested assumption, surfaces weaknesses before strengths, refuses to retreat without new evidence or reasoning, and ends with a question worth sitting with — not a recap.

**Use it for.** Stress-testing your own judgment on decisions, plans, interpretations, or work you're about to commit to. The skill is the friction you'd ask a sharp colleague for — not the validation you'd get from a friendly one.

**Triggers on phrases like.** "should I", "I'm planning to", "I've decided", "what do you think", "is this the right call", "review my plan", "my read on this", "am I seeing this right" — plus explicit pushback asks: "play devil's advocate", "be brutal", "punch holes", "challenge me", "don't tell me it's a good idea". Confidence and stakeholder buy-in (`the team agrees`, `leadership signed off`) **amplify** activation rather than skip it.

**What it does not do.** Activate on objective technical questions with one knowable answer — syntax, config values, debugging, conversions, proofreading — even when phrased "is this correct?" Those need execution, not opposition.

**What it produces.** Nothing on disk. Purely a behavioral mode that shapes the conversational response.

**Install.**

```
npx skills add https://github.com/Mi9-LLC/agent-skills --skill anti-sycophancy
```

**Full definition:** [`skills/anti-sycophancy/SKILL.md`](skills/anti-sycophancy/SKILL.md).

---

## Contributing

To add or modify a skill:

1. Create or edit a directory under `skills/<skill-name>/` containing a `SKILL.md` (YAML frontmatter with `name` + `description` + optional `allowed-tools`, plus a Markdown body). Long-form reference docs go under `skills/<skill-name>/references/`.
2. Add a row to the **Skills at a glance** table and a per-skill section to this README (mirror the format above: *what it does*, *use it for*, *triggers on*, *what it produces*, *install*, *full definition* link). Consumers discover skills from this README — an undocumented skill is effectively unshipped.
3. Open a PR against `main`. Teammates pick up the new version on their next `npx skills add … --skill <name>`.

There are no versions to bump and no catalogs to update — `npx skills add` always pulls the current state of the branch it points at. Tag releases (e.g. `v1.0.0`) only when you want to offer a `--ref`-able pin.

## License

[MIT](LICENSE).

## Documentation

For more on Claude Code Agent Skills, see the [official Anthropic documentation](https://code.claude.com/docs/en/skills) and [`anthropics/skills`](https://github.com/anthropics/skills) for the canonical layout.
