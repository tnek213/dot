if [ -d "$HOME/.opencode/bin" ] && [[ ! $PATH =~ "$HOME/.opencode/bin" ]]; then
	export PATH="$HOME/.opencode/bin:$PATH"
fi
