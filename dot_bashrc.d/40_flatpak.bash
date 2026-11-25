for flatpak_bin in "$HOME/.local/share/flatpak/exports/bin" /var/lib/flatpak/exports/bin; do
	if [ -d "$flatpak_bin" ] && [[ ! $PATH =~ "$flatpak_bin" ]]; then
		export PATH="$flatpak_bin:$PATH"
	fi
done
