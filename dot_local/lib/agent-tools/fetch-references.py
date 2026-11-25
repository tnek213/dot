"""Download Markdown references with provenance and atomic replacement."""

import argparse
import datetime
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def fetch(url: str, destination: Path) -> None:
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("source URL must use HTTPS")
    request = urllib.request.Request(
        url, headers={"User-Agent": "agent-reference-fetcher/1.0"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        if urllib.parse.urlsplit(response.url).scheme != "https":
            raise ValueError("source redirected to a non-HTTPS URL")
        content_type = response.headers.get_content_type()
        if content_type not in {"text/markdown", "text/plain", "text/x-markdown"}:
            raise ValueError(
                f"expected Markdown or plain text, received {content_type}"
            )
        content = response.read().decode("utf-8")
    if not content.strip():
        raise ValueError("source returned empty content")
    retrieved = datetime.datetime.now(datetime.timezone.utc).isoformat(
        timespec="seconds"
    )
    content = f"<!-- Source: {url}\nRetrieved: {retrieved} -->\n\n{content}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=destination.parent, delete=False
        ) as output:
            temporary = Path(output.name)
            output.write(content)
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument(
        "--source", action="append", nargs=2, default=[], metavar=("URL", "PATH")
    )
    parser.add_argument(
        "--prune",
        action="store_true",
        help="delete unlisted files after all downloads succeed",
    )
    args = parser.parse_args()
    root = args.destination.resolve()
    expected = set()
    for _, filename in args.source:
        relative = Path(filename)
        target = root / relative
        if relative.is_absolute() or not relative.parts or ".." in relative.parts:
            parser.error("source paths must be relative paths without '..'")
        if not target.resolve().is_relative_to(root) or target.resolve() == root:
            parser.error("source paths must stay within the destination")
        if any(
            path.is_symlink()
            for path in [target, *target.parents]
            if path != root and path.is_relative_to(root)
        ):
            parser.error("source paths must not contain symlinks")
        if target in expected:
            parser.error(f"duplicate source path: {filename}")
        expected.add(target)
    failed = False
    for url, filename in args.source:
        destination = root / filename
        try:
            fetch(url, destination)
        except (OSError, ValueError, urllib.error.URLError) as error:
            print(f"Failed to fetch {url}: {error}", file=sys.stderr)
            failed = True
        else:
            print(destination)
    if args.prune and not failed and root.exists():
        try:
            for path in root.rglob("*"):
                if (path.is_file() or path.is_symlink()) and path not in expected:
                    path.unlink()
                    print(f"Removed {path}")
            for path in sorted(
                root.rglob("*"), key=lambda path: len(path.parts), reverse=True
            ):
                if path.is_dir() and not path.is_symlink() and not any(path.iterdir()):
                    path.rmdir()
        except OSError as error:
            print(f"Failed to prune {root}: {error}", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
