__AICTX_NEW=(claude)
__AICTX_CONTINUE=(claude -c)

if command -v "${__AICTX_NEW[0]}" &>/dev/null; then
    __aictx() (
        set -euo pipefail
        shopt -s nullglob

        command -v fzf &>/dev/null || { echo "aictx: fzf not in PATH" >&2; exit 1; }

        root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        template="${AICTX_TEMPLATE:-$HOME/.config/aictx/template}"

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

        # Bump line 3 of $1/.aictx ("used:N lastused:YYYY-MM-DD"), at most once
        # per calendar day. Drives the settling-in window (usage days, not
        # wall-clock). Echoes the resulting count. Lines 1-2 are preserved.
        bump_usage() {
            local f="$1/.aictx" today l1="" l2="" l3="" used last tmp
            today=$(date +%F)
            { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; } < "$f" 2>/dev/null || true
            used=0; last=""
            if [[ $l3 == used:* ]]; then
                used=${l3#used:}; used=${used%% *}
                last=${l3##*lastused:}
                [[ $used =~ ^[0-9]+$ ]] || used=0
            fi
            if [ "$last" != "$today" ]; then
                used=$((used + 1)); last=$today
            fi
            tmp=$(mktemp)
            printf '%s\n%s\nused:%s lastused:%s\n' "$l1" "$l2" "$used" "$last" > "$tmp"
            mv "$tmp" "$f"
            printf '%s\n' "$used"
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
            local dir=$1 color=${2:-} name tags="" summary=""
            name=$(basename "$dir")
            { IFS= read -r tags; IFS= read -r summary; } < "$dir/.aictx" || true
            # $color bands the name by group; --ansi strips it from the selection
            # so the slug stays clean for cut -f1 / preview.
            printf '%s%s\e[0m\t  \e[2m%s\e[0m\t%s\n' "$color" "$name" "$summary" "$tags"
        }

        emit_manage() {
            local dir=$1 name tags="" summary="" prefix=c
            name=$(basename "$dir")
            { IFS= read -r tags; IFS= read -r summary; } < "$dir/.aictx" || true
            [[ " $tags " == *" archived "* ]] && prefix=a
            printf '%s\t%s\t  \e[2m%s\e[0m\t%s\n' "$prefix" "$name" "$summary" "$tags"
        }

        list_main() {
            # Pinned resume candidate first, in bold.
            if [ -n "$last" ] && [ -r "$root/$last/.aictx" ] && ! is_archived "$root/$last"; then
                emit_main "$root/$last" $'\e[1m'
            fi
            # Remaining chats in slug order (so same-subject chats are adjacent),
            # banded by main word (first slug token) — colour toggles per group
            # so each topic reads as a block.
            local prev="" shade=0 mw color
            for f in "$root"/*/.aictx; do
                dir=$(dirname "$f")
                [ "$(basename "$dir")" = "$last" ] && continue
                is_archived "$dir" && continue
                mw=$(basename "$dir"); mw=${mw%%-*}
                [ "$mw" != "$prev" ] && { shade=$((1 - shade)); prev=$mw; }
                [ "$shade" = 1 ] && color=$'\e[36m' || color=""
                emit_main "$dir" "$color"
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
            else
                [ -z "$sel" ] && exit 0
                dir="$root/$(cut -f1 <<<"$sel")"
                transcripts=("$HOME/.claude/projects/${dir//\//-}"/*.jsonl)
                if (( ${#transcripts[@]} > 0 )); then
                    cmd=("${__AICTX_CONTINUE[@]}")
                else
                    cmd=("${__AICTX_NEW[@]}")
                fi
            fi
            break
        done

        slug=$(basename "$dir")
        printf '%s\n' "$slug" > "$root/.last"
        # Count this open as a usage day and auto-settle once the chat has been
        # used on more than 7 distinct days (unless already settled early).
        used=$(bump_usage "$dir")
        if [ "${used:-0}" -gt 7 ] && [ -e "$dir/CLAUDE.md" ] \
           && ! grep -q '^Settled:' "$dir/CLAUDE.md"; then
            printf 'Settled: %s — 7 usage days elapsed; reorganize only on request.\n' \
                "$(date +%F)" >> "$dir/CLAUDE.md"
        fi
        (cd "$dir" && "${cmd[@]}" >/dev/tty)
        printf '%s\n' "$dir"
    )

    aictx() {
        local out
        out=$(__aictx) || return
        [ -n "$out" ] && [ -d "$out" ] || return
        # Only the chat just closed, and only its summary line: nothing is
        # renamed, moved or split, so other open chats are never disturbed.
        __aictx_refresh_summary "$out"
        cd "$out"
    }

    # Rewrite line 2 of $1/.aictx (the one-sentence summary) if the session
    # just ended shows it is wrong or stale. The model only prints the line;
    # the shell writes it, so nothing else in the chat can change.
    __aictx_refresh_summary() {
        local dir=$1 l1="" l2="" l3="" transcript recent readme="" new tmp
        { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; } < "$dir/.aictx" 2>/dev/null || return 0
        transcript=$(ls -t "$HOME/.claude/projects/${dir//\//-}"/*.jsonl 2>/dev/null | head -n1)
        [ -n "$transcript" ] || return 0
        recent=$(jq -r 'select(.type=="user" or .type=="assistant")
            | .message.content
            | if type=="string" then . else (map(select(.type=="text").text) | join(" ")) end
            | select(length > 0)' "$transcript" 2>/dev/null | tail -c 20000)
        [ -n "$recent" ] || return 0
        [ -r "$dir/README.md" ] && readme=$(head -c 4000 "$dir/README.md")
        printf 'aictx: refreshing summary of %s …\n' "$(basename "$dir")" >&2
        new=$(claude --model sonnet --tools "" -p "$(cat <<EOF
You maintain the one-line summary of a chat directory, shown in a picker
so its owner can find the chat again.

Current summary: $l2

README.md:
$readme

End of the latest conversation:
$recent

If the current summary is still accurate, print exactly KEEP. Otherwise
print one short sentence (under 100 characters, same language as the
current summary) describing what the whole chat is about — not just the
last session. Print nothing else.
EOF
)" 2>/dev/null | awk 'NF{last=$0} END{print last}')
        [ -n "$new" ] && [ "$new" != KEEP ] && [ "$new" != "$l2" ] || return 0
        tmp=$(mktemp)
        printf '%s\n%s\n%s\n' "$l1" "$new" "$l3" > "$tmp" && mv "$tmp" "$dir/.aictx"
        printf 'aictx: summary -> %s\n' "$new" >&2
    }
fi
