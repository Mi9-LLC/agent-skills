#!/usr/bin/env python3
"""UserPromptSubmit hook: detect a request for shorter/simpler/less AI-sounding CHAT
replies and tell Claude to load the clear-and-short skill so the change persists.

Deliberately narrow. The model already shortens or plainens a single reply on its own;
what it reliably fails to do is load the skill, which is what makes the mode hold for the
session. Patterns therefore target reply-directed mode switches only -- never a request to
shorten or de-AI a file, code, or prose written for other readers (that is unslop's job,
or plain editing).

Two kinds of request, because they are not the same ask:

  LENGTH -- "be brief", "too many words", "use fewer tokens".
  VOICE  -- "humanize your responses", "remove the AI tells", "stop writing like an AI".

A VOICE-only prompt asks for a different voice, not for less content, so its directive
tells Claude to apply the skill's voice rules and leave the length caps off.

STRONG patterns are unambiguously about Claude's own replies and fire on their own. WEAK
patterns ("too verbose", "ai tells") are ambiguous -- they read the same way aimed at a
function or a PR description -- so they fire only when the prompt names no code/document
target.

The VOICE directive is also the always-on default. On the FIRST prompt of a session that
matches no pattern at all, the hook emits it once and records the session id in SEEN_PATH,
so replies are plain from the start without anyone having to type "humanize your
responses". VOICE and not LENGTH, because a default must not silently drop content the
user never asked to lose -- plainer wording costs nothing, the length caps cut facts.
Once per session and not every prompt, for two reasons: re-injecting the same text on
every turn buys nothing, and it would fight the rest of the session -- after that first
prompt the hook is quiet again, so a later "be brief" still upgrades to the length rules
and a later "normal mode" still turns the skill off. A prompt that matches a pattern
closes out the default as well: it emits its own directive AND records the session, so
the voice directive can never fire a turn later and tell the model to drop the length
rules the user just asked for.

Three things hold the default back, none of which touch a prompt that matches a pattern
(an explicit "be brief" is a real request and is always honored):

  OFF-SWITCH  -- "normal mode", "stop clear-and-short", "stop being brief" and friends ask
                 for the mode OFF. They match none of the pattern lists, so without this
                 check the very prompt asking for the mode off would receive the default.
                 An off-switch prompt emits nothing and records the session, which also
                 stops the default firing later in that session.
  ENTRYPOINT  -- the environment variable CLAUDE_CODE_ENTRYPOINT names how Claude Code was
                 started: "cli" for an interactive terminal, "sdk-cli" for `claude -p` and
                 SDK runs (observed on Claude Code 2.1.251). The default fires only for "cli",
                 or when the variable is absent (older versions keep working). Otherwise
                 `claude -p`, SDK runs and eval harnesses would silently get a directive
                 nobody asked for, changing output that is being measured for something else.
  SOURCE      -- the payload's "source" field, when present, says who typed the prompt
                 ("user", "sdk", "system", ...). The default fires only for "user", or when
                 the field is absent. On 2.1.251 the `claude -p` payload carries no "source"
                 at all, which is why the ENTRYPOINT gate above exists; this one stays for
                 payloads that do carry it.
  OPT-OUT     -- setting the environment variable CLEAR_AND_SHORT_NO_DEFAULT to any
                 non-empty value turns the default off permanently, without uninstalling
                 the hook.
"""
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

# session_id -> ISO timestamp of the prompt that got the default VOICE directive.
SEEN_PATH = Path.home() / ".claude" / ".clear-and-short-sessions.json"
SEEN_TTL_DAYS = 7

STRONG_LENGTH = [
    r"\bbe (brief|concise|terse)\b",
    r"\bkeep it (short|brief|shorter|concise)\b",
    r"\bkeep your (replies|answers|responses) (short|brief|shorter|concise)\b",
    r"\b(shorter|briefer|more concise) (replies|answers|responses)\b",
    r"\byour (replies|answers|responses)\b.{0,40}?\btoo (long|verbose|wordy|many words)\b",
    r"\bstop repeating (yourself|the same)\b",
    r"\b(save|use fewer|stop wasting|don'?t waste|waste fewer) tokens\b",
    r"\b(stop|don'?t|do not|no more) narrat",
    r"\bnarration of (every|each)\b",
    r"\b(simple|plain) english\b",
    r"\bnot a native (english )?speaker\b",
    r"\bnon-?native (english )?speaker\b",
    r"\bfrom now on\b.{0,40}?\b(short|brief|concise)\b",
    r"\b(short|brief|concise)\b.{0,20}?\bfrom now on\b",
]

