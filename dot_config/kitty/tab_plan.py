from os import sep
from os.path import expanduser

import state

DROPPED_LETTERS = set("aeiouåäöAEIOUÅÄÖ")
COMPRESSIBLE_KINDS = {"cwd", "program"}
HOME = expanduser("~")

_plan: dict[int, str] = {}


def _shorten_cwd(path: str) -> str:
    if path == HOME:
        return "~"
    if path.startswith(HOME + sep):
        return "~" + path[len(HOME):]
    return path


def _drop_letters(word: str, keep: int = 8) -> str:
    if len(word) <= keep:
        return word
    return word[0] + "".join(c for c in word[1:] if c not in DROPPED_LETTERS)


def _compress(title: str) -> str:
    return "/".join(_drop_letters(p) for p in title.split("/"))


def _label(info) -> str:
    if info.kind == "cwd":
        return _shorten_cwd(info.value)
    return info.value


def rebuild(columns: int, gap: int, tab_ids: list[int]) -> None:
    _plan.clear()

    states = []
    for tab_id in tab_ids:
        info = state.of(tab_id)
        states.append(
            {
                "id": tab_id,
                "raw": _label(info),
                "compressible": info.kind in COMPRESSIBLE_KINDS,
                "compressed": False,
            }
        )

    def render(s):
        body = _compress(s["raw"]) if s["compressed"] else s["raw"]
        return f" {body} "

    def total():
        return sum(len(render(s)) for s in states) + max(0, len(states) - 1) * gap

    while total() > columns:
        candidates = [s for s in states if s["compressible"] and not s["compressed"]]
        if not candidates:
            break
        max(candidates, key=lambda s: len(render(s)))["compressed"] = True

    for s in states:
        _plan[s["id"]] = render(s)


def title_for(tab_id: int, fallback: str) -> str:
    return _plan.get(tab_id, fallback)
