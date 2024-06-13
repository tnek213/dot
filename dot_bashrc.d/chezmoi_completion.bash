# Add completion if not already set by package installation

if ! declare -F | grep -q "__chezmoi"; then
	source <(chezmoi completion bash)
fi