WEAK_LENGTH = [
    r"\btoo verbose\b",
    r"\btoo many words\b",
    r"\bless verbose\b",
]

STRONG_VOICE = [
    r"\bhumaniz\w*\s+(your|the|these)\s+"
    r"(replies|answers|responses|writing|output|wording|tone|voice|style)\b",
    r"\bde-?ai\s+(your|the|these)\s+(replies|answers|responses|writing|output)\b",
    r"\bstop\s+(sounding|writing|talking|reading)\s+like\s+"
    r"(an?\s+)?(ai|chat\s?gpt|robot|llm|bot|machine)\b",
    r"\bdon'?t\s+(sound|write|talk)\s+like\s+(an?\s+)?(ai|chat\s?gpt|robot|llm|bot)\b",
    r"\byour\s+(replies|answers|responses|writing|wording|tone)\b.{0,40}?"
    r"\b(sound|read|look|feel)s?\s+like\s+(an?\s+)?(ai|chat\s?gpt|robot|llm|bot)\b",
    r"\bless\s+ai-?(sounding|generated|ish)\b",
    r"\b(stop using|no more|cut the|drop the)\s+em\s?-?dashes?\b",
]

WEAK_VOICE = [
    r"\bai\s+tells?\b",
    r"\b(sound|read)s?\s+like\s+(an?\s+)?(ai|chat\s?gpt)\b",
]

# The words that make a phrase about Claude's own replies rather than about a dropdown,
# an API, or a quiz.
REPLY = r"(?:replies|answers|responses|output|writing|wording)"

# Asks for the mode OFF, matched ANYWHERE in the prompt. Each one is reply-directed on its
# own -- it names the skill, names Claude's replies, or asks Claude to stop being brief --
# so none needs the untargeted check the WEAK lists use. The generic phrases that read the
# same way in an unrelated sentence ("normal mode", "back to normal") live in
# OFF_SWITCH_ONLY below instead.
OFF_SWITCH = [
    # The skill by name.
    r"\b(stop|end|exit|quit|turn off|switch off|disable|cancel)\b.{0,20}?"
    r"\bclear[\s-]?and[\s-]?short\b",
    r"\bclear[\s-]?and[\s-]?short\b.{0,20}?\boff\b",
    # Asking Claude to stop being brief.
    r"\bstop being (brief|concise|terse|short|so short|so brief|so concise)\b",
    r"\bstop (keeping|making) (it|them|your (replies|answers|responses))\b.{0,20}?"
    r"\b(short|brief|concise)\b",
    r"\bstop\b.{0,20}?\b(the )?(short|brief|concise) (mode|replies|answers|responses)\b",
    # "be verbose" is an off-switch only when it is aimed at the replies: "again" means
    # back to how Claude answered before, and "your replies" says it outright. Bare
    # "be verbose about the error" asks for more detail on a topic, not for the mode off.
    r"\bbe (verbose|wordy|long|longer|detailed|thorough)\s+again\b",
    r"\bbe (verbose|wordy|long|longer|detailed|thorough)\b.{0,30}?\byour\s+" + REPLY + r"\b",
    # "full/normal/longer replies", but only when they are Claude's replies -- "full
    # answers to the quiz" and "the API returns longer responses" are neither.
    r"\byour\s+(full|normal|long|longer|verbose|regular)\s+" + REPLY + r"\b",
    r"\b(back to|go back to|return to|resume|give me|i want)\s+"
    r"(full|normal|long|longer|verbose|regular)\s+" + REPLY + r"\b",
    # "back to normal" tied to the replies in the same breath, either order.
    r"\b(back|go back|revert|return) to (normal|your normal|full|the usual|regular)\b"
    r".{0,30}?\byour\s+" + REPLY + r"\b",
    r"\byour\s+" + REPLY + r"\b.{0,30}?"
    r"\b(back|go back|revert|return) to (normal|your normal|full|the usual|regular)\b",
]

# Asks for the mode OFF, matched against the WHOLE prompt. These phrases are too generic
# to look for inside a sentence -- "normal mode" also appears in "the normal mode of
# failure", "back to normal" in "make the dropdown return to normal size". A real
# off-switch message is the switch and nothing else, so they must account for the entire
# prompt, give or take politeness.
OFF_SWITCH_ONLY = [
    r"(?:go\s+)?(?:back\s+to\s+)?normal\s*mode",
    r"(?:go\s+|switch\s+)?back\s+to\s+normal(?:\s+mode)?",
    r"return\s+to\s+normal(?:\s+mode)?",
    r"(?:back\s+to\s+)?(?:full|normal|regular|verbose|longer)\s+"
    r"(?:replies|answers|responses|mode)",
    r"normal\s+(?:voice|style|length)",
]

