#!/bin/sh
# Post-processing for aictx-tidy: extract renames from the current run,
# append them to renames.log, prune to last 30 days, then fold current.log
# into last-run.log.
set -eu

state="${1:?state dir required}"
today=$(date +%F)
cutoff=$(date -d '30 days ago' +%F)

if [ -s "$state/current.log" ]; then
    awk -v d="$today" '
        /^[[:space:]]+[a-z0-9-]+ -> [a-z0-9-]+[[:space:]]*$/ {
            printf "%s\t%s\t%s\n", d, $1, $3
        }
    ' "$state/current.log" >> "$state/renames.log" || true
fi

if [ -s "$state/renames.log" ]; then
    awk -v c="$cutoff" '$1 >= c' "$state/renames.log" > "$state/renames.log.tmp" \
        && mv "$state/renames.log.tmp" "$state/renames.log"
fi

if [ -f "$state/current.log" ]; then
    cat "$state/current.log" >> "$state/last-run.log"
    rm -f "$state/current.log"
fi
