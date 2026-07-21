if command -v nnn &>/dev/null; then
    export NNN_FIFO=/tmp/nnn.fifo
    export NNN_PLUG='p:preview-tui;s:ksplit'
    export NNN_TERMINAL=kitty
    # Open preview-tui automatically on launch with `n` (use -a to auto-create FIFO)
    # -T v: version (natural) sort, so file20 follows file19
    n() {
        # Expose bat (→ batcat on Debian) to preview-tui only inside nnn
        PATH="$HOME/.config/nnn/bin:$PATH" command nnn -aTv "$@"
    }
fi
