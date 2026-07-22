
# AlmaLinux

dnf install -y epel-release

# Debian

Debian dependencies:

apt-get install -y --no-install-recommends ovmf uml-utilities genisoimage qemu-utils
apt-get install -y --no-install-recommends qemu-system-x86 qemu-kvm

# to run arm64 images:
apt-get install -y --no-install-recommends qemu-efi-aarch64

usermod -aG kvm masterapp

ip tuntap add dev tap0 mode tap
ip link set dev tap0 master br0
ip link set tap0 up
