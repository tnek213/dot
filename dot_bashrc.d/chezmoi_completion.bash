# Add completion if not already set by package installation

if ! declare -F | grep -q "__chezmoi"; then
	__BASHRC_PHASE_PARALLEL_SOURCE_ADD 'chezmoi completion bash'
fi
