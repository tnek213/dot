import sys

from kitty.constants import config_dir

if config_dir not in sys.path:
    sys.path.insert(0, config_dir)

from helpers import log
from cmd_polling import poll_all_windows
from window_state import windows_polling


def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
    log('draw_tab', {
        'tab_id': tab.tab_id,
        'index': index,
        'is_last': is_last,
        'prev_tab': extra_data.prev_tab.tab_id if extra_data.prev_tab else None,
        'for_layout': extra_data.for_layout,
    })
    if extra_data.prev_tab is None:
        log('draw_tab:branch_first_of_pass', {})
        poll_all_windows()
        log('draw_tab:after_poll', {'ids': sorted(windows_polling.keys())})
    else:
        log('draw_tab:branch_subsequent', {})
    if tab.is_active:
        screen.cursor.fg = draw_data.active_fg
        screen.cursor.bg = draw_data.active_bg
        screen.cursor.bold = draw_data.active_font_style.bold
        screen.cursor.italic = draw_data.active_font_style.italic
    else:
        screen.cursor.fg = draw_data.inactive_fg
        screen.cursor.bg = draw_data.inactive_bg
        screen.cursor.bold = draw_data.inactive_font_style.bold
        screen.cursor.italic = draw_data.inactive_font_style.italic
    screen.draw(tab.title)
    log('draw_tab:return', {'cursor_x': screen.cursor.x})
    # Return last occupied cell, not the cell past it: kitty's tab_at uses
    # `a <= x <= b` inclusive, so returning cursor.x makes adjacent tabs share
    # a boundary cell and the left tab wins ties — single-char tabs become
    # unclickable on their own glyph.
    return screen.cursor.x - 1
