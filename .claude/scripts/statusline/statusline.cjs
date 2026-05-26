#!/usr/bin/env node
/**
 * Claude Code statusline (Node.js).
 *
 * Layout (single line, fields separated by │):
 *   model │ ✍️ ctx% │ RL-5h bar pct% (⏱ remaining) │ RL-7d bar pct% (⏱ remaining) │ cwd │ 🧠 thinking │ effort │ 👤 user
 *
 * Schema source: https://code.claude.com/docs/en/statusline
 *   - effort: read from effort.level on stdin (no settings.json lookup).
 *   - duration: read from cost.total_duration_ms.
 *   - rate_limits.*.resets_at: Unix epoch seconds (no ISO parsing).
 *   - thinking: read from thinking.enabled on stdin.
 *   - user: logged-in Claude account from ~/.claude.json (oauthAccount.emailAddress).
 *
 * Configure in .claude/settings.json:
 *   "statusLine": { "type": "command", "command": "node .claude/scripts/statusline/statusline.js" }
 */

const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const C = {
    blue: '\x1b[38;2;0;153;255m',
    orange: '\x1b[38;2;255;176;85m',
    green: '\x1b[38;2;0;175;80m',
    cyan: '\x1b[38;2;86;182;194m',
    red: '\x1b[38;2;255;85;85m',
    yellow: '\x1b[38;2;230;200;0m',
    white: '\x1b[38;2;220;220;220m',
    magenta: '\x1b[38;2;180;140;255m',
    dim: '\x1b[2m',
    reset: '\x1b[0m',
};

const SEP = ` ${C.dim}│${C.reset} `;

const colorForPct = pct => {
    if (pct >= 90) return C.red;
    if (pct >= 70) return C.yellow;
    if (pct >= 50) return C.orange;
    return C.green;
};

const buildBar = (pct, color, width = 10) => {
    const clamped = Math.max(0, Math.min(100, Math.round(pct)));
    const filled = Math.floor((clamped * width) / 100);
    const empty = width - filled;
    return `${color}${'●'.repeat(filled)}${C.dim}${'○'.repeat(empty)}${C.reset}`;
};

const formatRemaining = epoch => {
    if (!epoch || epoch === 0) return '';
    const remaining = epoch - Math.floor(Date.now() / 1000);
    if (remaining <= 0) return '';
    const h = Math.floor(remaining / 3600);
    const m = Math.floor((remaining % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
};

const getClaudeUser = () => {
    try {
        const raw = fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8');
        return JSON.parse(raw).oauthAccount?.emailAddress || '';
    } catch {
        return '';
    }
};

const getSkipPermsSigil = () => {
    if (process.platform === 'win32') return '';
    try {
        const cmd = execSync(`ps -o args= -p ${process.ppid}`, {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'ignore'],
        });

        return cmd.includes('--dangerously-skip-permissions') ? '⚡  ' : '';
    } catch {
        return '';
    }
};

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
    raw += chunk;
});
process.stdin.on('end', () => {
    let data = {};
    if (raw.trim()) {
        try {
            data = JSON.parse(raw);
        } catch {}
    }

    try {
        render(data);
    } catch {
        const fallbackModel = data?.model?.display_name || 'Claude';
        const fallbackCwd = data?.workspace?.current_dir || data?.cwd || process.cwd();
        console.log(`${C.blue}${fallbackModel}${C.reset}${SEP}${C.cyan}${path.basename(fallbackCwd)}${C.reset}`);
    }
});

function render(data) {
    const modelName = data.model?.display_name || 'Claude';

    const ctxSize = data.context_window?.context_window_size || 200000;
    let pctUsed = 0;
    if (data.context_window?.used_percentage != null) {
        pctUsed = Math.round(data.context_window.used_percentage);
    } else if (data.context_window?.current_usage) {
        const u = data.context_window.current_usage;
        const tokens = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
        pctUsed = ctxSize > 0 ? Math.floor((tokens * 100) / ctxSize) : 0;
    }
    const pctColor = colorForPct(pctUsed);

    const cwd = data.workspace?.current_dir || data.cwd || process.cwd();
    const dirname = path.basename(cwd);
    const skipPerms = getSkipPermsSigil();

    const rl = data.rate_limits;
    const rateParts = [];
    if (rl?.five_hour?.used_percentage != null) {
        const pct = Math.round(rl.five_hour.used_percentage);
        const bar = buildBar(pct, C.cyan);
        const remaining = formatRemaining(rl.five_hour.resets_at);
        let s = `${C.cyan}RL-5h${C.reset} ${bar} ${C.cyan}${pct.toString().padStart(3)}%${C.reset}`;
        if (remaining) s += ` ${C.dim}(⏱ ${remaining})${C.reset}`;
        rateParts.push(s);
    }
    if (rl?.seven_day?.used_percentage != null) {
        const pct = Math.round(rl.seven_day.used_percentage);
        const bar = buildBar(pct, C.magenta);
        const remaining = formatRemaining(rl.seven_day.resets_at);
        let s = `${C.magenta}RL-7d${C.reset} ${bar} ${C.magenta}${pct.toString().padStart(3)}%${C.reset}`;
        if (remaining) s += ` ${C.dim}(⏱ ${remaining})${C.reset}`;
        rateParts.push(s);
    }

    const parts = [];
    parts.push(`${C.blue}${modelName}${C.reset}`);
    parts.push(`✍️ ${pctColor}${pctUsed}%${C.reset}`);
    if (rateParts.length) parts.push(rateParts.join(SEP));

    parts.push(`${skipPerms}${C.cyan}${dirname}${C.reset}`);

    const thinkingEnabled = data.thinking?.enabled === true;
    parts.push(thinkingEnabled ? `${C.green}🧠 thinking ON${C.reset}` : `${C.red}🧠 thinking OFF${C.reset}`);

    const effortLevel = data.effort?.level;
    if (effortLevel) {
        let effortStr;
        switch (effortLevel) {
            case 'high':
                effortStr = `${C.magenta}● ${effortLevel}${C.reset}`;
                break;
            case 'low':
                effortStr = `${C.dim}◔ ${effortLevel}${C.reset}`;
                break;
            default:
                effortStr = `${C.dim}◑ ${effortLevel}${C.reset}`;
        }
        parts.push(effortStr);
    }

    const claudeUser = getClaudeUser();
    if (claudeUser) parts.push(`${C.white}🧒 ${claudeUser}${C.reset}`);

    console.log(parts.join(SEP));
}
