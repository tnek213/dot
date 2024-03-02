# Add completion if not already set by package installation

if ! declare -F | grep -q "__chezmoi"; then
	eval "$(chezmoi completion bash)"
fi
