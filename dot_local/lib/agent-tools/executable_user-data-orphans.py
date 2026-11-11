#!/usr/bin/env python3
"""Report stored user data keys that no installed skill declares in user-data.json."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

KINDS = ("preference", "state")
PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
TIMEOUT = 60


class ProviderError(Exception):
    pass


def reject_constant(value):
    raise ValueError("Non-finite numbers are not valid JSON")


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle, parse_constant=reject_constant)


def resolve_helper(config_path):
    try:
        config = load_json(config_path)
    except FileNotFoundError:
        raise ProviderError(f"Configuration file not found: {config_path}")
    except (OSError, ValueError) as error:
        raise ProviderError(f"Cannot read configuration {config_path}: {error}")
    if not isinstance(config, dict):
        raise ProviderError(f"Configuration {config_path} is not a JSON object")
    helper = config.get("user_data_helper")
    if not isinstance(helper, str) or not helper:
        raise ProviderError(f"user_data_helper is missing in {config_path}")
    if helper.startswith("~/"):
        helper = str(Path.home() / helper[2:])
    elif not os.path.isabs(helper):
        raise ProviderError("user_data_helper must be absolute or start with ~/")
    if not (os.path.isfile(helper) and os.access(helper, os.X_OK)):
        raise ProviderError(f"User data helper is not an executable file: {helper}")
    return helper


def run_helper(helper, *args):
    try:
        result = subprocess.run(
            [helper, *args],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ProviderError(f"Cannot run {helper}: {error}")
    if result.returncode != 0:
        detail = result.stderr.strip() or "no diagnostic"
        raise ProviderError(
            f"{helper} {args[0]} failed with exit {result.returncode}: {detail}"
        )
    try:
        output = json.loads(result.stdout)
    except ValueError:
        raise ProviderError(f"{helper} {args[0]} wrote invalid JSON")
    if not isinstance(output, dict):
        raise ProviderError(f"{helper} {args[0]} wrote an unexpected result")
    return output


def read_store(helper):
    store = {}
    for kind in KINDS:
        output = run_helper(helper, "scopes", "--kind", kind)
        scopes = output.get("scopes")
        if not isinstance(scopes, list) or not all(isinstance(s, str) for s in scopes):
            raise ProviderError("The scopes command wrote an unexpected result")
        for scope in scopes:
            output = run_helper(helper, "list", "--scope", scope, "--kind", kind)
            values = output.get("values")
            if not isinstance(values, dict):
                raise ProviderError("The list command wrote an unexpected result")
            store[(scope, kind)] = sorted(values)
    return store


def pattern_regex(pattern):
    parts = PLACEHOLDER.split(pattern)
    return re.compile("[^.]+".join(re.escape(part) for part in parts))


def parse_declaration(document):
    if not isinstance(document, dict) or set(document) != {"keys"}:
        raise ValueError('The document must be an object with only "keys"')
    if not isinstance(document["keys"], list):
        raise ValueError('"keys" must be a list')
    entries = []
    for index, entry in enumerate(document["keys"]):
        where = f"keys[{index}]"
        if not isinstance(entry, dict):
            raise ValueError(f"{where} must be an object")
        fields = set(entry)
        if not {"scope", "kind"} <= fields or len(fields & {"key", "pattern"}) != 1:
            raise ValueError(f"{where} needs scope, kind and one of key or pattern")
        if fields - {"scope", "kind", "key", "pattern"}:
            raise ValueError(f"{where} has unknown fields")
        for field in fields:
            if not isinstance(entry[field], str) or not entry[field]:
                raise ValueError(f"{where}.{field} must be a non-empty string")
        if entry["kind"] not in KINDS:
            raise ValueError(f"{where}.kind must be preference or state")
        if "pattern" in entry:
            matcher = pattern_regex(entry["pattern"]).fullmatch
        else:
            matcher = entry["key"].__eq__
        entries.append((entry["scope"], entry["kind"], matcher))
    return entries


def read_declarations(skills_dirs):
    entries, invalid = [], []
    for directory in skills_dirs:
        for skill in sorted(Path(directory).iterdir()):
            path = skill / "user-data.json"
            if skill.is_symlink() or not skill.is_dir() or not path.is_file():
                continue
            try:
                entries.extend(parse_declaration(load_json(path)))
            except (OSError, ValueError) as error:
                invalid.append({"path": str(path), "error": str(error)})
    return entries, invalid


def compare(store, entries):
    declared_scopes = {scope for scope, _, _ in entries}
    report = {
        "unknown_scopes": [],
        "undeclared_keys": [],
        "kind_mismatch": [],
    }
    for (scope, kind), keys in sorted(store.items()):
        if scope not in declared_scopes:
            report["unknown_scopes"].append(
                {"scope": scope, "kind": kind, "keys": keys}
            )
            continue
        for key in keys:
            matches = {
                entry_kind
                for entry_scope, entry_kind, matcher in entries
                if entry_scope == scope and matcher(key)
            }
            if kind in matches:
                continue
            if matches:
                report["kind_mismatch"].append(
                    {
                        "scope": scope,
                        "kind": kind,
                        "key": key,
                        "declared_kind": sorted(matches)[0],
                    }
                )
            else:
                report["undeclared_keys"].append(
                    {"scope": scope, "kind": kind, "key": key}
                )
    return report


def default_skills_dirs():
    candidates = [Path.home() / ".claude/skills", Path.home() / ".agents/skills"]
    return [path for path in candidates if path.is_dir()]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".config/agent-tools/config.json",
        help="Bootstrap configuration naming user_data_helper",
    )
    parser.add_argument(
        "--skills-dir",
        action="append",
        type=Path,
        help="Directory of skills to read, repeatable",
    )
    args = parser.parse_args(argv)
    try:
        skills_dirs = args.skills_dir or default_skills_dirs()
        for directory in skills_dirs:
            if not directory.is_dir():
                raise ProviderError(f"Skills directory not found: {directory}")
        helper = resolve_helper(args.config)
        store = read_store(helper)
        entries, invalid = read_declarations(skills_dirs)
    except (ProviderError, OSError) as error:
        print(error, file=sys.stderr)
        return 2
    report = compare(store, entries)
    report["invalid_declarations"] = invalid
    json.dump(report, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 1 if any(report.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
