# Claude Code Statusline

A custom statusline for [Claude Code](https://claude.ai/code) that displays real-time session metrics, rate limit tracking, and git status.

## Example Output

<div style="background-color:#1e1e1e; color:#d4d4d4; padding:12px; border-radius:6px; font-family:monospace; font-size:14px; line-height:1.5;">
<span style="color:#36d9ff;">Opus</span> | <span style="color:#4ec9b0;">[</span><span style="color:#4ec9b0;">===========</span><span style="color:#858585;">----------</span><span style="color:#4ec9b0;">]</span> | <span style="color:#4ec9b0;">90k/200k (45%)</span> | <span style="color:#36d9ff;">Elapsed: 2hr 41m (45% used)</span> | <span style="color:#4ec9b0;">Reset in: 2hr 18m</span> | <span style="color:#d78ae6;">(develop)</span> | <span style="color:#4ec9b0;">My Project</span>
</div>

**Color meanings:**
- **Cyan** (`#36d9ff`) — Model name, Elapsed timer
- **Green** (`#4ec9b0`) — Progress bar, Token display, Reset timer, Project name
- **Magenta** (`#d78ae6`) — Git branch
- **Dim Gray** (`#858585`) — Progress bar empty space

## What It Shows

| Widget | Description | Color |
|--------|-------------|-------|
| **Model** | Current Claude model (Opus, Sonnet, etc.) | Cyan |
| **Progress Bar** | Visual context window usage | Green/Yellow/Red |
| **Tokens** | Used/max tokens + percentage (e.g. `90k/200k (45%)`) | Green/Yellow/Red |
| **Elapsed** | Time elapsed in the 5-hour rate limit window + % used | Cyan/Yellow/Red |
| **Reset in** | Time remaining until rate limit window resets | Green/Yellow/Red |
| **Git Branch** | Current branch name | Magenta |
| **Project** | Project directory name | Green |

### Color Schema

Both the progress bar and token display use the same dynamic color coding:

- **Green** — < 50% usage
- **Yellow** — 50–80% usage
- **Red** — > 80% usage

## Prerequisites

- **Node.js** >= 18.17 (for `fs.readdirSync` with `recursive: true`)
- **Claude Code** CLI with statusline support
- **Git** (optional, for branch and diff stats)

## Installation (Any Project)

### Step 1: Copy the Script

Copy `statusline.cjs` into your project's `.claude/scripts/statusline/` directory:

```bash
# From your project root
mkdir -p .claude/scripts/statusline
cp /path/to/statusline.cjs .claude/scripts/statusline/statusline.cjs
```

Or download it directly into your project:

```bash
mkdir -p .claude/scripts/statusline
curl -o .claude/scripts/statusline/statusline.cjs \
  https://raw.githubusercontent.com/<your-org>/<your-repo>/develop/.claude/scripts/statusline/statusline.cjs
```

### Step 2: Configure Claude Code Settings

Add or merge the following into your project's `.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node .claude/scripts/statusline/statusline.cjs",
    "padding": 0
  }
}
```

If the file already exists, just add the `"statusLine"` key to the existing JSON object.

### Step 3: Configure Token Quota (Optional)

The statusline estimates rate limit usage as a percentage. The default quota is **97,000,000 tokens** per 5-hour window, calibrated for the **Max 5x** plan.

To override for a different plan, set the environment variable:

```bash
# In your shell profile (.bashrc, .zshrc, etc.)
export NEXUS_STATUSLINE_TOKEN_QUOTA=97000000   # Max 5x (default)
export NEXUS_STATUSLINE_TOKEN_QUOTA=19400000   # Pro (estimated ~1/5 of Max 5x)
export NEXUS_STATUSLINE_TOKEN_QUOTA=388000000  # Max 20x (estimated ~4x of Max 5x)
```

### Step 4: Verify

Start a new Claude Code session in your project directory. The statusline should appear at the bottom of the terminal.

To test manually:

```bash
echo '{"model":{"display_name":"Opus"},"cost":{"total_duration_ms":5400000},"context_window":{"used_percentage":45,"context_window_size":200000},"workspace":{"project_dir":"'"$(pwd)"'"}}' \
  | node .claude/scripts/statusline/statusline.cjs
```

Expected output (with ANSI colors):
```
Opus | [==========-----------] | 90k/200k (45%) | Elapsed: 2hr 41m (45% used) | Reset in: 2hr 18m | (develop) | my-project
```

### Step 5: Add to .gitignore (Optional)

If you don't want to commit the context state file written by the statusline:

```gitignore
# Claude Code statusline state
.claude/context-state.json
```

## How It Works

### Rate Limit Timers (`Elapsed` / `Reset in`)

1. Scans `~/.claude/projects/**/*.jsonl` for API call timestamps
2. Finds the largest idle gap (>= 30 min) within the last 5 hours
3. The block starts at the first API call after that gap
4. Caches the block start at `~/.cache/nexus-statusline/block-cache.json` (auto-invalidates when the block expires)

### Usage Percentage (`N% used`)

Sums all tokens (input + cache + output) within the current block window and divides by the configured quota. This is an estimate -- Anthropic's actual rate limit accounting is opaque and may differ slightly.

### Git Diff Stats (`+N -N`)

Runs `git diff HEAD --shortstat` to show uncommitted insertions and deletions.

## Customization

### Changing Colors

Edit the `colors` object near the top of `statusline.cjs`:

```js
const colors = {
  cyan: '\x1b[36m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[91m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  reset: '\x1b[0m',
  dim: '\x1b[2m',
};
```

### Context Warning Threshold

The script writes a context state file for hook consumption. To change when it triggers:

```js
const CONTEXT_THRESHOLD = 65; // percentage
```

### Removing Widgets

Each widget is an independent section in the `process.stdin.on('end', ...)` handler, marked with numbered comments. Delete or comment out any section you don't want.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No statusline appears | Ensure `.claude/settings.json` has the `statusLine` config and Node.js >= 18.17 is installed |
| No git branch/diff | Verify `git` is in PATH and you're in a git repository |
| Block/Reset timers missing | No recent JSONL files found in `~/.claude/projects/`. Start a conversation first |
| Usage % seems wrong | Adjust `NEXUS_STATUSLINE_TOKEN_QUOTA` env var for your plan |
| Cache seems stale | Delete `~/.cache/nexus-statusline/block-cache.json` to force a fresh JSONL scan |

## Credits

Block timer logic inspired by [ccstatusline](https://github.com/sirmalloc/ccstatusline).
