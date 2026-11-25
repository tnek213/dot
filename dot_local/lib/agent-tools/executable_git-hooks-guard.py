#!/usr/bin/env python3
"""PreToolUse hook: agents never skip or disable git hooks.

Blocks `--no-verify` (and its abbreviations), `git commit -n`, and overriding
`core.hooksPath`. Kent runs such commands by hand when they are needed.
Works for Claude Code and Codex: the reason goes to stderr with exit code 2.
"""

import json
import re
import shlex
import sys

NO_VERIFY = re.compile(r"^--no-veri(f|fy)?$")
HOOKS_PATH = re.compile(r"core\.hookspath", re.I)
## short options of `git commit` that take a value, so `-m n` is not `-n`
COMMIT_VALUE_FLAGS = set("mFcCt")
GLOBAL_VALUE_OPTIONS = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--config-env",
}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n"}


def segments(command: str) -> list[list[str]]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    parts: list[list[str]] = [[]]
    for token in lexer:
        if token in SEPARATORS or set(token) <= set(";&|()\n"):
            parts.append([])
        else:
            parts[-1].append(token)
    return [part for part in parts if part]


def commit_skips_hooks(args: list[str]) -> bool:
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg == "--":
            return False
        if not arg.startswith("-") or arg.startswith("--") or arg == "-":
            continue
        for index, letter in enumerate(arg[1:]):
            if letter == "n":
                return True
            if letter in COMMIT_VALUE_FLAGS:
                skip_next = index == len(arg) - 2
                break
    return False


def git_bypass(tokens: list[str]) -> str | None:
    words = [token.rsplit("/", 1)[-1] for token in tokens]
    if "git" not in words:
        return None
    rest = tokens[words.index("git") + 1 :]
    if any(NO_VERIFY.match(token) for token in rest):
        return "--no-verify skips git hooks"
    position = 0
    while position < len(rest) and rest[position].startswith("-"):
        position += 2 if rest[position] in GLOBAL_VALUE_OPTIONS else 1
    subcommand = rest[position] if position < len(rest) else ""
    if subcommand == "commit":
        if commit_skips_hooks(rest[position + 1 :]):
            return "`git commit -n` skips git hooks"
    if any(HOOKS_PATH.search(token) for token in rest):
        if subcommand != "config" or not {"--get", "--list", "-l"} & set(rest):
            return "changing core.hooksPath disables git hooks"
    return None


def reason(command: str) -> str | None:
    if HOOKS_PATH.search(command) and re.search(
        r"GIT_CONFIG_(PARAMETERS|VALUE)", command
    ):
        return "overriding core.hooksPath through the environment disables git hooks"
    try:
        parts = segments(command)
    except ValueError:
        parts = [command.split()]
    for tokens in parts:
        found = git_bypass(tokens)
        if found:
            return found
    return None


def main() -> None:
    event = json.load(sys.stdin)
    if event.get("tool_name") not in {"Bash", "shell", "exec_command"}:
        sys.exit(0)
    tool_input = event.get("tool_input") or {}
    command = tool_input.get("command") or tool_input.get("cmd") or ""
    if isinstance(command, list):
        command = shlex.join(command)
    found = reason(command)
    if found:
        print(
            f"Blocked: {found}. Agents must never bypass git hooks. Fix what the hook "
            "reports, or stop and tell Kent, who runs the command by hand if it is "
            "really needed.",
            file=sys.stderr,
        )
        sys.exit(2)


main()
