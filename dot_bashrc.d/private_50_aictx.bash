__AICTX_NEW=(claude)
__AICTX_CONTINUE=(claude -c)

if command -v "${__AICTX_NEW[0]}" &>/dev/null; then
    __aictx() (
        set -euo pipefail
        shopt -s nullglob

        command -v fzf &>/dev/null || { echo "aictx: fzf not in PATH" >&2; exit 1; }

        root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        template="$root/.template"

        last=""; [ -r "$root/.last" ] && IFS= read -r last < "$root/.last" || true

        is_archived() {
            local tags=""
            { IFS= read -r tags; } < "$1/.aictx" 2>/dev/null || return 1
            [[ " $tags " == *" archived "* ]]
        }

        # Rewrite the tags line (line 1) of $1/.aictx.
        set_tags() {
            local dir=$1 newtags=$2 f="$1/.aictx" tmp
            tmp=$(mktemp)
            { printf '%s\n' "$newtags"; tail -n +2 "$f"; } > "$tmp"
            mv "$tmp" "$f"
        }

        add_archived() {
            local tags=""
            { IFS= read -r tags; } < "$1/.aictx" || true
            [[ " $tags " == *" archived "* ]] && return 0
            set_tags "$1" "${tags:+$tags }archived"
        }

        remove_archived() {
            local tags="" out
            { IFS= read -r tags; } < "$1/.aictx" || true
            out=$(printf '%s\n' "$tags" | tr ' ' '\n' | grep -vx 'archived' | paste -sd' ' -)
            set_tags "$1" "$out"
        }

        emit_main() {
            local dir=$1 name tags="" summary=""
            name=$(basename "$dir")
            { IFS= read -r tags; IFS= read -r summary; } < "$dir/.aictx" || true
            printf '%s\t  \e[2m%s\e[0m\t%s\n' "$name" "$summary" "$tags"
        }

        emit_manage() {
            local dir=$1 name tags="" summary="" prefix=c
            name=$(basename "$dir")
            { IFS= read -r tags; IFS= read -r summary; } < "$dir/.aictx" || true
            [[ " $tags " == *" archived "* ]] && prefix=a
            printf '%s\t%s\t  \e[2m%s\e[0m\t%s\n' "$prefix" "$name" "$summary" "$tags"
        }

        list_main() {
            if [ -n "$last" ] && [ -r "$root/$last/.aictx" ] && ! is_archived "$root/$last"; then
                emit_main "$root/$last"
            fi
            for f in "$root"/*/.aictx; do
                dir=$(dirname "$f")
                [ "$(basename "$dir")" = "$last" ] && continue
                is_archived "$dir" && continue
                emit_main "$dir"
            done
        }

        list_manage() {
            for f in "$root"/*/.aictx; do
                emit_manage "$(dirname "$f")"
            done
        }

        manage_view() {
            while :; do
                local out key sels names=()
                out=$(list_manage | fzf \
                    --ansi --layout=reverse --multi \
                    --delimiter=$'\t' --with-nth=1,2,3 --nth=2 \
                    --header 'tab: mark · ctrl-a: archive · ctrl-u: unarchive · ctrl-x: delete · esc: back' \
                    --expect=ctrl-a,ctrl-u,ctrl-x,esc) || return 0
                key=$(printf '%s' "$out" | head -n1)
                sels=$(printf '%s' "$out" | tail -n +2)
                names=()
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    names+=("$(cut -f2 <<<"$line")")
                done <<<"$sels"
                case "$key" in
                    esc|"") return 0 ;;
                    ctrl-a)
                        for n in "${names[@]}"; do add_archived "$root/$n"; done ;;
                    ctrl-u)
                        for n in "${names[@]}"; do remove_archived "$root/$n"; done ;;
                    ctrl-x)
                        [ ${#names[@]} -eq 0 ] && continue
                        printf 'Delete these chats permanently?\n' >/dev/tty
                        printf '  - %s\n' "${names[@]}" >/dev/tty
                        printf 'Type "yes" to confirm: ' >/dev/tty
                        local confirm=""
                        read -r confirm </dev/tty || true
                        if [ "$confirm" = "yes" ]; then
                            for n in "${names[@]}"; do rm -rf "$root/$n"; done
                        fi ;;
                esac
            done
        }

        while :; do
            query=""; key=""; sel=""
            { IFS= read -r query; IFS= read -r key; IFS= read -r sel; } < <(list_main | fzf \
                --ansi --layout=reverse --delimiter=$'\t' --with-nth=1,2 \
                --preview "head -n 2 '$root'/{1}/.aictx; printf 'files: '; ls -p -I .aictx '$root'/{1} | tr '\n' ' '; echo" \
                --preview-window=bottom:3 \
                --print-query --expect=ctrl-n,ctrl-d,esc \
                --header 'enter: open  ·  ctrl-n: new  ·  ctrl-d: manage  ·  esc: cancel') || true

            case "$key" in
                esc) exit 0 ;;
                ctrl-d) manage_view; continue ;;
            esac

            is_new=0
            if [ "$key" = "ctrl-n" ] || { [ -z "$sel" ] && [ -n "$query" ]; }; then
                slug=$(printf '%s' "$query" \
                    | sed 'y/åäöÅÄÖé _/aaoAAOe--/' \
                    | tr '[:upper:]' '[:lower:]' \
                    | tr -cd 'a-z0-9-' \
                    | sed -E 's/-+/-/g; s/^-|-$//g')
                [ -z "$slug" ] && { echo "empty name" >&2; exit 1; }

                dir="$root/$slug"
                [ -e "$dir" ] && { echo "exists: $dir" >&2; exit 1; }

                cp -r "$template" "$dir"
                tags="$(date +%Y-%m-%d) ${slug//-/ }"
                summary="$query"
                printf '%s\n%s\n' "$tags" "$summary" > "$dir/.aictx"
                cmd=("${__AICTX_NEW[@]}")
                is_new=1
            else
                [ -z "$sel" ] && exit 0
                dir="$root/$(cut -f1 <<<"$sel")"
                transcripts=("$HOME/.claude/projects/${dir//\//-}"/*.jsonl)
                if (( ${#transcripts[@]} > 0 )); then
                    cmd=("${__AICTX_CONTINUE[@]}")
                else
                    # Existing slug with no prior transcript (e.g. internal
                    # state wiped). Treat as a new chat so the slug is
                    # re-evaluated on exit.
                    cmd=("${__AICTX_NEW[@]}")
                    is_new=1
                fi
            fi
            break
        done

        printf '%s\n' "$(basename "$dir")" > "$root/.last"
        (cd "$dir" && "${cmd[@]}" >/dev/tty)
        printf '%s\n%s\n' "$dir" "$is_new"
    )

    aictx() {
        local out is_new
        { IFS= read -r out; IFS= read -r is_new; } < <(__aictx) || return
        [ -z "$out" ] && return
        [ -d "$out" ] || return
        local caller_pwd=$PWD
        if [ "$is_new" = 1 ]; then
            # Slug may be renamed by the background tidy — we can't
            # reliably cd into a name that's about to change. Stay put.
            printf 'aictx: slug-tidy + autocommit running in background — journalctl --user -fn 50\n' >&2
        else
            cd "$out"
        fi
        # Detached transient user service: tidy (if is_new) + autocommit.
        # Auto-generated unit name so parallel exits don't collide.
        systemd-run --user --no-block --quiet \
            --description="aictx post-exit work for $(basename "$out")" \
            --setenv=PATH="$PATH" \
            bash -c '
                source ~/.bashrc.d/50_aictx.bash 2>/dev/null
                out=$1; is_new=$2
                if [ "$is_new" = 1 ]; then
                    slug=$(basename "$out")
                    parent=$(dirname "$out")
                    cd "$parent" && aictx-tidy-one "$slug" || true
                fi
                __aictx_autocommit
            ' _ "$out" "$is_new"
        OLDPWD=$caller_pwd
    }

    # Snapshot ~/Documents/aictx into a bare repo under XDG_STATE_HOME.
    # Runs after every aictx exit; commit message is a timestamp, no AI.
    # Lazy init on first call. No-op when the work tree is clean.
    __aictx_autocommit() {
        command -v git >/dev/null 2>&1 || return 0
        local repo="${XDG_STATE_HOME:-$HOME/.local/state}/aictx-git"
        local work="${AICTX_ROOT:-$HOME/Documents/aictx}"
        [ -d "$work" ] || return 0
        if [ ! -d "$repo" ]; then
            git init --bare --quiet "$repo" || return 0
            git --git-dir="$repo" config user.name "aictx"
            git --git-dir="$repo" config user.email "aictx@localhost"
        fi
        git --git-dir="$repo" --work-tree="$work" add -A
        git --git-dir="$repo" --work-tree="$work" \
            commit --quiet -m "$(date -Iseconds)" 2>/dev/null
        return 0
    }

    # Run the tidy-slug logic manually against a single chat slug.
    # Bypasses the systemd ExecCondition guards (no daily marker, no claude-running check)
    # and the per-slug skip rules (.last, 8h mtime) — the caller picked this slug on purpose.
    aictx-tidy-one() {
        local slug=${1:-}
        slug=${slug%/}
        slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local rules_file="$HOME/.config/systemd/user/aictx-tidy-uses/prompt.md"
        if [ -z "$slug" ] || [ ! -d "$root/$slug" ]; then
            echo "usage: aictx-tidy-one <existing-slug>" >&2
            return 1
        fi
        [ -r "$rules_file" ] || { echo "missing rules: $rules_file" >&2; return 1; }

        local overview=""
        local d s sum
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            [ -e "$d/.aictx" ] || continue
            s=$(basename "$d")
            sum=""
            { IFS= read -r _; IFS= read -r sum; } < "$d/.aictx" || true
            overview="${overview}${overview:+
}- $s — ${sum:-(no summary)}"
        done

        local prompt
        prompt=$(cat <<EOF
You are doing a one-shot manual rename evaluation for a single chat slug.
The user picked this slug deliberately — eligibility checks (\`.last\`,
8h-mtime, volume cap) do not apply. Your job is the slug-quality
judgement and, if warranted, the rename itself, plus a similar judgement
on the \`.aictx\` summary line (line 2).

**Target slug:** \`$slug\` (directory: \`$root/$slug\`)

## Rules

The shared slug-tidy rules — read in full:

$(cat "$rules_file")

## Manual-mode override: summary refresh

The shared rules tell you to leave line 2 of \`.aictx\` alone. In manual
mode you also evaluate line 2 — this function runs right after a chat
session, so the latest transcript is the best signal we'll ever have for
what the chat is actually about.

Update line 2 only if it's clearly wrong, stale, or describes a different
scope than the transcript shows. Borderline → leave it. Keep to one
short sentence; don't expand scope. Make this edit whether or not you
rename the slug, and do it in the same \`.aictx\` edit as the tag-line
update when a rename happens.

## Workspace conventions

Also read \`$root/CLAUDE.md\` if it adds anything not covered above.

## Workspace overview

Every existing chat slug, with its one-line summary — use this to avoid
picking a new slug that's ambiguous with or duplicates an existing one,
even if the names differ literally:

$overview

## Output

Your final assistant message must be exactly one line: the final slug
(new if renamed, original \`$slug\` otherwise). Nothing else — no prose,
no quotes. Tool calls before the final response are unaffected.
EOF
)
        local newslug claude_out
        claude_out=$(cd "$root" && claude --model sonnet --permission-mode acceptEdits \
            --allowedTools "Read Glob Grep Edit Bash(claude-project move:*) Bash(ls:*) Bash(find:*) Bash(stat:*) Bash(cat:*) Bash(date:*) Bash(pwd:*) Bash(command:*)" \
            -p "$prompt")
        # Take the last non-empty line and the last whitespace-separated token of it,
        # so any leading prose Claude added doesn't pollute the slug.
        newslug=$(printf '%s\n' "$claude_out" | awk 'NF{last=$NF} END{print last}')
        # If .last pointed at the input slug and the slug got renamed, update .last too.
        if [ -n "$newslug" ] && [ "$newslug" != "$slug" ] && [ -r "$root/.last" ]; then
            local last=""
            IFS= read -r last < "$root/.last" || true
            if [ "$last" = "$slug" ]; then
                printf '%s\n' "$newslug" > "$root/.last"
            fi
        fi
        printf '%s\n' "${newslug:-$slug}"
    }
fi
