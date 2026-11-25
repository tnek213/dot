if command -v python3 &>/dev/null; then
    # Redirect ruff's .ruff_cache dir into XDG_CACHE_HOME. Single shared cache is
    # safe; ruff namespaces entries internally.
    export RUFF_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ruff"
fi
