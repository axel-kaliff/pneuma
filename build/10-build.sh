#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# Base is bluefin-lts (CentOS Stream 10), which already provides: brew (with
# first-boot setup + PATH plumbing), flatpak preinstall infra, ujust, uupd
# auto-updates, tailscale, firewalld, fwupd, zram, GNOME + GDM. This script
# only layers what the base does NOT provide. CentOS Stream 10 is dnf4-only.
###############################################################################

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: RPMDB Copy-Up"

# rpm's sqlite database uses mmap; when the db still lives in an overlayfs
# lower layer, the first dnf write yields "database disk image is malformed".
# Force a full copy-up of the db directory before any transaction. This RUN
# layer executes every numbered build script, so one copy-up covers them all.
RPMDB_DIR="$(rpm --eval '%_dbpath')"
cp -a "${RPMDB_DIR}" "${RPMDB_DIR}.copyup"
rm -rf "${RPMDB_DIR}"
mv "${RPMDB_DIR}.copyup" "${RPMDB_DIR}"
rpm -q bash >/dev/null

echo "::endgroup::"

echo "::group:: Repo State (EPEL + CRB)"

# bluefin-lts pulls from EPEL 10 at build time; assert the repos are available
# for our own layers too (idempotent if the base already ships them).
rpm -q epel-release >/dev/null 2>&1 || dnf -y install epel-release
dnf config-manager --set-enabled crb

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Brewfiles: the base's brew-preinstall user service installs every Brewfile in
# preinstall.d/ at first login (ublue brew infra) — no custom service needed.
mkdir -p /usr/share/ublue-os/homebrew/preinstall.d/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/preinstall.d/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Flatpaks: generate a preinstall file for the base's flatpak-preinstall.service
# (flatpak preinstall reads /usr/share/flatpak/preinstall.d/). Removing an app
# from install.list later may deinstall it from users' systems on upgrade.
mkdir -p /usr/share/flatpak/preinstall.d
{
    while IFS= read -r app; do
        app="${app%%#*}"
        app="${app//[[:space:]]/}"
        [ -z "${app}" ] && continue
        printf '[Flatpak Preinstall %s]\nBranch=stable\nIsRuntime=false\n\n' "${app}"
    done </ctx/custom/flatpaks/install.list
} >/usr/share/flatpak/preinstall.d/pneuma.preinstall
systemctl enable flatpak-preinstall.service

# Copy Quadlet container definitions
mkdir -p /usr/share/pneuma
cp -r /ctx/build/files/usr/share/pneuma/quadlets /usr/share/pneuma/quadlets

echo "::endgroup::"

echo "::group:: Install Packages"

# Only what the base doesn't carry. gum is required by the default ujust
# recipes; plymouth-plugin-script + -label render the Pneuma boot theme
# (script 40): the script plugin runs it, the label plugin draws Image.Text.
dnf -y install \
    git \
    gum \
    tmux \
    wl-clipboard \
    plymouth-plugin-script \
    plymouth-plugin-label

echo "::endgroup::"

echo "::group:: Install Pneuma Setup Scripts"

# Install rebase-safe setup scripts and services
install -Dm755 /ctx/build/files/usr/libexec/pneuma-user-setup /usr/libexec/pneuma-user-setup
install -Dm644 /ctx/build/files/usr/lib/systemd/system/pneuma-user-setup.service /usr/lib/systemd/system/pneuma-user-setup.service

# Update badge: maintain /run/pneuma/update-staged after the base's uupd
# auto-update stages a bootc deployment (read by omarchy-update-available).
install -Dm755 /ctx/build/files/usr/libexec/pneuma-update-flag /usr/libexec/pneuma-update-flag
test -f /usr/lib/systemd/system/uupd.service
mkdir -p /usr/lib/systemd/system/uupd.service.d
cat > /usr/lib/systemd/system/uupd.service.d/50-pneuma-update-flag.conf << 'EOF'
# Installed by pneuma (build/10-build.sh): refresh the staged-update flag the
# Omarchy bar's update badge reads.
[Service]
ExecStartPost=-/usr/libexec/pneuma-update-flag
EOF

echo "::endgroup::"

echo "::group:: Keyboard Remapping (keyd)"

# keyd: system-wide key remapping at the evdev layer — applies in Hyprland,
# GNOME, and virtual consoles alike. Not packaged for EL10 (the community COPR
# has no epel-10 chroot), so build the small C daemon from a pinned tag.
# Config ships in /etc (keyd only reads /etc/keyd/; build-time /etc files
# persist via ostree 3-way merge).
# renovate: datasource=github-tags depName=rvaiya/keyd
KEYD_VERSION="v2.5.0"
git clone --depth 1 --branch "${KEYD_VERSION}" https://github.com/rvaiya/keyd.git /tmp/keyd
# PREFIX must be set at compile time too (DATA_DIR is baked into the binary
# and keyd.service is generated from it during `make all`)
make -C /tmp/keyd PREFIX=/usr
make -C /tmp/keyd install PREFIX=/usr
# The Makefile only installs the unit when systemd is *running* — never true
# inside a container build — so install the generated unit explicitly.
install -Dm644 /tmp/keyd/keyd.service /usr/lib/systemd/system/keyd.service
rm -rf /tmp/keyd
install -Dm644 /ctx/build/files/etc/keyd/default.conf /etc/keyd/default.conf
systemctl enable keyd.service

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable systemd services the base leaves off (everything else — tailscaled,
# firewalld, fwupd, uupd.timer, gdm — is already handled by bluefin-lts;
# gdm is later replaced by sddm in script 37).
systemctl enable podman.socket
systemctl enable pneuma-user-setup.service
systemctl enable podman-auto-update.timer

# grub2-tools ships a per-user timer that writes boot_success to grubenv
# 2 minutes after every login; /boot is read-only on bootc, so it fails
# permanently (and Omarchy's failed-unit toast surfaces it). Boot counting
# via grubenv is unused on image-based systems.
if [ -f /usr/lib/systemd/user/grub-boot-success.timer ]; then
    systemctl --global mask grub-boot-success.timer
fi

# Pre-enable user services for new users via /etc/skel (guarded: the systray
# unit arrives via dotfiles/brew, not every build has it)
if [ -f /usr/lib/systemd/user/tailscale-systray.service ]; then
    mkdir -p /etc/skel/.config/systemd/user/default.target.wants
    ln -sf /usr/lib/systemd/user/tailscale-systray.service /etc/skel/.config/systemd/user/default.target.wants/tailscale-systray.service
fi

echo "::endgroup::"

echo "::group:: ZRAM Configuration"

# Configure ZRAM with LZ4 compression (4GB) — deliberate tuning override of
# the base's zstd default. /usr/lib path (immutable layer): /etc is user-owned
# state on ostree.
mkdir -p /usr/lib/systemd
cat > /usr/lib/systemd/zram-generator.conf << 'ZRAMEOF'
[zram0]
zram-size = min(ram, 4096)
compression-algorithm = lz4
ZRAMEOF

echo "::endgroup::"

echo "::group:: Kernel Hardening"

# Sysctl hardening
# Use /usr/lib path (immutable layer) — /etc is user-owned state on ostree
mkdir -p /usr/lib/sysctl.d
cat > /usr/lib/sysctl.d/99-pneuma-hardening.conf << 'SYSCTLEOF'
# Restrict dmesg access to root
kernel.dmesg_restrict = 1

# Hide kernel pointers
kernel.kptr_restrict = 2

# Restrict ptrace
kernel.yama.ptrace_scope = 2

# Disable core dumps
fs.suid_dumpable = 0

# Network hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
SYSCTLEOF

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
