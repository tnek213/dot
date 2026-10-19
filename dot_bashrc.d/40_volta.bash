# Place Volta toolchain under XDG_DATA_HOME instead of ~/.volta.
# Exported unconditionally so a fresh machine can bootstrap Volta into
# VOLTA_HOME (a not-yet-existing dir on PATH is harmless).

export VOLTA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/volta"
export PATH="$VOLTA_HOME/bin:$PATH"
