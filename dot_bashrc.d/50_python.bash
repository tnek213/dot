if command -v python3 &>/dev/null; then
    # Place Python REPL history under XDG_STATE_HOME instead of $HOME.
    # PYTHON_HISTORY requires Python 3.13+.
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/python"
    export PYTHON_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/python/history"

    # Mirror __pycache__ trees under XDG_CACHE_HOME instead of polluting source dirs.
    # PYTHONPYCACHEPREFIX requires Python 3.8+.
    export PYTHONPYCACHEPREFIX="${XDG_CACHE_HOME:-$HOME/.cache}/python"

    # Redirect pytest's .pytest_cache dir into XDG_CACHE_HOME. Single shared cache
    # across all projects; pytest namespaces entries by test nodeid internally.
    export PYTEST_ADDOPTS="-o cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/pytest"
fi
