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
            local dir=$1 color=${2:-} name tags="" summary="" mark=""
            name=$(basename "$dir")
            { IFS= read -r tags; IFS= read -r summary; } < "$dir/.aictx" || true
            # Flag a pending proposal (bright glyph in the summary column).
            if [ -f "$dir/parts.md" ]; then
                if grep -q '^## MERGE-SUGGESTED' "$dir/parts.md"; then mark=$'\e[33m⇄\e[0m '
                elif grep -q '^## SPLIT-SUGGESTED' "$dir/parts.md"; then mark=$'\e[33m✂\e[0m '; fi
            fi
            # $color bands the name by group; --ansi strips it from the selection
            # so the slug stays clean for cut -f1 / preview.
            printf '%s%s\e[0m\t  %s\e[2m%s\e[0m\t%s\n' "$color" "$name" "$mark" "$summary" "$tags"
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
        # Queue this chat for tidy at exit. Append now (before claude runs) so a
        # Ctrl-C / closed terminal still leaves it queued for a later drain.
        # Dedup so reopening the same chat doesn't pile up entries.
        if [ ! -e "$root/.tidylist" ] || ! grep -qxF "$slug" "$root/.tidylist"; then
            printf '%s\n' "$slug" >> "$root/.tidylist"
        fi
        (cd "$dir" && "${cmd[@]}" >/dev/tty)
        printf '%s\n%s\n' "$dir" "$is_new"
    )

    aictx() {
        local out is_new
        { IFS= read -r out; IFS= read -r is_new; } < <(__aictx) || return
        [ -z "$out" ] && return
        [ -d "$out" ] || return
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local slug; slug=$(basename "$out")
        # Foreground: drain the tidy queue — this chat plus any leftovers from
        # interrupted prior sessions. Each entry is tidied then popped, so a
        # Ctrl-C / closed terminal during this step just leaves it for next time.
        # Runs synchronously so you see any rename before the prompt returns.
        local final; final=$(__aictx_process_tidylist "$slug")
        # cd into this chat under its final (possibly renamed) slug.
        if [ -n "$final" ] && [ -d "$root/$final" ]; then
            cd "$root/$final"
        elif [ -d "$out" ]; then
            cd "$out"
        fi
    }

    # Drain $root/.tidylist in the foreground, one slug at a time: run each
    # through __aictx_process_tidyitem (rename + type/summary refresh), then pop it —
    # whether or not it succeeded, so a bad entry can't wedge the queue. Echoes
    # the final slug for the slug passed as $1 (so the caller can cd into it
    # after a rename); progress goes to stderr.
    __aictx_process_tidylist() {
        local want=${1:-}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local list="$root/.tidylist"
        local final="$want"
        if [ -r "$list" ]; then
            local slug new
            while :; do
                IFS= read -r slug < "$list" 2>/dev/null || true
                [ -n "$slug" ] || break
                if [ -d "$root/$slug" ]; then
                    printf 'aictx: tidying %s …\n' "$slug" >&2
                    new=$(__aictx_process_tidyitem "$slug") || new="$slug"
                    if [ "$new" != "$slug" ]; then
                        printf 'aictx: renamed %s -> %s\n' "$slug" "$new" >&2
                    fi
                    [ "$slug" = "$want" ] && final="$new"
                fi
                # Pop the first line.
                tail -n +2 "$list" > "$list.tmp" 2>/dev/null && mv "$list.tmp" "$list"
            done
            rm -f "$list"
        fi
        printf '%s\n' "$final"
    }

    # Workspace overview: each chat slug + its one-line .aictx summary. Feeds the
    # tidy / parts-eval / split / merge prompts (disambiguation, sibling lookup).
    __aictx_overview() {
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}" d s sum out=""
        for d in "$root"/*/; do
            [ -d "$d" ] || continue; [ -e "$d/.aictx" ] || continue
            s=$(basename "$d"); sum=""
            { IFS= read -r _; IFS= read -r sum; } < "$d/.aictx" || true
            out="${out}${out:+
}- $s — ${sum:-(no summary)}"
        done
        printf '%s\n' "$out"
    }

    # Sorted unique sha256 of $1's content files, excluding the bookkeeping files
    # that legitimately change (.aictx, CLAUDE.md, parts.md, README.md).
    __aictx_content_hashes() {
        find "$1" -type f \
            ! -name .aictx ! -name CLAUDE.md ! -name parts.md ! -name README.md \
            -exec sha256sum {} + 2>/dev/null | awk '{print $1}' | sort -u
    }

    # After a split/merge, confirm every pre-op content hash ($2, sorted) still
    # exists somewhere under the workspace — i.e. files were moved, not lost or
    # altered. $1 is the op label for the message.
    __aictx_check_integrity() {
        local label=$1 before=$2 after missing n
        after=$(__aictx_content_hashes "${AICTX_ROOT:-$HOME/Documents/aictx}")
        missing=$(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
        if [ -n "$missing" ]; then
            n=$(printf '%s\n' "$missing" | grep -c .)
            printf '%s: WARNING — %d content file(s) vanished or changed; review before relying on the result.\n' "$label" "$n" >&2
        else
            printf '%s: content integrity OK — all topic files preserved.\n' "$label" >&2
        fi
    }

    # Tidy one chat at exit: judge its slug (rename if clearly better), refresh
    # its type/stage tags and .aictx summary, inject the type guidance, then
    # evaluate parts. One foreground pass per queued chat. Echoes the final slug.
    __aictx_process_tidyitem() {
        local slug=${1:-}
        slug=${slug%/}
        slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local rules_file="$HOME/.config/aictx/slug-rules.md"
        local types_dir="$HOME/.config/aictx/types"
        if [ -z "$slug" ] || [ ! -d "$root/$slug" ]; then
            echo "usage: __aictx_process_tidyitem <existing-slug>" >&2
            return 1
        fi
        [ -r "$rules_file" ] || { echo "missing rules: $rules_file" >&2; return 1; }

        local overview; overview=$(__aictx_overview)

        local prompt
        prompt=$(cat <<EOF
You are evaluating one chat slug at exit. Your job is the slug-quality
judgement and, if warranted, the rename itself, plus a similar judgement
on the \`.aictx\` summary line (line 2).

**Target slug:** \`$slug\` (directory: \`$root/$slug\`)

## Rules

The shared slug-tidy rules — read in full:

$(cat "$rules_file")

## Summary line (line 2)

This runs right after a chat session, so the latest transcript is the
best signal for what the chat is actually about. Per the shared rules,
update line 2 only if it's clearly wrong, stale, or describes a different
scope than the transcript shows. Borderline → leave it. Keep to one
short sentence; don't expand scope. Make this edit whether or not you
rename the slug, and do it in the same \`.aictx\` edit as the tag-line
update when a rename happens.

Leave line 3 (\`used:N lastused:...\`) untouched — the \`aictx\` command
maintains it. Edit only lines 1 and 2.

## Type and stage classification

This function runs right after a session, so the transcript is the best
signal for what kind of chat this is. Classify it and load matching
guidance:

1. Read \`$types_dir/README.md\` (the taxonomy + decision aid).
2. Pick at most one \`type:\` — \`tool\`, \`concept\`, \`workflow\`,
   \`project\`, or \`reference\`. If genuinely unclear, leave \`type:\`
   unset. Also add \`stage:incubating\` if this is clearly an idea space
   headed for its own repo once built.
3. On \`.aictx\` line 1, set/refresh the \`type:<kind>\` tag (and
   \`stage:incubating\` when it applies) — change it only if the current
   value is absent or clearly wrong. Fold this into the same line-1 edit
   as any tag/rename update above.
4. Mirror the guidance into the chat's \`./CLAUDE.md\`: replace the block
   between \`<!-- aictx:type-guidance START -->\` and
   \`<!-- aictx:type-guidance END -->\` (create it at end of file if
   absent) with the verbatim contents of \`$types_dir/<type>.md\`, plus
   \`$types_dir/incubating.md\` when \`stage:incubating\` is set. If
   \`type:\` is unset, leave \`./CLAUDE.md\` alone.

Borderline → leave existing classification as-is. Don't churn.

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
        local final="${newslug:-$slug}"
        # Parts evaluation (gated internally on content change). No stdout.
        __aictx_eval_parts "$final"
        printf '%s\n' "$final"
    }

    # Echo a chat's activation-day count (the N in `used:N` on .aictx line 3), or 0.
    __aictx_used() {
        local l3 u=0
        l3=$(sed -n '3p' "$1/.aictx" 2>/dev/null)
        if [[ $l3 == used:* ]]; then u=${l3#used:}; u=${u%% *}; [[ $u =~ ^[0-9]+$ ]] || u=0; fi
        printf '%s' "$u"
    }

    # Refresh parts.md for one chat from its durable files, and (re)write a
    # SPLIT/MERGE-SUGGESTED block. Skipped unless the chat's content files changed
    # since the last eval — pass a second arg "force" to re-eval anyway (e.g. after
    # a parts-rules change). Foreground; emits no stdout (progress → tty) so
    # callers can capture the slug cleanly.
    __aictx_eval_parts() {
        local slug=${1:-} force=${2:-}
        slug=${slug%/}; slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local dir="$root/$slug"
        local rules="$HOME/.config/aictx/parts-rules.md"
        [ -d "$dir" ] || return 0
        [ -r "$rules" ] || return 0

        # Newest content mtime, excluding files our own passes mutate.
        local cmtime
        cmtime=$(find "$dir" -type f \
                   ! -name .aictx ! -name CLAUDE.md ! -name parts.md \
                   -printf '%T@\n' 2>/dev/null | sort -rn | head -n1)
        cmtime=${cmtime%.*}
        [ -n "$cmtime" ] || return 0   # no content files yet

        local parts="$dir/parts.md" last=""
        [ -r "$parts" ] && last=$(grep -oP '<!-- parts-eval: \K[0-9]+' "$parts" 2>/dev/null | head -n1)
        [ "$force" != force ] && [ -n "$last" ] && [ "$cmtime" -le "$last" ] && return 0   # unchanged

        # Proposal cooldown: after a dismissal (aictx-review's x), suppress new
        # SPLIT/MERGE proposals until the chat has been activated 5 more days
        # (used count). Marker lives in parts.md and is shell-owned (re-stamped below).
        local cd_note="" dis
        dis=$(grep -oP '<!-- proposal-dismissed: used=\K[0-9]+' "$parts" 2>/dev/null | head -n1)
        if [ -n "$dis" ] && [ "$(( $(__aictx_used "$dir") - dis ))" -lt 5 ]; then
            cd_note="

**Proposal cooldown is active** — a recent dismissal is still in effect. Do NOT
add a SPLIT-SUGGESTED or MERGE-SUGGESTED block this run; maintain the parts list
as normal otherwise."
        else
            dis=""   # absent or expired → don't re-stamp the marker (cooldown over)
        fi

        printf 'aictx: evaluating parts of %s …\n' "$slug" >&2
        local overview; overview=$(__aictx_overview)
        local prompt
        prompt=$(cat <<EOF
You are maintaining the "parts" list for one aictx chat, at exit.

**Chat:** \`$slug\` (directory: \`$dir\`)

## Rules

$(cat "$rules")

## Current parts.md

$( [ -r "$parts" ] && cat "$parts" || echo "(none yet)" )

## Workspace overview (sibling chats — for the merge check)

$overview

## Task

1. Examine the chat's durable files under \`$dir\` (README, topic .md files,
   code) and create/update \`$dir/parts.md\` per the "Maintaining parts.md" rules.
2. Apply the "Split trigger" rules: add/refresh/remove the SPLIT-SUGGESTED block.
3. Then apply the "Merge trigger" rules: using the overview above (read a
   sibling's parts.md if its summary looks related), add/refresh/remove a
   MERGE-SUGGESTED block. A chat carries at most one of SPLIT/MERGE.
$cd_note

Edit files directly; print only a one-line summary.
EOF
)
        ( cd "$root" && claude --model sonnet --permission-mode acceptEdits \
            --allowedTools "Read Glob Grep Edit Write Bash(ls:*) Bash(find:*) Bash(cat:*) Bash(date:*)" \
            -p "$prompt" >&2 ) || true

        # Stamp shell-owned markers: the eval marker, plus the dismissal-cooldown
        # marker if still active (strip any copies the AI left, re-add ours).
        [ -f "$parts" ] || printf '# Parts\n\n(no distinct parts yet)\n' > "$parts"
        local tmp; tmp=$(mktemp)
        {
            grep -v '<!-- parts-eval:\|<!-- proposal-dismissed:' "$parts"
            [ -n "$dis" ] && printf '<!-- proposal-dismissed: used=%s -->\n' "$dis"
            printf '<!-- parts-eval: %s -->\n' "$cmtime"
        } > "$tmp"
        mv "$tmp" "$parts"
    }

    # Classify one chat's type/stage from its files, set the type: tag on
    # .aictx line 1, and inject the matching guidance fragment into its
    # CLAUDE.md. Backfill helper for the sweep: **skipped if already typed**, so
    # the first sweep types everything and later runs are cheap. (The exit tidy
    # classifies inline for chats you open; this covers the rest.) No stdout.
    __aictx_classify_type() {
        local slug=${1:-}
        slug=${slug%/}; slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local dir="$root/$slug"
        local types_dir="$HOME/.config/aictx/types"
        local template="${AICTX_TEMPLATE:-$HOME/.config/aictx/template}"
        [ -d "$dir" ] || return 0
        [ -r "$types_dir/README.md" ] || return 0
        local l1=""; { IFS= read -r l1; } < "$dir/.aictx" 2>/dev/null || true
        [[ $l1 == *type:* ]] && return 0   # already typed (match any tag format)
        # Need durable content files to classify from. A chat with none should
        # get files first (aictx-backfill-files), not be typed from a one-liner.
        find "$dir" -type f ! -name .aictx ! -name CLAUDE.md ! -name parts.md ! -name README.md \
            -print -quit 2>/dev/null | grep -q . || return 0

        printf 'aictx: classifying type of %s …\n' "$slug" >&2
        local prompt
        prompt=$(cat <<EOF
You are classifying one aictx chat's type, for backfill.

**Chat:** \`$slug\` (directory: \`$dir\`)
**Template (for a missing CLAUDE.md):** \`$template\`

## Type taxonomy

$(cat "$types_dir/README.md")

## Task

Examine the chat's durable files under \`$dir\` (README, topic .md files, code)
and determine its type:

1. Pick at most one \`type:\` — \`tool\`, \`concept\`, \`workflow\`, \`project\`,
   or \`reference\`. Only if genuinely unclear, change nothing and stop. Add
   \`stage:incubating\` only if it clearly applies.
2. Append the \`type:<kind>\` tag (and \`stage:incubating\` if apt) to \`.aictx\`
   line 1 **as new space-separated tags** — the tags on line 1 are separated by
   single spaces, *never* joined with a comma. Edit only line 1; leave lines 2-3
   untouched.
3. Inject guidance into \`$dir/CLAUDE.md\`: replace the block between
   \`<!-- aictx:type-guidance START -->\` and \`<!-- aictx:type-guidance END -->\`
   with the verbatim contents of \`$types_dir/<type>.md\` (plus
   \`$types_dir/incubating.md\` if incubating). If \`CLAUDE.md\` is missing, copy
   \`$template/CLAUDE.md\` there first; if the markers are absent, append them.

Edit files directly; print only a one-line summary.
EOF
)
        ( cd "$root" && claude --model sonnet --permission-mode acceptEdits \
            --allowedTools "Read Glob Grep Edit Write Bash(cp:*) Bash(ls:*) Bash(find:*) Bash(cat:*) Bash(date:*)" \
            -p "$prompt" >&2 ) || true
    }

    # Execute a previously-proposed split (propose-then-confirm). Reads the
    # SPLIT-SUGGESTED block in the chat's parts.md and performs the moves +
    # bookkeeping in the foreground. Run it after the chat has ended.
    aictx-split() {
        local slug=${1:-}
        slug=${slug%/}; slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local dir="$root/$slug"
        local rules="$HOME/.config/aictx/parts-rules.md"
        local template="${AICTX_TEMPLATE:-$HOME/.config/aictx/template}"
        if [ -z "$slug" ] || [ ! -d "$dir" ]; then
            echo "usage: aictx-split <existing-slug>" >&2; return 1
        fi
        [ -r "$dir/parts.md" ] && grep -q '^## SPLIT-SUGGESTED' "$dir/parts.md" || {
            echo "aictx-split: no SPLIT-SUGGESTED block in $slug/parts.md" >&2; return 1; }
        [ -r "$rules" ] || { echo "missing rules: $rules" >&2; return 1; }

        local overview; overview=$(__aictx_overview)

        local prompt
        prompt=$(cat <<EOF
You are executing a previously-proposed split of an aictx chat — the user ran
\`aictx-split $slug\` to confirm it.

**Parent chat:** \`$slug\` (directory: \`$dir\`)
**Template to copy for each child:** \`$template\`
**Workspace root:** \`$root\`

## Rules

$(cat "$rules")

## Parent parts.md (contains the SPLIT-SUGGESTED block to execute)

$(cat "$dir/parts.md")

## Existing slugs (avoid collisions)

$overview

## Task

Execute the SPLIT-SUGGESTED block per the "Executing a split" rules: create
each child chat from the template, move the listed parts' files (closed parts
travel with their cluster), write bookkeeping on both sides (\`origin:\` in each
child, \`## Splits\` in the parent), and remove the SPLIT-SUGGESTED block. Print
a short report of what you did.
EOF
)
        # Inventory the parent's content hashes (they must still exist somewhere
        # after the moves) for the post-op integrity check.
        local before; before=$(__aictx_content_hashes "$dir")

        ( cd "$root" && claude --model sonnet --permission-mode acceptEdits \
            --allowedTools "Read Glob Grep Edit Write Bash(cp:*) Bash(mkdir:*) Bash(mv:*) Bash(ls:*) Bash(find:*) Bash(cat:*) Bash(date:*) Bash(basename:*) Bash(dirname:*)" \
            -p "$prompt" >&2 ) || true
        __aictx_check_integrity aictx-split "$before"
    }

    # Execute a previously-proposed merge (propose-then-confirm). Reads the
    # MERGE-SUGGESTED block in the chat's parts.md, folds the absorbed sibling
    # chats into the target, archives the absorbed chats, and writes bookkeeping
    # — in the foreground. Run it after the chat has ended.
    aictx-merge() {
        local slug=${1:-}
        slug=${slug%/}; slug=${slug##*/}
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local dir="$root/$slug"
        local rules="$HOME/.config/aictx/parts-rules.md"
        local template="${AICTX_TEMPLATE:-$HOME/.config/aictx/template}"
        if [ -z "$slug" ] || [ ! -d "$dir" ]; then
            echo "usage: aictx-merge <existing-slug>" >&2; return 1
        fi
        [ -r "$dir/parts.md" ] && grep -q '^## MERGE-SUGGESTED' "$dir/parts.md" || {
            echo "aictx-merge: no MERGE-SUGGESTED block in $slug/parts.md" >&2; return 1; }
        [ -r "$rules" ] || { echo "missing rules: $rules" >&2; return 1; }

        local overview; overview=$(__aictx_overview)

        local prompt
        prompt=$(cat <<EOF
You are executing a previously-proposed merge of aictx chats — the user ran
\`aictx-merge $slug\` to confirm it.

**Chat holding the proposal:** \`$slug\` (directory: \`$dir\`)
**Template (if the target is a new slug):** \`$template\`
**Workspace root:** \`$root\`

## Rules

$(cat "$rules")

## parts.md (contains the MERGE-SUGGESTED block to execute)

$(cat "$dir/parts.md")

## Existing slugs

$overview

## Task

Execute the MERGE-SUGGESTED block per the "Executing a merge" rules: move the
absorbed chats' content into the target (whole files, unchanged), fold in their
parts, archive each absorbed chat (\`archived\` tag + \`successor:\`), write the
target's \`## Merged-in\` bookkeeping, and remove the MERGE-SUGGESTED block.
Print a short report.
EOF
)
        # No content-hash integrity check here: a merge intentionally rewrites
        # the target to integrate the fork, so "content unchanged" is the wrong
        # invariant. No-information-loss is enforced by the prompt + your review.
        ( cd "$root" && claude --model sonnet --permission-mode acceptEdits \
            --allowedTools "Read Glob Grep Edit Write Bash(cp:*) Bash(mkdir:*) Bash(mv:*) Bash(ls:*) Bash(find:*) Bash(cat:*) Bash(date:*) Bash(basename:*) Bash(dirname:*)" \
            -p "$prompt" >&2 ) || true
    }

    # True (0) if a chat is an abandoned empty shell safe to delete: never
    # conversed (no transcript), no durable content files, an untouched
    # boilerplate README, and created more than 5 days ago (per the .aictx
    # creation-date tag). Strict on purpose — anything with history or content
    # fails the test.
    __aictx_empty_stale() {
        local cdir=${1%/} proj l1 created cre age
        [ -e "$cdir/.aictx" ] || return 1
        proj="$HOME/.claude/projects/${cdir//\//-}"
        find "$proj" -maxdepth 1 -name '*.jsonl' -print -quit 2>/dev/null | grep -q . && return 1
        find "$cdir" -type f ! -name .aictx ! -name CLAUDE.md ! -name parts.md ! -name README.md \
            -print -quit 2>/dev/null | grep -q . && return 1
        { [ -f "$cdir/README.md" ] && grep -q '(no topic files yet)' "$cdir/README.md"; } || return 1
        { IFS= read -r l1; } < "$cdir/.aictx" || return 1
        created=${l1%% *}
        cre=$(date -d "$created" +%s 2>/dev/null) || return 1
        age=$(( ( $(date +%s) - cre ) / 86400 ))
        [ "$age" -gt 5 ]
    }

    # On-demand sweep over every non-archived chat: delete abandoned empty shells
    # (>5 days, no history/content), then backfill the type: tag (if untyped) and
    # (re)evaluate parts — the cross-chat complement to the per-exit pass (which
    # only sees chats you open). The classify/parts steps are gated (skip typed /
    # unchanged), so the first run does the work and later runs are cheap. Run it
    # periodically. Pass "force" to re-evaluate parts even for unchanged chats
    # (e.g. after editing parts-rules.md) — classify still skips already-typed.
    aictx-parts-sweep() {
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}" d slug tags
        local force=""; [ "${1:-}" = force ] && force=force
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            [ -e "$d/.aictx" ] || continue
            tags=""; { IFS= read -r tags; } < "$d/.aictx" 2>/dev/null || true
            [[ " $tags " == *" archived "* ]] && continue   # skip archived
            slug=$(basename "$d")
            if __aictx_empty_stale "$d"; then
                printf 'aictx: deleting empty shell %s (no history/content, >5d old)\n' "$slug" >&2
                rm -rf "${d%/}"
                continue
            fi
            __aictx_classify_type "$slug"
            __aictx_eval_parts "$slug" "$force"
        done
        printf 'aictx-parts-sweep: done.\n' >&2
    }

    # Resume each non-archived chat that has prior conversation but no durable
    # content files, and have it externalise its knowledge into files — because a
    # content-less chat means its important info lives only in the transcript.
    # In the same resumed session it also classifies the type, sets up CLAUDE.md
    # (template + the matching type-guidance fragment), and tags .aictx, so the
    # files are written under the right guidance. Foreground, idempotent (a chat
    # that gains files is skipped next time). Run on demand; then re-run the
    # sweep for parts. No stdout.
    aictx-backfill-files() {
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        local types_dir="$HOME/.config/aictx/types"
        local template="${AICTX_TEMPLATE:-$HOME/.config/aictx/template}"
        local d tags cdir slug proj prompt
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            [ -e "$d/.aictx" ] || continue
            tags=""; { IFS= read -r tags; } < "$d/.aictx" 2>/dev/null || true
            [[ " $tags " == *" archived "* ]] && continue
            # Skip if it already has durable content files.
            find "$d" -type f ! -name .aictx ! -name CLAUDE.md ! -name parts.md ! -name README.md \
                -print -quit 2>/dev/null | grep -q . && continue
            cdir=${d%/}; slug=$(basename "$cdir")
            proj="$HOME/.claude/projects/${cdir//\//-}"
            # Need a prior transcript to resume; without one there's no memory to externalise.
            find "$proj" -maxdepth 1 -name '*.jsonl' -print -quit 2>/dev/null | grep -q . || {
                printf 'aictx: %s has no transcript to resume — skipping\n' "$slug" >&2; continue; }

            printf 'aictx: backfilling files for %s …\n' "$slug" >&2
            prompt=$(cat <<EOF
This chat's important information lives only in this conversation, not in files.
Fix that — and set up the chat's type guidance while you have the full context.

- Type taxonomy: read \`$types_dir/README.md\`.
- Per-type guidance fragments: \`$types_dir/<type>.md\`.
- Template (for a missing CLAUDE.md): \`$template\`.

Do, in order:

1. Classify this chat's type from the conversation, using the taxonomy: one of
   tool / concept / workflow / project / reference (+ stage:incubating if apt).
2. Set up \`./CLAUDE.md\`: if missing, copy \`$template/CLAUDE.md\` to it. Then
   replace the block between \`<!-- aictx:type-guidance START -->\` and
   \`<!-- aictx:type-guidance END -->\` with the verbatim contents of
   \`$types_dir/<type>.md\` (plus \`$types_dir/incubating.md\` if incubating).
3. Append \`type:<kind>\` (and \`stage:incubating\` if apt) to \`.aictx\` line 1
   as new space-separated tags — single spaces, never commas. Edit only line 1.
4. Write the durable knowledge into files, following \`./CLAUDE.md\` (now carrying
   the type guidance) and \`../CLAUDE.md\`: one topic per file with a fitting
   name; capture the conclusions, decisions, facts, and working examples worth
   keeping; bias what you record per the type guidance; keep README.md's file
   list in sync.

The files are the source of truth — the transcript is only supplementary
history. Only write what the conversation actually established; don't invent. If
there is genuinely nothing durable to record, still do steps 1-3, but make no
topic files.
EOF
)
            ( cd "$cdir" && claude -c --model sonnet -p "$prompt" --permission-mode acceptEdits \
                --allowedTools "Read Write Edit Glob Grep Bash(cp:*) Bash(ls:*) Bash(cat:*) Bash(find:*)" >&2 ) || true
        done
        printf 'aictx-backfill-files: done.\n' >&2
    }

    # Remove a SPLIT/MERGE-SUGGESTED block from a parts.md (drop lines from the
    # `## …-SUGGESTED` header until the next `## ` heading, eval marker, or EOF).
    __aictx_strip_proposal() {
        local f=$1 tmp
        [ -f "$f" ] || return 0
        tmp=$(mktemp)
        awk '
            /^## (MERGE|SPLIT)-SUGGESTED/ { skip=1; next }
            skip && (/^## / || /^<!-- parts-eval/) { skip=0 }
            !skip
        ' "$f" > "$tmp" && mv "$tmp" "$f"
    }

    # Dismiss a proposal: strip its block and stamp a cooldown marker, so no new
    # split/merge proposal is made for this chat until it has been activated 5
    # more days (the `used` count). $1 is the chat dir.
    __aictx_mark_dismissed() {
        local dir=$1 parts used tmp
        parts="$dir/parts.md"
        __aictx_strip_proposal "$parts"
        [ -f "$parts" ] || return 0
        used=$(__aictx_used "$dir")
        tmp=$(mktemp)
        { grep -v '<!-- proposal-dismissed:' "$parts"; printf '<!-- proposal-dismissed: used=%s -->\n' "$used"; } > "$tmp"
        mv "$tmp" "$parts"
    }

    # Run one chat's pending proposal — merge or split, whichever block it holds.
    # If the proposal block is still present afterwards, the agent didn't
    # complete the work; surface that clearly so the entry doesn't quietly
    # resurface in the picker as if nothing happened.
    __aictx_run_proposal() {
        local dir=$1 slug kind=""
        slug=$(basename "$dir")
        if grep -q '^## MERGE-SUGGESTED' "$dir/parts.md" 2>/dev/null; then
            kind=MERGE
            aictx-merge "$slug"
        elif grep -q '^## SPLIT-SUGGESTED' "$dir/parts.md" 2>/dev/null; then
            kind=SPLIT
            aictx-split "$slug"
        fi
        if [ -n "$kind" ] && grep -q "^## ${kind}-SUGGESTED" "$dir/parts.md" 2>/dev/null; then
            printf '\n\e[31maictx-review: %s incomplete on %s — %s-SUGGESTED block still in parts.md.\e[0m\n' \
                "${kind,,}" "$slug" "$kind" >&2
            printf 'Inspect %s/parts.md and re-run, or edit/dismiss the proposal.\n' "$dir" >&2
            printf '(Press Enter to continue)' >&2
            read -r _ </dev/tty || true
        fi
    }

    # Interactive review of pending split/merge proposals across all chats.
    # Lists each non-archived chat carrying a SPLIT/MERGE-SUGGESTED block; the
    # preview shows its parts.md. Per item: enter = run it, e = edit the block,
    # x = dismiss (+5-activation-day cooldown); ctrl-a = run all remaining (one
    # confirm); esc = quit. Loops until none left.
    aictx-review() {
        local root="${AICTX_ROOT:-$HOME/Documents/aictx}"
        command -v fzf >/dev/null 2>&1 || { echo "aictx-review: fzf not in PATH" >&2; return 1; }
        while :; do
            local list f d s tags
            list=$(
                for f in "$root"/*/parts.md; do
                    [ -e "$f" ] || continue
                    d=$(dirname "$f"); s=$(basename "$d")
                    tags=""; { IFS= read -r tags; } < "$d/.aictx" 2>/dev/null || true
                    [[ " $tags " == *" archived "* ]] && continue
                    if grep -q '^## MERGE-SUGGESTED' "$f"; then printf '%s\t\e[33mmerge\e[0m\n' "$s"
                    elif grep -q '^## SPLIT-SUGGESTED' "$f"; then printf '%s\t\e[36msplit\e[0m\n' "$s"; fi
                done
            )
            [ -z "$list" ] && { echo "aictx-review: no pending proposals." >&2; return 0; }
            local out key sel slug
            out=$(printf '%s\n' "$list" | fzf --ansi --delimiter=$'\t' --with-nth=2,1 \
                --preview "cat '$root'/{1}/parts.md" --preview-window=right:55% \
                --header $'enter: run  ·  e: edit  ·  x: dismiss (+cooldown)\nctrl-a: run all  ·  esc: quit' \
                --expect=enter,e,x,ctrl-a,esc) || return 0
            key=$(printf '%s\n' "$out" | head -n1)
            sel=$(printf '%s\n' "$out" | sed -n '2p')
            slug=$(printf '%s' "$sel" | cut -f1)
            case "$key" in
                ""|esc) return 0 ;;
                e) [ -n "$slug" ] && "${EDITOR:-vi}" "$root/$slug/parts.md" ;;
                x) [ -n "$slug" ] && __aictx_mark_dismissed "$root/$slug" ;;
                enter) [ -n "$slug" ] && __aictx_run_proposal "$root/$slug" ;;
                ctrl-a)
                    local -a slugs=(); local s2
                    while IFS= read -r s2; do s2=${s2%%$'\t'*}; [ -n "$s2" ] && slugs+=("$s2"); done <<< "$list"
                    printf 'aictx-review: run all %s remaining proposal(s)? [y/N] ' "${#slugs[@]}" >/dev/tty
                    local ans=""; read -r ans </dev/tty || true
                    [ "$ans" = y ] || continue
                    for s2 in "${slugs[@]}"; do __aictx_run_proposal "$root/$s2"; done
                    ;;
            esac
        done
    }
fi