# Filler an off-switch message carries without becoming a sentence about something else.
POLITE_PREFIX = r"(?:(?:ok(?:ay)?|please|hey|claude|and|now)[\s,]+)*"
POLITE_SUFFIX = r"(?:[\s,]+(?:please|now|again|thanks|thank\s+you|claude))*"

# A named code/document target means a WEAK match is about that thing, not the reply.
TARGET = (
    r"\b(function|method|class|variable|docstring|comment|paragraph|sentence|"
    r"readme|changelog|release notes?|commit message|pull request|pr description|"
    r"docs?|documentation|blog|post|article|ticket|issue|log|file|script|test)\b"
    r"|\.(md|ts|tsx|js|jsx|py|cs|java|go|rs|json|ya?ml|txt)\b"
    r"|[\w./-]+/[\w./-]+"
)


def _compile(patterns):
    return [re.compile(p, re.I) for p in patterns]


STRONG_LENGTH_RX = _compile(STRONG_LENGTH)
WEAK_LENGTH_RX = _compile(WEAK_LENGTH)
STRONG_VOICE_RX = _compile(STRONG_VOICE)
WEAK_VOICE_RX = _compile(WEAK_VOICE)
OFF_SWITCH_RX = _compile(OFF_SWITCH)
OFF_SWITCH_ONLY_RX = _compile(
    [POLITE_PREFIX + "(?:" + p + ")" + POLITE_SUFFIX for p in OFF_SWITCH_ONLY]
)
TARGET_RX = re.compile(TARGET, re.I)

INVOKE = (
    "Invoke the clear-and-short skill now (Skill tool, skill: \"clear-and-short\") "
    "BEFORE answering the rest of this message, then answer under it."
)
PERSIST = (
    "Answering that way just this once is not enough: loading the skill is what makes the "
    "change hold for the rest of the session and what protects the detail that must never "
    "be cut."
)
SCOPE = (
    "This applies to chat replies only -- do not rewrite code, comments, commit messages, "
    "documentation, or prose written for other readers (that is the unslop skill's job)."
)

DIRECTIVE_LENGTH = (
    "The user is asking for shorter, simpler, or less repetitive chat replies. "
    + INVOKE + " " + PERSIST + " " + SCOPE
)
DIRECTIVE_VOICE = (
    "The user is asking for chat replies without the tells that mark writing as "
    "machine-generated. " + INVOKE + " Apply the skill's \"Cut - always\", \"Simple "
    "English\", and \"No AI tells\" sections. Do NOT apply its length rules: this is a "
    "request for a different voice, not for less content, so still state every fact the "
    "answer needs. " + PERSIST + " " + SCOPE
)
DIRECTIVE_BOTH = (
    "The user is asking for chat replies that are shorter and free of the tells that mark "
    "writing as machine-generated. " + INVOKE + " Apply the whole skill, including its "
    "\"No AI tells\" section. " + PERSIST + " " + SCOPE
)


def classify(prompt: str) -> str:
    """Return "length", "voice", "both", or "" for a prompt.

    A weak match counts only when the prompt names no code or document target.
    """
    untargeted = not TARGET_RX.search(prompt)
    length = any(rx.search(prompt) for rx in STRONG_LENGTH_RX) or (
        untargeted and any(rx.search(prompt) for rx in WEAK_LENGTH_RX)
    )
    voice = any(rx.search(prompt) for rx in STRONG_VOICE_RX) or (
        untargeted and any(rx.search(prompt) for rx in WEAK_VOICE_RX)
    )
    if length and voice:
        return "both"
    if length:
        return "length"
    if voice:
        return "voice"
    return ""


def _normalize(prompt: str) -> str:
    """Lowercase, collapse whitespace, drop surrounding punctuation. For whole-prompt matching."""
    return re.sub(r"\s+", " ", prompt.strip().lower()).strip(" .!?,;:\"'")


def is_off_switch(prompt: str) -> bool:
    """True when the prompt asks for the mode OFF ("normal mode", "stop clear-and-short").

    Two tests. The reply-directed phrases are looked for anywhere in the prompt; the
    generic ones must account for the whole prompt, or an ordinary sentence that happens
    to contain "normal mode" would silently suppress the default for the whole session.

    Kept out of classify() on purpose: classify() names the directive to emit, and an
    off-switch emits none. It only decides whether the default stays quiet.
    """
    if any(rx.search(prompt) for rx in OFF_SWITCH_RX):
        return True
    text = _normalize(prompt)
    return any(rx.fullmatch(text) for rx in OFF_SWITCH_ONLY_RX)


