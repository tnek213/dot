#!/bin/sh
# Daily aictx slug-tidy runner. Filters eligible candidates in shell, then
# hands a focused prompt (shared rules + candidate buckets + budgets) to
# Claude. Output goes to stdout; the caller redirects to current.log.
set -eu

state="${1:?state dir required}"
root="$HOME/Documents/aictx"
uses_dir="$HOME/.config/systemd/user/aictx-tidy-uses"
rules_file="$uses_dir/prompt.md"

last=""
[ -r "$root/.last" ] && IFS= read -r last < "$root/.last" || true

# Names that have been the *destination* of a rename in the last 30 days.
# renames.log is already pruned to that window by post.sh.
recent_renamed=""
if [ -r "$state/renames.log" ]; then
    recent_renamed=$(awk -F'\t' '{print $3}' "$state/renames.log" | sort -u)
fi

is_recent() {
    [ -z "$recent_renamed" ] && return 1
    printf '%s\n' "$recent_renamed" | grep -qxF "$1"
}

bucket_normal=""
bucket_recent=""
examined=0

for d in "$root"/*/; do
    [ -d "$d" ] || continue
    slug=$(basename "$d")
    [ -e "$d/.aictx" ] || continue
    [ "$slug" = "$last" ] && continue
    # Skip if any file under the chat dir has mtime within the last 8 hours.
    if find "$d" -mmin -480 -type f -print 2>/dev/null | head -n1 | grep -q .; then
        continue
    fi
    examined=$((examined + 1))
    if is_recent "$slug"; then
        bucket_recent="${bucket_recent}${bucket_recent:+
}- $slug"
    else
        bucket_normal="${bucket_normal}${bucket_normal:+
}- $slug"
    fi
done

[ -z "$bucket_normal" ] && bucket_normal="(none)"
[ -z "$bucket_recent" ] && bucket_recent="(none)"

# Workspace overview: every chat slug + line-2 summary, for disambiguation.
overview=""
for d in "$root"/*/; do
    [ -d "$d" ] || continue
    [ -e "$d/.aictx" ] || continue
    s=$(basename "$d")
    summary=""
    { IFS= read -r _; IFS= read -r summary; } < "$d/.aictx" || true
    overview="${overview}${overview:+
}- $s — ${summary:-(no summary)}"
done

prompt=$(cat <<EOF
You are doing the daily aictx slug-tidy batch. Per-slug eligibility was
already filtered in shell (skipped: \`.last\`, dirs without \`.aictx\`,
chats with file mtime within the last 8 hours). Your only job is the
slug-quality judgement and the rename itself.

## Rules

The shared slug-tidy rules — read in full:

$(cat "$rules_file")

## Workspace conventions

Also read \`$root/CLAUDE.md\` if it adds anything not covered above.

## Workspace overview

Every existing chat slug, with its one-line summary — use this to avoid
picking a new slug that's ambiguous with or duplicates an existing one,
even if the names differ literally:

$overview

## Candidates

**Not renamed in the last 30 days** ($(printf '%s' "$bucket_normal" | grep -c '^- ' || echo 0) chats):

$bucket_normal

**Renamed in the last 30 days** ($(printf '%s' "$bucket_recent" | grep -c '^- ' || echo 0) chats — apply a higher bar; these were the destination of a previous rename, so re-renaming risks ping-ponging):

$bucket_recent

For each candidate you actually consider renaming, read its context per
the "Reading context for a candidate" section in the rules.

## Volume cap

At most **10 renames total** in this run, at most **5** of which may
come from the "renamed in the last 30 days" bucket. Pick the candidates
where the new slug is most clearly better; borderline → skip. The job
retries daily, so leftover candidates get a fresh look tomorrow.

## Output

Print one short report to stdout in this exact shape:

\`\`\`
examined=$examined  renamed=<M>  skipped=<K>
  <old-slug> -> <new-slug>
    <one short sentence on why this rename was clearly better>
  ...
\`\`\`

If M=0, write \`no renames this run\` and exit. Don't list skipped chats
individually — only the count.
EOF
)

exec claude --model sonnet --permission-mode acceptEdits \
    --allowedTools "Read Glob Grep Edit Bash(claude-project move:*) Bash(ls:*) Bash(find:*) Bash(stat:*) Bash(cat:*) Bash(date:*) Bash(pwd:*) Bash(command:*)" \
    -p "$prompt"
