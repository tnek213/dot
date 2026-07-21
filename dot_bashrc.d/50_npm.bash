if command -v npm &>/dev/null; then
    # Place npm cache and user rc under XDG dirs instead of ~/.npm and ~/.npmrc.
    # Using npm_config_* env vars avoids `npm config set` writing a new ~/.npmrc.
    export npm_config_cache="${XDG_CACHE_HOME:-$HOME/.cache}/npm"
    export npm_config_userconfig="${XDG_CONFIG_HOME:-$HOME/.config}/npm/npmrc"

    mkdir -p "$npm_config_cache"
    mkdir -p "$(dirname "$npm_config_userconfig")"
fi
