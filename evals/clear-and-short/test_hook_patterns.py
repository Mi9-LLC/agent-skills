import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location(
    "hook", os.path.join(os.path.dirname(__file__), "..", "..", "hooks", "clear-and-short-trigger.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

CASES = [
    # (prompt, expected kind)
    # --- the reported failure ---
    ("Humanize your responses and remove the AI tells.", "voice"),
    # --- voice, reply-directed ---
    ("humanize your replies please", "voice"),
    ("remove the AI tells", "voice"),
    ("your answers sound like ChatGPT", "voice"),
    ("stop writing like an AI", "voice"),
    ("stop sounding like a robot", "voice"),
    ("don't write like chatgpt", "voice"),
    ("de-AI your responses", "voice"),
    ("can you be less AI-sounding", "voice"),
    ("no more em dashes", "voice"),
    ("humanize your writing style", "voice"),
    # --- length, unchanged behaviour (regression) ---
    ("be brief", "length"),
    ("keep it short", "length"),
    ("from now on keep it short", "length"),
    ("too many words", "length"),
    ("shorter answers please", "length"),
    ("you are too verbose", "length"),
    ("stop repeating yourself", "length"),
    ("use fewer tokens", "length"),
    ("stop narrating every tool call", "length"),
    ("use simple English", "length"),
    ("plain English please", "length"),
    ("I am not a native speaker", "length"),
    # --- both ---
    ("be brief and stop sounding like an AI", "both"),
    ("shorter replies, and remove the AI tells", "both"),
    # --- hard negatives: a named document/code target goes to unslop or plain editing ---
    ("humanize this README", ""),
    ("remove the AI tells from the release notes", ""),
    ("de-AI the docs", ""),
    ("this blog post sounds like AI", ""),
    ("make src/app.ts shorter", ""),
    ("shorten this commit message", ""),
    ("unslop the PR description", ""),
    ("this paragraph reads like ChatGPT wrote it", ""),
    ("make the docstring less verbose", ""),
    # --- hard negatives: ordinary work ---
    ("why does the build fail", ""),
    ("add a test for the parser", ""),
    ("what does this function do", ""),
    ("humanity has used AI for years", ""),
]

fails = []
for prompt, expected in CASES:
    got = hook.classify(prompt)
    ok = got == expected
    if not ok:
        fails.append((prompt, expected, got))
    print("%-4s %-12s %-12s %s" % ("ok" if ok else "FAIL", expected or "-", got or "-", prompt))

# --- the unasked-for default: entrypoint and source gates ---
DEFAULT_CASES = [
    # (CLAUDE_CODE_ENTRYPOINT or None, payload, expected)
    (None, {}, True),                        # old version, no variable, no source
    ("cli", {}, True),                       # interactive terminal
    ("cli", {"source": "user"}, True),
    ("cli", {"source": "sdk"}, False),
    ("sdk-cli", {}, False),                  # claude -p on 2.1.251: no source field
    ("sdk-cli", {"source": "user"}, False),
    ("CLI", {}, True),
]
for entrypoint, payload, expected in DEFAULT_CASES:
    saved = os.environ.pop("CLAUDE_CODE_ENTRYPOINT", None)
    no_default = os.environ.pop("CLEAR_AND_SHORT_NO_DEFAULT", None)
    if entrypoint is not None:
        os.environ["CLAUDE_CODE_ENTRYPOINT"] = entrypoint
    got = hook._default_allowed(payload)
    os.environ.pop("CLAUDE_CODE_ENTRYPOINT", None)
    if saved is not None:
        os.environ["CLAUDE_CODE_ENTRYPOINT"] = saved
    if no_default is not None:
        os.environ["CLEAR_AND_SHORT_NO_DEFAULT"] = no_default
    ok = got == expected
    if not ok:
        fails.append(("default entrypoint=%r payload=%r" % (entrypoint, payload), expected, got))
    print("%-4s default entrypoint=%-9r payload=%r -> %r" % ("ok" if ok else "FAIL", entrypoint, payload, got))
CASES = CASES + DEFAULT_CASES

print()
print("%d/%d passed" % (len(CASES) - len(fails), len(CASES)))
for prompt, expected, got in fails:
    print("  FAIL: %r expected %r got %r" % (prompt, expected, got))
sys.exit(1 if fails else 0)
