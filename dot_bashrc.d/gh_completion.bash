if command -v gh &>/dev/null; then
    __BASHRC_SOURCE_COMMAND_OUTPUT gh completion -s bash
    __BASHRC_SOURCE_COMMAND_OUTPUT gh copilot alias bash
    __BASHRC_SOURCE_COMMAND_OUTPUT gh copilot completion bash
    __BASHRC_SOURCE_COMMAND_OUTPUT gh classroom completion bash
fi