def _load_seen() -> dict:
    """Read the seen-session map. A missing or malformed file counts as empty.

    Same reasoning as the malformed-payload guard in main(): the seen-file is a
    convenience, never a reason to interfere with a prompt.
    """
    try:
        with open(SEEN_PATH, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}


def _record_seen(session_id: str) -> bool:
    """Record session_id, dropping entries older than SEEN_TTL_DAYS. True when written.

    The write goes through a temporary file in the same directory plus os.replace, so a
    reader never sees a half-written map. Any failure -- a missing or unwritable
    ~/.claude, a full disk -- returns False instead of raising: the prompt must go through
    either way.
    """
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=SEEN_TTL_DAYS)
    kept = {}
    for sid, stamp in _load_seen().items():
        try:
            when = datetime.fromisoformat(stamp)
        except ValueError:
            continue  # unparseable timestamp: drop it rather than keep it forever
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        if when >= cutoff:
            kept[sid] = stamp
    kept[session_id] = now.isoformat()
    tmp = None
    try:
        SEEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(
            dir=str(SEEN_PATH.parent), prefix=".clear-and-short-", suffix=".tmp"
        )
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(kept, fh)
        os.replace(tmp, SEEN_PATH)
        return True
    except Exception:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        return False


def _emit(directive: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": directive,
            }
        },
        sys.stdout,
    )


def _default_allowed(payload) -> bool:
    """True when the unasked-for VOICE default may fire for this payload.

    Two gates, both about the default only -- a prompt that matches a pattern is a real
    request and is honored whatever the source or the environment says.

    CLEAR_AND_SHORT_NO_DEFAULT set to any non-empty value turns the default off.

    CLAUDE_CODE_ENTRYPOINT is "cli" in an interactive terminal and "sdk-cli" under
    `claude -p` and SDK runs (Claude Code 2.1.251). Only "cli" gets the default; an ABSENT
    variable is treated as interactive so older versions keep working.

    "source", when the payload carries it, says who typed the prompt: "user", "sdk",
    "system" and others. Only "user" gets the default; an ABSENT source is treated as a
    user prompt. The `claude -p` payload on 2.1.251 has no "source" field, so this check
    alone let the default fire there -- the entrypoint check is the one that holds.
    """
    if os.environ.get("CLEAR_AND_SHORT_NO_DEFAULT"):
        return False
    entrypoint = os.environ.get("CLAUDE_CODE_ENTRYPOINT")
    if entrypoint is not None and entrypoint.strip().lower() != "cli":
        return False
    if "source" not in payload:
        return True
    source = payload.get("source")
    return isinstance(source, str) and source.strip().lower() == "user"


def _voice_default(payload) -> None:
    """Emit DIRECTIVE_VOICE once, on the first unmatched prompt of a session.

    A session id is required. Without one the hook cannot tell a first prompt from a
    fiftieth, so it would re-inject the directive on every turn -- a missing or non-string
    session_id therefore means stay quiet. Same for a seen-file that could not be written:
    an unrecorded session would fire again on the next prompt, which is the every-prompt
    behavior this default exists to avoid.
    """
    if not _default_allowed(payload):
        return
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id.strip():
        return
    if session_id in _load_seen():
        return
    if not _record_seen(session_id):
        return
    _emit(DIRECTIVE_VOICE)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return  # never block a prompt on a malformed payload
    if not isinstance(payload, dict):
        return
    prompt = payload.get("prompt") or ""
    if not isinstance(prompt, str) or not prompt.strip():
        return
    kind = classify(prompt)
    if not kind:
        # An off-switch asks for the mode OFF, so it emits nothing -- but it does record
        # the session, or the default would fire on the next prompt of the session the
        # user just asked to be quiet.
        if is_off_switch(prompt):
            session_id = payload.get("session_id")
            if isinstance(session_id, str) and session_id.strip():
                _record_seen(session_id)
            return
        _voice_default(payload)
        return
    # A matched prompt emits exactly what it always did, on any prompt of the session.
    _emit({
        "length": DIRECTIVE_LENGTH,
        "voice": DIRECTIVE_VOICE,
        "both": DIRECTIVE_BOTH,
    }[kind])
    # It also closes out the default, so the voice directive can never fire later in this
    # session and tell the model to drop length rules the user asked for a turn earlier.
    # Best-effort: the emit above already happened and must never depend on this write.
    session_id = payload.get("session_id")
    if isinstance(session_id, str) and session_id.strip():
        _record_seen(session_id)


if __name__ == "__main__":
    main()
