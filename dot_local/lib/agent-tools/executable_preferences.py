#!/usr/bin/env python3
"""Store scoped preferences in private Seafile-synchronized JSON files."""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

STORE = Path.home() / "Seafile/AiPreferences"
LOCK_DIRECTORY = Path.home() / ".local/state/agent-tools/preference-locks"


def reject_constant(value):
    raise ValueError("Non-finite numbers are not valid JSON")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object keys")
        result[key] = value
    return result


def parse_json(content):
    value = json.loads(
        content, parse_constant=reject_constant, object_pairs_hook=unique_object
    )
    json.dumps(value, allow_nan=False)
    return value


def check_store():
    if not STORE.is_dir():
        raise OSError(f"Preference store is unavailable: {STORE}")
    if any("sfconflict" in path.name.lower() for path in STORE.iterdir()):
        raise ValueError("Seafile conflict copies exist in the preference store")


def scope_path(scope):
    digest = hashlib.sha256(scope.encode("utf-8")).hexdigest()
    return STORE / f"{digest}.json"


def read_scope(scope):
    path = scope_path(scope)
    if path.is_symlink():
        raise ValueError("Preference scope files must not be symlinks")
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    data = parse_json(content)
    if (
        not isinstance(data, dict)
        or set(data) != {"scope", "values"}
        or data["scope"] != scope
        or not isinstance(data["values"], dict)
        or any(not key for key in data["values"])
    ):
        raise ValueError("Invalid preference scope document")
    return data["values"]


def write_scope(scope, values):
    content = (
        json.dumps(
            {"scope": scope, "values": values},
            ensure_ascii=False,
            allow_nan=False,
            indent=2,
        )
        + "\n"
    )
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=STORE, prefix=".pending-", delete=False
        ) as output:
            temporary = Path(output.name)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        check_store()
        os.replace(temporary, scope_path(scope))
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def execute(args):
    check_store()
    LOCK_DIRECTORY.mkdir(parents=True, exist_ok=True, mode=0o700)
    store_id = hashlib.sha256(str(STORE.resolve()).encode("utf-8")).hexdigest()
    descriptor = os.open(
        LOCK_DIRECTORY / f"{store_id}.lock", os.O_CREAT | os.O_RDWR, 0o600
    )
    with os.fdopen(descriptor, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        check_store()
        values = read_scope(args.scope)
        result = {"scope": args.scope}
        if args.command == "list":
            result["values"] = values
            return result, 0
        result["key"] = args.key
        if args.command == "get":
            if args.key not in values:
                result["missing"] = True
                return result, 1
            result["value"] = values[args.key]
        elif args.command == "set":
            values[args.key] = args.value
            write_scope(args.scope, values)
        elif args.command == "delete":
            result["deleted"] = args.key in values
            if result["deleted"]:
                del values[args.key]
                write_scope(args.scope, values)
        return result, 0


def identifier(value):
    if not value:
        raise argparse.ArgumentTypeError("Identifiers must not be empty")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("get", "set", "list", "delete"):
        command = commands.add_parser(name)
        command.add_argument("--scope", required=True, type=identifier)
        if name != "list":
            command.add_argument("--key", required=True, type=identifier)
        if name == "set":
            command.add_argument("--value-json", required=True)
    args = parser.parse_args()
    try:
        if args.command == "set":
            args.value = parse_json(args.value_json)
        result, status = execute(args)
    except json.JSONDecodeError:
        print("Preference operation failed: invalid JSON", file=sys.stderr)
        return 2
    except (OSError, ValueError, OverflowError, RecursionError) as error:
        print(f"Preference operation failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
