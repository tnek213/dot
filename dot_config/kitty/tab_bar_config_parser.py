CONFIG_ERRORS: list[str] = []
_LOG_LEVELS = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
_MISSING = object()

try:
    import tab_bar_config as _user
except Exception as e:
    CONFIG_ERRORS.append(f"failed to import tab_bar_config.py: {e!r}")
    _user = None


def _hex_color(s: str) -> int:
    return int(s.lstrip("#"), 16)


def _v_hex(s):
    try:
        n = _hex_color(s)
    except ValueError:
        return f"not a valid hex color: {s!r}"
    if not 0 <= n <= 0xFFFFFF:
        return f"hex color out of range: {s!r}"
    return None


def _v_hex_or_empty(s):
    if s == "":
        return None
    return _v_hex(s)


def _v_nonneg(v):
    return None if v >= 0 else f"must be >= 0, got {v!r}"


def _v_log_level(s):
    if s == "" or s.upper() in _LOG_LEVELS:
        return None
    return f"must be one of {'/'.join(_LOG_LEVELS)} or empty, got {s!r}"


def _get(name, expected_type, default, validator=None):
    if _user is None:
        return default
    val = getattr(_user, name, _MISSING)
    if val is _MISSING:
        CONFIG_ERRORS.append(f"{name}: missing (using default {default!r})")
        return default
    if not isinstance(val, expected_type):
        want = getattr(expected_type, "__name__", str(expected_type))
        CONFIG_ERRORS.append(
            f"{name}: expected {want}, got {type(val).__name__} {val!r} (using default {default!r})"
        )
        return default
    if validator is not None:
        err = validator(val)
        if err:
            CONFIG_ERRORS.append(f"{name}: {err} (using default {default!r})")
            return default
    return val


LOG_LEVEL = _get("LOG_LEVEL", str, "", _v_log_level)
PROGRAM_GRACE_SECONDS = _get("PROGRAM_GRACE_SECONDS", (int, float), 2.0, _v_nonneg)
OUTPUT_GRACE_SECONDS = _get("OUTPUT_GRACE_SECONDS", (int, float), 2.0, _v_nonneg)
CWD_WAIT_TIMEOUT_SECONDS = _get(
    "CWD_WAIT_TIMEOUT_SECONDS", (int, float), 0.2, _v_nonneg
)
OUTPUT_TAB_PREFIX = _get("OUTPUT_TAB_PREFIX", str, "*")
BELL_TAB_PREFIX = _get("BELL_TAB_PREFIX", str, "!")
ALERT_STICKY_SECONDS = _get("ALERT_STICKY_SECONDS", (int, float), 1.0, _v_nonneg)
ALERT_PAD_SECONDS = _get("ALERT_PAD_SECONDS", (int, float), 10.0, _v_nonneg)
ALERT_AUTO_RESET_SECONDS = _get(
    "ALERT_AUTO_RESET_SECONDS", (int, float), 600.0, _v_nonneg
)

OUTPUT_TAB_FOREGROUND = _hex_color(
    _get("OUTPUT_TAB_FOREGROUND", str, "#000000", _v_hex)
)
OUTPUT_TAB_BACKGROUND = _hex_color(
    _get("OUTPUT_TAB_BACKGROUND", str, "#aa5500", _v_hex)
)
BELL_TAB_FOREGROUND = _hex_color(
    _get("BELL_TAB_FOREGROUND", str, "#000000", _v_hex)
)
BELL_TAB_BACKGROUND = _hex_color(
    _get("BELL_TAB_BACKGROUND", str, "#aa0000", _v_hex)
)

_eq_fg = _get("TAB_EQUAL_FOREGROUND", str, "", _v_hex_or_empty)
_eq_bg = _get("TAB_EQUAL_BACKGROUND", str, "", _v_hex_or_empty)
TAB_EQUAL_FOREGROUND = _hex_color(_eq_fg) if _eq_fg else 0
TAB_EQUAL_BACKGROUND = _hex_color(_eq_bg) if _eq_bg else 0
