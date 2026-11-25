#!/usr/bin/env python3
"""User data provider that stores each scope as a JSON file in a private Seafile library."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path

STORE = Path.home() / "Seafile/AiUserData"
LOCK_DIRECTORY = Path.home() / ".local/state/agent-tools/user-data-locks"


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
        raise OSError(f"User data store is unavailable: {STORE}")
    if any("sfconflict" in path.name.lower() for path in STORE.iterdir()):
        raise ValueError("Seafile conflict copies exist in the user data store")


KINDS = ("preference", "state")


def scope_path(scope, kind="preference"):
    # The hash keeps scopes apart that differ only in case or filtered characters.
    digest = hashlib.sha256(scope.encode("utf-8")).hexdigest()[:12]
    name = re.sub(r"[^-a-z0-9]", "", scope.lower())
    stem = f"{name}.{digest}" if name else digest
    return STORE / (f"{stem}.json" if kind == "preference" else f"{stem}.{kind}.json")


def read_document(path):
    if path.is_symlink():
        raise ValueError("User data scope files must not be symlinks")
    data = parse_json(path.read_text(encoding="utf-8"))
    if (
        not isinstance(data, dict)
        or set(data) != {"scope", "values"}
        or not isinstance(data["scope"], str)
        or not isinstance(data["values"], dict)
        or any(not key for key in data["values"])
    ):
        raise ValueError("Invalid user data scope document")
    return data


def read_scope(scope, kind="preference"):
    path = scope_path(scope, kind)
    try:
        data = read_document(path)
    except FileNotFoundError:
        return {}
    if data["scope"] != scope:
        raise ValueError("Invalid user data scope document")
    return data["values"]


def list_scopes(kind):
    suffix = ".state.json" if kind == "state" else ".json"
    scopes = []
    for path in STORE.iterdir():
        if path.name.startswith(".pending-") or not path.name.endswith(suffix):
            continue
        if kind == "preference" and path.name.endswith(".state.json"):
            continue
        scope = read_document(path)["scope"]
        if scope_path(scope, kind) != path:
            raise ValueError(f"User data file does not match its scope: {path.name}")
        scopes.append(scope)
    return sorted(scopes)


def write_scope(scope, values, kind="preference"):
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
        os.replace(temporary, scope_path(scope, kind))
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
        if args.command == "scopes":
            return {"kind": args.kind, "scopes": list_scopes(args.kind)}, 0
        values = read_scope(args.scope, args.kind)
        result = {"scope": args.scope, "kind": args.kind}
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
            write_scope(args.scope, values, args.kind)
        elif args.command == "delete":
            result["deleted"] = args.key in values
            if result["deleted"]:
                del values[args.key]
                write_scope(args.scope, values, args.kind)
        return result, 0


def identifier(value):
    if not value:
        raise argparse.ArgumentTypeError("Identifiers must not be empty")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("get", "set", "list", "delete", "scopes"):
        command = commands.add_parser(name)
        command.add_argument("--kind", choices=KINDS, default="preference")
        if name == "scopes":
            continue
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
        print("User data operation failed: invalid JSON", file=sys.stderr)
        return 2
    except (OSError, ValueError, OverflowError, RecursionError) as error:
        print(f"User data operation failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
