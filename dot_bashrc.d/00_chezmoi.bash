if command -v chezmoi &>/dev/null; then
    __BASHRC_SOURCE_COMMAND_OUTPUT chezmoi completion bash
    export CHEZMOI_DIFF_COMMAND="code --diff"
fi
