# shellcheck disable=SC2046

gh-repo-create-nackc8() {

    if [ $# -gt 0 ]; then
        cd "$1" || echo "Error: invalid target $1" >&2 && return 1
    fi

    gh repo create \
        "nackc8/$(basename "$PWD")" \
        --disable-issues \
        --disable-wiki \
        --private \
        $(git rev-parse HEAD 1>/dev/null 2>&1 && printf -- --push) \
        --source .

    git rebase --root -x "git commit --amend --reset-author -CHEAD"
    git push -f
}
