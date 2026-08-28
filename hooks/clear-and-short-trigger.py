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
"""
import json
import re
import sys

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


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return  # never block a prompt on a malformed payload
    prompt = payload.get("prompt") or ""
    if not isinstance(prompt, str) or not prompt.strip():
        return
    kind = classify(prompt)
    if not kind:
        return
    directive = {
        "length": DIRECTIVE_LENGTH,
        "voice": DIRECTIVE_VOICE,
        "both": DIRECTIVE_BOTH,
    }[kind]
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": directive,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
