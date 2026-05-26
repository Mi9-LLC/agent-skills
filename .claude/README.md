# `.claude/` directory

Claude Code tooling for this repo. Currently just the custom statusline.

## One-time setup on a new machine

The statusline is wired up via `.claude/settings.local.json`, which is **gitignored** because it carries a machine-specific absolute path. After cloning the repo, create that file yourself:

```json
{
    "statusLine": {
        "type": "command",
        "command": "node \"<absolute path to repo>/.claude/scripts/statusline/statusline.cjs\"",
        "refreshInterval": 5
    }
}
```

Replace `<absolute path to repo>` with the full path where you cloned the repo (forward slashes, e.g. `C:/Develop/Mi9 Artifacts/Claude Plugins`). Restart Claude Code in the project directory and the statusline appears at the bottom of the terminal.

### Why absolute, why local

- **Why absolute:** Claude Code silently drops the statusline when `command` uses a project-relative path on this setup (Git Bash on Windows). Absolute paths are reliable.
- **Why `settings.local.json`:** the path differs per clone location, so it can't be committed. Claude Code merges `settings.local.json` into `settings.json` automatically; the `.local.json` half is conventionally per-developer and is in `.gitignore`.

## What the statusline shows

See `scripts/statusline/README.md` (vendored from another project — partially out of sync with the current script, but the customization/troubleshooting sections are still useful).
