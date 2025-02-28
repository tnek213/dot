# shellcheck disable=SC1091

if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"

    #
    # lazy load nvm and nvm bash completion
    #

    nvm() {
        unset -f nvm
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        nvm "$@"
    }

    complete -o default -F __nvm nvm

    __nvm() {
        unset -f __nvm
        [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
        __nvm "$@"
    }
fi
