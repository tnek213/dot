#!/usr/bin/env python3
"""Run explicitly supplied reviewer profiles without shell interpolation."""

import argparse
import json
import math
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key in reviewer profiles")
        result[key] = value
    return result


def validate(profiles):
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError("profiles must be a nonempty object")
    for name, profile in profiles.items():
        if not isinstance(name, str) or not name or not isinstance(profile, dict):
            raise ValueError("each profile needs a name and an object")
        argv = profile.get("argv")
        mode = profile.get("prompt_input")
        timeout = profile.get("timeout_seconds")
        if (
            not isinstance(argv, list)
            or not argv
            or any(not isinstance(arg, str) or "\0" in arg for arg in argv)
            or not argv[0]
        ):
            raise ValueError("argv must be a nonempty string array")
        if "/" in argv[0] and not Path(argv[0]).is_absolute():
            raise ValueError("reviewer executable paths must be absolute")
        if mode not in ("stdin", "argument"):
            raise ValueError("prompt_input must be stdin or argument")
        if mode == "argument" and not any("$prompt" in arg for arg in argv[1:]):
            raise ValueError("argument profiles need $prompt after the executable")
        if "$prompt" in argv[0] or (
            mode == "stdin" and any("$prompt" in arg for arg in argv)
        ):
            raise ValueError("invalid $prompt placement")
        try:
            valid_timeout = (
                not isinstance(timeout, bool)
                and isinstance(timeout, (int, float))
                and math.isfinite(timeout)
                and timeout > 0
            )
        except OverflowError:
            valid_timeout = False
        if not valid_timeout:
            raise ValueError("timeout_seconds must be finite and positive")


def run(profiles, prompt, cwd, output):
    validate(profiles)
    if os.name != "posix":
        raise ValueError("reviewer process-group cleanup requires POSIX")
    if not cwd.is_dir():
        raise ValueError("review snapshot directory does not exist")
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    results = []
    for index, (name, profile) in enumerate(profiles.items(), 1):
        argv = [arg.replace("$prompt", prompt) for arg in profile["argv"]]
        status = "failed"
        code = None
        stdout_path = output / f"{index}.stdout.txt"
        stderr_path = output / f"{index}.stderr.txt"
        with (
            tempfile.TemporaryFile() as prompt_stream,
            stdout_path.open("wb") as stdout_stream,
            stderr_path.open("wb") as stderr_stream,
        ):
            if profile["prompt_input"] == "stdin":
                prompt_stream.write(prompt.encode("utf-8"))
                prompt_stream.seek(0)
            try:
                if not Path(argv[0]).is_absolute():
                    search_path = os.pathsep.join(
                        p
                        for p in os.get_exec_path()
                        if Path(p).is_absolute()
                        and not Path(p).resolve().is_relative_to(cwd.resolve())
                    )
                    executable = shutil.which(argv[0], path=search_path)
                    if not executable:
                        raise OSError(
                            f"Reviewer executable {argv[0]!r} not found on absolute PATH entries"
                        )
                    argv[0] = executable
                if Path(argv[0]).resolve().is_relative_to(cwd.resolve()):
                    raise OSError(
                        f"Reviewer executable {argv[0]!r} resolves inside the reviewed snapshot"
                    )
                with subprocess.Popen(
                    argv,
                    stdin=prompt_stream
                    if profile["prompt_input"] == "stdin"
                    else subprocess.DEVNULL,
                    cwd=cwd,
                    stdout=stdout_stream,
                    stderr=stderr_stream,
                    start_new_session=True,
                ) as process:
                    try:
                        code = process.wait(timeout=profile["timeout_seconds"])
                        status = "completed" if code == 0 else "failed"
                    except subprocess.TimeoutExpired:
                        status = "timeout"
                    finally:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait()
            except (OSError, ValueError) as error:
                stderr_stream.write(str(error).encode("utf-8", errors="replace"))
                status = "unavailable"
        try:
            for path in (stdout_path, stderr_path):
                with path.open(encoding="utf-8") as stream:
                    while stream.read(65536):
                        pass
        except UnicodeDecodeError:
            if status == "completed":
                status = "failed"
            with stderr_path.open("ab") as stream:
                stream.write(
                    b"\nReviewer output contains invalid UTF-8; raw bytes preserved.\n"
                )
        results.append(
            {
                "name": name,
                "status": status,
                "exit_code": code,
                "output_prefix": str(index),
            }
        )
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return all(result["status"] == "completed" for result in results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--profiles",
        type=Path,
        required=True,
        help="JSON object containing only selected profiles",
    )
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--cwd", type=Path, required=True)
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="new private directory outside the skill",
    )
    args = parser.parse_args()
    try:
        return (
            0
            if run(
                json.loads(
                    args.profiles.read_text(encoding="utf-8"),
                    object_pairs_hook=unique_object,
                ),
                args.prompt_file.read_text(encoding="utf-8"),
                args.cwd,
                args.output_dir,
            )
            else 1
        )
    except (OSError, ValueError) as error:
        print(f"Reviewer setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
