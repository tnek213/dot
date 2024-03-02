if command -v virsh &>/dev/null; then
	export LIBVIRT_DEFAULT_URI=qemu:///system
fi
