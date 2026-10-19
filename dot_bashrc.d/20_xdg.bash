# Export the XDG Base Directory vars explicitly.
# Other snippets fall back to these defaults via ${XDG_*:-...}, so ordering
# inside .bashrc.d/ does not matter — this just makes the values visible to
# child processes that inherit the environment.

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
