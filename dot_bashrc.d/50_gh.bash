if command -v gh &>/dev/null; then
    __BASHRC_SOURCE_COMMAND_OUTPUT gh completion -s bash
    __BASHRC_SOURCE_COMMAND_OUTPUT gh classroom completion bash

    # shellcheck disable=SC2046,SC2317,SC2329
    ___BASHRC_GH_TEMPLATE() {
        if [ $# -gt 0 ]; then
            cd "$1" || { echo "Error: invalid target $1" >&2 && return 1; }
        fi

        gh repo create \
            "TEMPL/$(basename "$PWD")" \
            --disable-issues \
            --disable-wiki \
            --private \
            $(git rev-parse HEAD 1>/dev/null 2>&1 && printf -- --push) \
            --source .

        git rebase --root -x "git commit --amend --reset-author -CHEAD"
        git push -f
    }

    for ___BASHRC_GH_ORG in kc8se nackc8; do
        eval "$(declare -f ___BASHRC_GH_TEMPLATE | sed "s/TEMPL/$___BASHRC_GH_ORG/")"
    done

    unset ___BASHRC_GH_TEMPLATE
fi
