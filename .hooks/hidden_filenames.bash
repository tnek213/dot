#!/usr/bin/env bash

if [[ -n "${CHEZMOI_HIDDEN_FILENAMES-}" ]]; then
	exit 0
fi

set -euo pipefail
shopt -s nullglob

export CHEZMOI_HIDDEN_FILENAMES=1

hook_state=$(mktemp -u "/tmp/chezmoi-hook-XXXXXX")
trap 'rm -rf "$hook_state"' EXIT

_chezmoi() {
	command chezmoi --persistent-state "$hook_state" "$@"
}

cd "$(_chezmoi source-path)" || exit 1

CRYPT="crypt"

same_inode() {
	[[ "$(stat -c '%d:%i' -- "$1")" == "$(stat -c '%d:%i' -- "$2")" ]]
}

effective_lines() {
	(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$1" || echo "") | LC_ALL=C sort -u
}

rm -f .git/info/exclude.next
rm -rf "$CRYPT/.chezmoidata/" && mkdir "$CRYPT/.chezmoidata/"

for cryptfile_config in "$CRYPT"/*.yaml.age; do
	cryptfile_id="$(basename "${cryptfile_config%.yaml.age}")"
	cryptfile_data="$CRYPT/${cryptfile_id}.age"

	[[ -f "$cryptfile_data" ]] || {
		echo "Missing data for $cryptfile_config: $cryptfile_data" >&2
		exit 1
	}

	meta="$(
		declare -A least=()
		least["dst"]=1
		least["remoteUrlPattern"]=0
		least["remoteUrlPattern1"]=0
		least["remoteUrlPattern2"]=0
		least["remoteUrlPattern3"]=0

		while IFS= read -r line; do
			if [[ "$line" =~ ^[[:space:]]*$ ]]; then
				continue
			elif [[ "$line" =~ ^([a-zA-Z0-9]+):\ *(.*)$ ]]; then
				name="${BASH_REMATCH[1]}"

				value="${BASH_REMATCH[2]}"
				if [[ $value =~ ^\"(.*)\"$ ]]; then
					value="${BASH_REMATCH[1]}"
				fi
				value="\"$value\""

				echo "$name=$value"
				if [[ ${least["$name"]+x} ]]; then
					least["$name"]=$((${least["$name"]} - 1))
				else
					echo "Unknown variable in $cryptfile_config: $name" >&2
					exit 1
				fi
			else
				echo "Invalid line in $cryptfile_config: $line" >&2
				exit 1
			fi

			for key in "${!least[@]}"; do
				if [[ ${least["$key"]} -gt 0 ]]; then
					echo "Missing variable in $cryptfile_config: $key" >&2
					exit 1
				fi
			done
		done < <(_chezmoi --use-builtin-age=on decrypt "$cryptfile_config")
	)"

	src="$cryptfile_data"
	dst=
	remoteUrlPattern=
	remoteUrlPattern1=
	remoteUrlPattern2=
	remoteUrlPattern3=

	eval "$meta"

	if [[ "$dst" != /* ]] || [[ "$dst" =~ /\.\.?/ ]]; then
		echo "dst must be an absolute path without .. or . components in $cryptfile_config: $dst" >&2
		exit 1
	fi

	dst_repo_rel=".$dst"

	if [[ ! -d "${dst_repo_rel%/*}" ]]; then
		echo "dst directory does not exist for $cryptfile_config: $dst" >&2
		exit 1
	fi

	cryptfile_yaml="$CRYPT/.chezmoidata/$cryptfile_id.yaml"

	echo -e "'crypt':\n  '$cryptfile_id':" >"$cryptfile_yaml"

	echo "    'src': '$src'" >>"$cryptfile_yaml"
	echo "    'dst': '$dst'" >>"$cryptfile_yaml"

	echo "$dst" >>.git/info/exclude
	echo "$dst" >>.git/info/exclude.next

	if [ -e "$dst_repo_rel" ]; then
		if ! same_inode "$dst_repo_rel" "$src"; then
			# Keep the newer file
			if [[ "$src" -nt "$dst_repo_rel" ]]; then
				ln -f "$src" "$dst_repo_rel"
			else
				ln -f "$dst_repo_rel" "$src"
			fi
		fi
	else
		ln "$src" "$dst_repo_rel"
	fi

	target_path="$(_chezmoi target-path "$dst_repo_rel")"
	target_path=${target_path#"${HOME%/}/"}
	echo "    'targetPath': '$target_path'" >>"$cryptfile_yaml"
	[[ -n "$remoteUrlPattern" ]] && echo "    'remoteUrlPattern': '$remoteUrlPattern'" >>"$cryptfile_yaml"
	[[ -n "$remoteUrlPattern1" ]] && echo "    'remoteUrlPattern1': '$remoteUrlPattern1'" >>"$cryptfile_yaml"
	[[ -n "$remoteUrlPattern2" ]] && echo "    'remoteUrlPattern2': '$remoteUrlPattern2'" >>"$cryptfile_yaml"
	[[ -n "$remoteUrlPattern3" ]] && echo "    'remoteUrlPattern3': '$remoteUrlPattern3'" >>"$cryptfile_yaml"

done

cur_git_exclude="$(effective_lines .git/info/exclude)"
nxt_git_exclude="$(effective_lines .git/info/exclude.next)"

while IFS= read -r obsolete_entry; do
	if [[ -z "$obsolete_entry" ]]; then
		continue
	fi

	obsolete_entry_repo_rel=".$obsolete_entry"

	rm -f "$obsolete_entry_repo_rel"
done < <(comm -13 <(echo "$nxt_git_exclude") <(echo "$cur_git_exclude"))

mv .git/info/exclude.next .git/info/exclude
