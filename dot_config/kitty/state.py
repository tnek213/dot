from dataclasses import dataclass, field
from time import monotonic
from typing import Iterable


@dataclass
class TabInfo:
    tab_id: int = 0
    kind: str = "title"
    value: str = ""
    created_at: float = field(default_factory=monotonic)
    last_focus: float = field(default_factory=monotonic)
    program_cmd: str | None = None
    program_started_at: float = 0.0
    program_timer_id: int | None = None
    last_cwd: str = ""
    first_render_done: bool = False
    pending_cwd: str = ""
    pending_cwd_at: float = 0.0
    shell_integration_works: bool = True
    alert_kind: str | None = None
    alert_started_at: float = 0.0
    alert_focused_at: float = 0.0
    alert_timer_ids: list[int] = field(default_factory=list)
    last_fg: int = -1
    last_bg: int = -1


_info: dict[int, TabInfo] = {}


def of(tab_id: int) -> TabInfo:
    info = _info.get(tab_id)
    if info is None:
        info = TabInfo(tab_id=tab_id)
        _info[tab_id] = info
    return info


def gc(live_ids: Iterable[int]) -> None:
    live = set(live_ids)
    for tab_id in list(_info):
        if tab_id not in live:
            del _info[tab_id]
