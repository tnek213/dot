function unison() {
	command unison --diff 'diff = code --diff %1 %2' "$@" --merge = code --wait '%1'
}
