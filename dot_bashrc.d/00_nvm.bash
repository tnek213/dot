# shellcheck disable=SC1091

if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

    __BASHRC_SOURCE_COMMAND_OUTPUT node --completion-bash
    __BASHRC_SOURCE_COMMAND_OUTPUT npm completion
fi
