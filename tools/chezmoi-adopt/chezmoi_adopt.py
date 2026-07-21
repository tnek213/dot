#!/usr/bin/env python3
"""chezmoi-adopt — keep declared directory trees fully tracked by chezmoi.

See SPEC.md for the full specification. This tool operates on target paths
under $HOME (like chezmoi) and shells out to chezmoi / chezmoi-cryptpath.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys
from pathlib import Path

import tomlkit

ENCRYPTIONS = ("none", "content", "all")
CONFIG_ENV = "CHEZMOI_ADOPT_CONFIG"


def default_config() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "chezmoi-adopt.toml"


def config_path() -> Path:
    return Path(os.environ[CONFIG_ENV]) if os.environ.get(CONFIG_ENV) else default_config()


def die(msg: str, code: int = 1):
    print(f"chezmoi-adopt: {msg}", file=sys.stderr)
    sys.exit(code)


# --------------------------------------------------------------------------
# path helpers
# --------------------------------------------------------------------------

def expand(p) -> Path:
    return Path(os.path.abspath(os.path.expanduser(str(p))))


def to_config_str(abs_path: Path) -> str:
    """Store paths under $HOME as ~/… so the (synced) config stays portable."""
    try:
        return "~/" + abs_path.relative_to(Path.home()).as_posix()
    except ValueError:
        return str(abs_path)


def is_under(child: Path, parent: Path) -> bool:
    return parent in child.parents


def depth_under(child: Path, root: Path) -> int:
    return len(child.relative_to(root).parts)


# --------------------------------------------------------------------------
# chezmoi interface
# --------------------------------------------------------------------------

def run(cmd, check=True, capture=False) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


def have(prog: str) -> bool:
    from shutil import which
    return which(prog) is not None


def cm_ignored() -> set[Path]:
    """Absolute target paths ignored by chezmoi (.chezmoiignore). `chezmoi
    ignored` prints paths relative to the destination dir ($HOME)."""
    r = run(["chezmoi", "ignored"], check=False, capture=True)
    home = Path.home()
    return {home / line.strip() for line in r.stdout.splitlines() if line.strip()}


def cm_managed(include: str = "files") -> set[Path]:
    r = run(["chezmoi", "managed", f"--include={include}", "--path-style=absolute"],
            check=False, capture=True)
    return {Path(line) for line in r.stdout.splitlines() if line.strip()}


def cm_add(path: Path, encryption: str):
    if encryption == "none":
        run(["chezmoi", "add", str(path)])
    elif encryption == "content":
        run(["chezmoi", "add", "--encrypt", str(path)])
    elif encryption == "all":
        run(["chezmoi-cryptpath", "to-encrypted-path", str(path)])
    else:
        die(f"unknown encryption: {encryption}")


def cm_forget(path: Path, encryption: str = "none"):
    if encryption == "all":
        run(["chezmoi-cryptpath", "forget", str(path)], check=False, capture=True)
    else:
        run(["chezmoi", "forget", "--force", str(path)], check=False)


# --------------------------------------------------------------------------
# config (TOML)
# --------------------------------------------------------------------------

class Config:
    def __init__(self, doc, path: Path):
        self.doc = doc
        self.path = path

    @classmethod
    def load(cls) -> "Config":
        path = config_path()
        if path.exists():
            doc = tomlkit.parse(path.read_text())
        else:
            doc = tomlkit.document()
        return cls(doc, path)

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(tomlkit.dumps(self.doc))
        # Keep the chezmoi source in sync — only for the real (default) config.
        if self.path == default_config() and have("chezmoi"):
            run(["chezmoi", "add", str(self.path)], check=False, capture=True)

    def global_ignore(self) -> list[str]:
        return list(self.doc.get("ignore", []))

    def set_global_ignore(self, patterns: list[str]):
        if patterns:
            self.doc["ignore"] = patterns
        elif "ignore" in self.doc:
            del self.doc["ignore"]

    def roots(self) -> list[dict]:
        """Return roots as plain dicts with an added 'abs' Path, deepest last."""
        out = []
        for t in self.doc.get("root", []):
            out.append({
                "path": str(t["path"]),
                "encryption": str(t.get("encryption", "none")),
                "levels": int(t.get("levels", 0)),
                "ignore": list(t.get("ignore", [])),
                "abs": expand(t["path"]),
                "_t": t,
            })
        out.sort(key=lambda r: len(r["abs"].parts))
        return out

    def find_root(self, abs_path: Path):
        for r in self.roots():
            if r["abs"] == abs_path:
                return r
        return None

    def upsert_root(self, abs_path: Path, encryption: str, levels: int):
        aot = self.doc.get("root")
        if aot is None:
            aot = tomlkit.aot()
            self.doc["root"] = aot
        for t in aot:
            if expand(t["path"]) == abs_path:
                t["encryption"] = encryption
                t["levels"] = levels
                return
        t = tomlkit.table()
        t["path"] = to_config_str(abs_path)
        t["encryption"] = encryption
        t["levels"] = levels
        aot.append(t)

    def remove_root(self, abs_path: Path) -> bool:
        aot = self.doc.get("root")
        if aot is None:
            return False
        for i, t in enumerate(list(aot)):
            if expand(t["path"]) == abs_path:
                del aot[i]
                return True
        return False

    def add_ignore(self, pattern: str, dirs: list[Path]):
        if not dirs:
            pats = self.global_ignore()
            if pattern not in pats:
                pats.append(pattern)
            self.set_global_ignore(pats)
            return
        for t in self.doc.get("root", []):
            if expand(t["path"]) in dirs:
                pats = list(t.get("ignore", []))
                if pattern not in pats:
                    pats.append(pattern)
                t["ignore"] = pats

    def remove_ignore(self, pattern: str, dirs: list[Path]):
        if not dirs:
            self.set_global_ignore([p for p in self.global_ignore() if p != pattern])
            return
        for t in self.doc.get("root", []):
            if expand(t["path"]) in dirs and "ignore" in t:
                t["ignore"] = [p for p in list(t["ignore"]) if p != pattern]


# --------------------------------------------------------------------------
# adoption logic
# --------------------------------------------------------------------------

def governing_root(f: Path, roots: list[dict]):
    """Deepest root that is an ancestor of (or equals) f, else None."""
    best = None
    for r in roots:
        rabs = r["abs"]
        if f == rabs or is_under(f, rabs):
            if best is None or len(rabs.parts) > len(best["abs"].parts):
                best = r
    return best


def ignored(rel: str, name: str, patterns: list[str]) -> bool:
    for pat in patterns:
        if fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch(name, pat):
            return True
    return False


def candidates_for(roots: list[dict], global_ig: list[str]) -> list[tuple[Path, dict]]:
    """(file, governing_root) for every unmanaged, in-scope, non-ignored file.

    Walks each root's filesystem (chezmoi's `unmanaged` only reports the
    unmanaged frontier, not files inside a wholly-unmanaged dir) and filters
    against chezmoi's managed + ignored sets and the tool's own patterns.
    """
    managed = cm_managed()
    chezmoi_ignored = cm_ignored()
    seen: set[Path] = set()
    out: list[tuple[Path, dict]] = []
    for r in roots:
        if not r["abs"].is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(r["abs"]):
            dirnames.sort()
            dabs = Path(dirpath)
            for fn in sorted(filenames):
                f = dabs / fn
                if f in seen or f in managed or f in chezmoi_ignored:
                    continue
                gr = governing_root(f, roots)
                if gr is None:
                    continue
                if gr["levels"] and depth_under(f, gr["abs"]) > gr["levels"]:
                    continue
                rel = f.relative_to(gr["abs"]).as_posix()
                if ignored(rel, f.name, global_ig + gr["ignore"]):
                    continue
                seen.add(f)
                out.append((f, gr))
    return out


def frontier(cands: list[tuple[Path, dict]], managed: set[Path]) -> list[dict]:
    """Collapse brand-new directories (no managed files inside) into dir items."""
    managed_dirs: set[Path] = set()
    for m in managed:
        managed_dirs.update(m.parents)

    def is_new_dir(d: Path) -> bool:
        return d not in managed_dirs

    items: list[dict] = []
    handled: set[Path] = set()
    cand_files = {f for f, _ in cands}
    gr_of = {f: gr for f, gr in cands}

    for f, gr in sorted(cands, key=lambda c: str(c[0])):
        if f in handled:
            continue
        # highest new-dir ancestor strictly below the governing root
        top = None
        for anc in f.parents:
            if anc == gr["abs"]:
                break
            if not is_under(anc, gr["abs"]):
                break
            if is_new_dir(anc):
                top = anc
        if top is not None:
            items.append({"kind": "dir", "path": top, "root": gr,
                          "files": [g for g in cand_files if g == top or is_under(g, top)]})
            for g in list(cand_files):
                if g == top or is_under(g, top):
                    handled.add(g)
        else:
            items.append({"kind": "file", "path": f, "root": gr, "files": [f]})
            handled.add(f)
    return items


def rel_to_root(path: Path, root: dict) -> str:
    return path.relative_to(root["abs"]).as_posix()


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def cmd_add(args):
    for d in args.dirs:
        if not expand(d).is_dir():
            die(f"not a directory: {d}", 2)
    cfg = Config.load()
    for d in args.dirs:
        cfg.upsert_root(expand(d), args.encryption, args.levels)
    cfg.save()
    # adopt current files immediately for the just-added roots
    roots = cfg.roots()
    targets = {expand(d) for d in args.dirs}
    cands = [(f, gr) for f, gr in candidates_for(roots, cfg.global_ignore())
             if gr["abs"] in targets]
    _apply(frontier(cands, cm_managed()), dry=False)


def cmd_remove(args):
    cfg = Config.load()
    roots = cfg.roots()
    managed = cm_managed()
    changed = False
    for p in args.paths:
        pabs = expand(p)
        root = cfg.find_root(pabs)
        if root:
            files_set = cm_managed("files")
            under = [m for m in cm_managed("files,dirs")
                     if m == pabs or is_under(m, pabs)]
            for m in sorted(under, key=lambda x: len(x.parts), reverse=True):
                cm_forget(m, root["encryption"] if m in files_set else "none")
            cfg.remove_root(pabs)
            changed = True
            print(f"removed root and forgot its files: {p}")
            continue
        owning = governing_root(pabs, roots)
        if pabs.is_dir() and owning:
            die(f"{p} is inside adopted root {owning['path']}; "
                f"remove that root instead", 2)
        if pabs in managed:
            gr = governing_root(pabs, roots)
            cm_forget(pabs, gr["encryption"] if gr else "none")
            print(f"forgot: {p}")
        else:
            die(f"{p} is neither a managed file nor a registered root", 2)
    if changed:
        cfg.save()


def cmd_list(args):
    cfg = Config.load()
    roots = cfg.roots()
    managed = cm_managed()

    def show_root(r):
        print(f"[root] {r['encryption']:7} levels={r['levels']} {r['path']}")

    if not args.patterns:
        if not roots:
            print("no adopted roots")
        for r in roots:
            show_root(r)
        return

    for pat in args.patterns:
        pabs = expand(pat)
        if pabs.is_dir():
            for r in roots:
                if r["abs"] == pabs or is_under(r["abs"], pabs):
                    show_root(r)
            continue
        for m in sorted(managed):
            if fnmatch.fnmatch(m.name, pat) or fnmatch.fnmatch(str(m), pat):
                print(m)
        for r in roots:
            if fnmatch.fnmatch(r["abs"].name, pat) or fnmatch.fnmatch(str(r["abs"]), pat):
                show_root(r)


def cmd_ignore(args):
    cfg = Config.load()
    dirs = [expand(d) for d in args.dirs]
    if args.action == "list":
        if not dirs:
            g = cfg.global_ignore()
            if g:
                print("[global]")
                for p in g:
                    print(f"  {p}")
            for r in cfg.roots():
                if r["ignore"]:
                    print(f"[{r['path']}]")
                    for p in r["ignore"]:
                        print(f"  {p}")
        else:
            for r in cfg.roots():
                if r["abs"] in dirs and r["ignore"]:
                    print(f"[{r['path']}]")
                    for p in r["ignore"]:
                        print(f"  {p}")
        return
    if args.action == "add":
        cfg.add_ignore(args.pattern, dirs)
    elif args.action == "remove":
        cfg.remove_ignore(args.pattern, dirs)
    cfg.save()


def cmd_reconcile(args):
    cfg = Config.load()
    roots = cfg.roots()
    if not roots:
        print("no adopted roots; use `chezmoi-adopt add` first")
        return
    cands = candidates_for(roots, cfg.global_ignore())
    items = frontier(cands, cm_managed())
    if not items:
        print("nothing to adopt")
        return

    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    if interactive:
        _reconcile_interactive(cfg, items)
    elif args.force:
        _apply(items, dry=False)
    else:
        print("# dry audit — would adopt (run with --force, or interactively):")
        _apply(items, dry=True)


def _apply(items: list[dict], dry: bool):
    for it in items:
        enc = it["root"]["encryption"]
        label = f"{it['kind']:4} [{enc}] {it['path']}"
        if dry:
            print(f"  {label}")
            continue
        print(f"adopt {label}")
        for f in sorted(it["files"]):
            cm_add(f, enc)


def _reconcile_interactive(cfg: Config, items: list[dict]):
    try:
        import readline  # enables prefill for the pattern editor
    except ImportError:
        readline = None

    dirty = False
    for it in items:
        root = it["root"]
        rel = rel_to_root(it["path"], root)
        while True:
            ans = input(f"{it['kind']} {it['path']} [{root['encryption']}]  "
                        f"[A]dd / [I]gnore / i[G]nore-pattern / [s]kip / [q]uit ? ").strip().lower()
            if ans in ("a", ""):
                _apply([it], dry=False)
                break
            if ans == "s":
                break
            if ans == "q":
                if dirty:
                    cfg.save()
                return
            if ans == "i":
                pat = rel + "/*" if it["kind"] == "dir" else rel
                cfg.add_ignore(pat, [root["abs"]])
                dirty = True
                print(f"  ignored: {pat} (in {root['path']})")
                break
            if ans == "g":
                default = (rel + "/*") if it["kind"] == "dir" else rel
                if readline:
                    readline.set_startup_hook(lambda: readline.insert_text(default))
                try:
                    pat = input("  pattern: ").strip()
                finally:
                    if readline:
                        readline.set_startup_hook()
                if not pat:
                    continue
                if not (fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch(it["path"].name, pat)):
                    print(f"  error: pattern {pat!r} does not match {rel!r}")
                    continue
                cfg.add_ignore(pat, [root["abs"]])
                dirty = True
                print(f"  ignored: {pat} (in {root['path']})")
                break
    if dirty:
        cfg.save()


# --------------------------------------------------------------------------
# argument parsing
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="chezmoi-adopt",
        description="Keep declared directory trees fully tracked by chezmoi.")
    p.add_argument("--force", action="store_true",
                   help="non-interactive reconcile: adopt everything not ignored")
    sub = p.add_subparsers(dest="command")

    pa = sub.add_parser("add", help="register directories as adopted roots")
    pa.add_argument("encryption", choices=ENCRYPTIONS)
    pa.add_argument("--levels", type=int, default=0,
                    help="descent depth (0 = unlimited)")
    pa.add_argument("dirs", nargs="+", metavar="DIR")
    pa.set_defaults(func=cmd_add)

    pr = sub.add_parser("remove", help="un-adopt a root (and forget its files) or forget a file")
    pr.add_argument("paths", nargs="+", metavar="PATH")
    pr.set_defaults(func=cmd_remove)

    pl = sub.add_parser("list", help="list adopted roots / managed files")
    pl.add_argument("patterns", nargs="*", metavar="PATTERN")
    pl.set_defaults(func=cmd_list)

    pi = sub.add_parser("ignore", help="manage ignore patterns")
    isub = pi.add_subparsers(dest="action", required=True)
    il = isub.add_parser("list")
    il.add_argument("dirs", nargs="*", metavar="DIR")
    ia = isub.add_parser("add")
    ia.add_argument("pattern", metavar="PATTERN")
    ia.add_argument("dirs", nargs="*", metavar="DIR")
    ir = isub.add_parser("remove")
    ir.add_argument("pattern", metavar="PATTERN")
    ir.add_argument("dirs", nargs="*", metavar="DIR")
    pi.set_defaults(func=cmd_ignore)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    if not have("chezmoi"):
        die("chezmoi not found on PATH")
    if getattr(args, "command", None) is None:
        cmd_reconcile(args)
    else:
        args.func(args)


if __name__ == "__main__":
    main()
