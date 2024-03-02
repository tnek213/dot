#!/usr/bin/env bash

if [[ -n "${CHEZMOI_HIDDEN_FILENAMES-}" ]]; then
	exit 0
fi

set -euo pipefail
shopt -s nullglob

export CHEZMOI_HIDDEN_FILENAMES=1

hook_state=$(mktemp -u "/tmp/chezmoi-hook-XXXXXX")
mock_source=$(mktemp -u "/tmp/chezmoi-hook-XXXXXX")
trap 'rm -rf "$hook_state" "$mock_source"' EXIT

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

# alt_path(kind, cur): probe whether the real source dir already has
# something that maps to the same chezmoi *target* as the literal path
# `cur` (e.g. cur="dot_config/foo" might match an existing
# "dot_config/private_foo"). Returns the absolute existing source path,
# or empty if no such mapping exists.
#
# Mechanism: create an empty mock file/dir under $mock_source at the
# literal path, ask chezmoi (-S $mock_source) what target that maps to,
# then ask the real chezmoi source-path of that target.
alt_path() (
	kind="$1"
	cur="$2"
	mock="$mock_source/$cur"

	trap '(cd "$mock_source" && rm -rf "${cur%%/*}")' EXIT

	if [[ "$kind" == "dir" ]]; then
		mkdir -p "$mock"
	elif [[ "$kind" == "file" ]]; then
		mkdir -p "$(dirname "$mock")"
		: >"$mock"
	else
		echo "alt_path: kind must be 'dir' or 'file', got: $kind" >&2
		return 2
	fi

	resolved_target="$(_chezmoi -S "$mock_source" target-path "$mock")"
	alt="$(_chezmoi source-path "$resolved_target" 2>/dev/null)" || true

	echo "$alt"
	[[ -n "$alt" ]]
)

# resolve_source(dst): resolve a logical dst (e.g.
# "/dot_config/foo/bar/encrypted_baz") into the actual source-relative
# path to use, honoring any existing chezmoi-prefixed ancestor in the
# source dir. Walks up from leaf to root using alt_path; if an existing
# ancestor uses a different prefix than the literal one (e.g.
# "dot_config/private_foo" already exists for literal "dot_config/foo"),
# prints a warning and reuses it instead of creating a duplicate that
# would resolve to the same target. mkdirs any genuinely-missing
# intermediate dirs and records them in .git/info/exclude so the outer
# loop re-emits them to exclude.next.
resolve_source() (
	dst="$1"
	rel="${dst#/}"
	src_root="$(_chezmoi source-path)"

	# Walk up: probe leaf as a file, ancestors as dirs.
	remaining=()
	probe="$rel"
	kind="file"
	found=""
	while [[ -n "$probe" ]]; do
		found="$(alt_path "$kind" "$probe")" || true
		[[ -n "$found" ]] && break
		kind="dir"
		remaining=("${probe##*/}" "${remaining[@]}")
		if [[ "$probe" == */* ]]; then
			probe="${probe%/*}"
		else
			probe=""
		fi
	done

	src_rel=""
	if [[ -n "$found" ]]; then
		if [[ ${#remaining[@]} -gt 0 ]] && [[ ! -d "$found" ]]; then
			echo "resolve_source: ancestor of $dst is not a directory: $found" >&2
			exit 1
		fi
		src_rel="${found#"$src_root"/}"
		[[ "$src_rel" == "$found" ]] && src_rel=""

		literal="$src_root/$probe"
		if [[ "$found" != "$literal" ]]; then
			echo "warning: $dst overlays existing source path ${found#"$src_root"/} (literal would be $probe); reusing existing path" >&2
		fi
	fi

	# Append remaining components; mkdir each new intermediate dir and
	# add it to .git/info/exclude. The leaf itself is left untouched
	# (the caller hardlinks it).
	n=${#remaining[@]}
	for ((i = 0; i < n; i++)); do
		src_rel="${src_rel:+$src_rel/}${remaining[i]}"
		if (( i < n - 1 )) && [[ ! -d "$src_root/$src_rel" ]]; then
			mkdir "$src_root/$src_rel"
			echo "/$src_rel/" >>"$src_root/.git/info/exclude"
		fi
	done

	echo "$src_rel"
)

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

	# Resolve dst to an actual source-relative path. resolve_source
	# reuses any existing differently-prefixed ancestor (with warning)
	# and mkdirs / records exclude entries for new intermediates.
	src_rel="$(resolve_source "$dst")"
	dst_repo_rel="./$src_rel"

	# Walk up the resolved path emitting exclude.next entries for each
	# hook-owned ancestor (now visible in .git/info/exclude either from
	# a prior run or from resolve_source above).
	ancestor="${dst_repo_rel%/*}"
	while [[ "$ancestor" != "." && -n "$ancestor" ]]; do
		excl_line="${ancestor#.}/"
		if grep -qxF -- "$excl_line" .git/info/exclude 2>/dev/null; then
			echo "$excl_line" >>.git/info/exclude.next
		else
			break
		fi
		ancestor="${ancestor%/*}"
	done

	cryptfile_yaml="$CRYPT/.chezmoidata/$cryptfile_id.yaml"

	echo -e "'crypt':\n  '$cryptfile_id':" >"$cryptfile_yaml"

	echo "    'src': '$src'" >>"$cryptfile_yaml"
	echo "    'dst': '$dst'" >>"$cryptfile_yaml"

	echo "/$src_rel" >>.git/info/exclude
	echo "/$src_rel" >>.git/info/exclude.next

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

	if [[ "$obsolete_entry" == */ ]]; then
		rmdir "${obsolete_entry_repo_rel%/}" 2>/dev/null \
			|| echo "warning: not removing non-empty ${obsolete_entry_repo_rel%/}" >&2
	else
		rm -f "$obsolete_entry_repo_rel"
	fi
done < <(
	LC_ALL=C comm -13 <(echo "$nxt_git_exclude") <(echo "$cur_git_exclude") \
		| awk '{ print length, $0 }' | LC_ALL=C sort -rn | cut -d' ' -f2-
)

mv .git/info/exclude.next .git/info/exclude
