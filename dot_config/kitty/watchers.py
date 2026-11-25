from time import monotonic

import state


def on_load(boss, window, data):
    pass


def on_close(boss, window, data):
    pass


def on_resize(boss, window, data):
    pass


def on_focus_change(boss, window, data):
    tab = boss.tab_for_window(window)
    if tab is not None:
        state.of(tab.id).last_focus = monotonic()


def on_title_change(boss, window, data):
    pass


def on_set_user_var(boss, window, data):
    pass


def on_cmd_startstop(boss, window, data):
    tm = boss.active_tab_manager
    if tm is not None:
        tm.mark_tab_bar_dirty()


def on_color_scheme_preference_change(boss, window, data):
    pass


def on_tab_bar_dirty(boss, tab, data):
    live_ids = []
    for t in boss.all_tabs:
        state.of(t.id)  # ensure registered, sets created_at on first sight
        live_ids.append(t.id)
    state.gc(live_ids)


def on_quit(boss, window, data):
    pass
