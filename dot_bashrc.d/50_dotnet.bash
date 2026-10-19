if command -v dotnet &>/dev/null; then
    # Place .NET CLI state under XDG_DATA_HOME instead of ~/.dotnet.
    # DOTNET_CLI_HOME relocates ~/.dotnet (corefx crypto stores, tool state, etc).
    export DOTNET_CLI_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/dotnet"
fi
