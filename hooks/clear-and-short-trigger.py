#!/usr/bin/env python3
"""UserPromptSubmit hook: detect a request for shorter/simpler CHAT replies and
tell Claude to load the clear-and-short skill so the change persists.

Deliberately narrow. The model already shortens a single reply on its own; what it
reliably fails to do is load the skill, which is what makes the mode hold for the
session. Patterns therefore target reply-directed mode switches only -- never a
request to shorten a file, code, or prose written for other readers (that is
unslop's job, or plain editing).

STRONG patterns are unambiguously about Claude's own replies and fire on their own.
WEAK patterns ("too verbose", "too many words") are ambiguous -- they read the same
way aimed at a function or a PR description -- so they fire only when the prompt
names no code/document target.
"""
import json
import re
import sys

STRONG = [
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

WEAK = [
    r"\btoo verbose\b",
    r"\btoo many words\b",
    r"\bless verbose\b",
]

# A named code/document target means a WEAK match is about that thing, not the reply.
TARGET = (
    r"\b(function|method|class|variable|docstring|comment|paragraph|sentence|"
    r"readme|changelog|release notes?|commit message|pull request|pr description|"
    r"docs?|documentation|blog|post|article|ticket|issue|log|file|script|test)\b"
    r"|\.(md|ts|tsx|js|jsx|py|cs|java|go|rs|json|ya?ml|txt)\b"
    r"|[\w./-]+/[\w./-]+"
)

STRONG_RX = [re.compile(p, re.I) for p in STRONG]
WEAK_RX = [re.compile(p, re.I) for p in WEAK]
TARGET_RX = re.compile(TARGET, re.I)

DIRECTIVE = (
    "The user is asking for shorter, simpler, or less repetitive chat replies. "
    "Invoke the clear-and-short skill now (Skill tool, skill: \"clear-and-short\") "
    "BEFORE answering the rest of this message, then answer under it. Answering "
    "shorter just this once is not enough: loading the skill is what makes the "
    "change hold for the rest of the session and what protects the detail that "
    "must never be cut. This applies to chat replies only -- do not shorten code, "
    "comments, commit messages, documentation, or prose written for other readers."
)


def matches(prompt: str) -> bool:
    """True when the prompt asks for shorter/simpler chat replies."""
    if any(rx.search(prompt) for rx in STRONG_RX):
        return True
    if any(rx.search(prompt) for rx in WEAK_RX):
        return not TARGET_RX.search(prompt)
    return False


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return  # never block a prompt on a malformed payload
    prompt = payload.get("prompt") or ""
    if not isinstance(prompt, str) or not prompt.strip():
        return
    if not matches(prompt):
        return
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": DIRECTIVE,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
