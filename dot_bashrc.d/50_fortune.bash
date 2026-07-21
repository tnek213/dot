if [ -t 1 ] && command -v fortune &>/dev/null; then
    ___BASHRC_FORTUNE_QUOTES="${XDG_DATA_HOME:-$HOME/.local/share}/fortunes/quotes"
    ___BASHRC_FORTUNE_QUOTES_DAT="${___BASHRC_FORTUNE_QUOTES}.dat"

    if [ -e "$___BASHRC_FORTUNE_QUOTES" ] && [ -e "$___BASHRC_FORTUNE_QUOTES_DAT" ]; then
        fortune "${XDG_DATA_HOME:-$HOME/.local/share}/fortunes/quotes" | awk '
            /^    — / { printf "\033[2m%s\033[0m\n", $0; next }
            { printf "\033[3m%s\033[0m\n", $0 }
        '
    fi
fi
