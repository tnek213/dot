if command -v vboxmanage >/dev/null; then
	alias ubse-start='vboxmanage startvm --type=headless ubse'
fi
