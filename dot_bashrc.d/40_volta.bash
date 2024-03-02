# Place Volta toolchain under XDG_DATA_HOME instead of ~/.volta.

___BASHRC_VOLTA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/volta"
if [ -d "$___BASHRC_VOLTA_HOME" ]; then
    export VOLTA_HOME="$___BASHRC_VOLTA_HOME"
    export PATH="$VOLTA_HOME/bin:$PATH"
fi
unset ___BASHRC_VOLTA_HOME
