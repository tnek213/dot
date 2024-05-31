# Needs Starship: https://starship.rs/
if command -v starship &>/dev/null; then
	__BASHRC_PHASE_PARALLEL_SOURCE_ADD 'starship init bash'
fi
