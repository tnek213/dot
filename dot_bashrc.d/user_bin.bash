# shellcheck disable=SC2076
if [[ ! $PATH =~ "$HOME/bin" ]]; then
	export PATH="$HOME/bin:$PATH"
fi
