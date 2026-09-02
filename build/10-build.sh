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

echo "::group:: Rebuild RPMDB"

# The base image's sqlite rpmdb is written by the (newer) rpm/sqlite of its
# Fedora build runners; c10s rpm 4.19 then fails index SELECTs with
# "database disk image is malformed" on the first dnf transaction check.
# Rewrite the db with this OS's own rpm. rpm --rebuilddb's final rename can
# fail on overlayfs ("failed to replace old database") — fall back to
# swapping the rebuilt files in manually. This RUN layer executes every
# numbered build script, so one rebuild covers them all.
RPMDB_DIR="$(readlink -f "$(rpm --eval '%_dbpath')")"
if ! rpm --rebuilddb; then
    latest="$(find "$(dirname "${RPMDB_DIR}")" -maxdepth 1 -name 'rpmrebuilddb.*' | sort | tail -n1)"
    test -n "${latest}"
    rm -f "${RPMDB_DIR}"/rpmdb.sqlite*
    cp -f "${latest}"/* "${RPMDB_DIR}"/
    rm -rf "${latest}"
fi
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
# GNOME, and virtual consoles alike. Not packaged for EL10 anywhere upstream,
# so it's built in the akaliff/pneuma COPR (spec vendored in the omedora
# fork — see build/36 header for the spec-source flow). The RPM ships the
# systemd unit and a keyd-group sysusers.d entry, replacing the from-source
# compile and the pneuma-keyd.conf sysusers file this script used to install.
# Config ships in /etc (keyd only reads /etc/keyd/; build-time /etc files
# persist via ostree 3-way merge).
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh
copr_install_isolated "akaliff/pneuma" keyd
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
#
# Deliberately narrow: this is a developer workstation, so knobs that cost
# more in diagnosis than they buy in defence are left at the distro value.
# Do NOT re-add these without re-reading why they were dropped:
#   kptr_restrict = 2   50-redhat.conf ships 1 (hidden from unprivileged,
#                       visible to CAP_SYSLOG). 2 hides pointers from root as
#                       well and breaks perf symbolisation.
#   fs.suid_dumpable=0  overrides systemd's 50-coredump.conf (2, root-only
#                       readable) and silently disables systemd-coredump.
#   dmesg_restrict = 1  locks the console user out of the first tool you reach
#                       for when triaging, on a single-user machine where that
#                       user can sudo anyway.
mkdir -p /usr/lib/sysctl.d
cat > /usr/lib/sysctl.d/99-pneuma-hardening.conf << 'SYSCTLEOF'
# Restrict ptrace to descendants: gdb/strace still work on processes you
# launch, and PR_SET_PTRACER is honoured (Chromium's crash handler needs it);
# attaching to unrelated running processes is not allowed. The base ships 0
# in 10-default-yama-scope.conf; 2 requires CAP_SYS_PTRACE and blocks
# debugging outright, including inside Flatpak sandboxes.
kernel.yama.ptrace_scope = 1

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
