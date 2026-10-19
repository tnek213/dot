if command -v chezmoi &>/dev/null; then
    __BASHRC_SOURCE_COMMAND_OUTPUT chezmoi completion bash
    if command -v code &>/dev/null; then
        export CHEZMOI_DIFF_COMMAND="code --diff"
    fi
fi
