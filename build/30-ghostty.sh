#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Ghostty Terminal (built from source)
###############################################################################
# Build from source to get a pinned, up-to-date version — no COPR dependency.
# EL10 has no gtk4-layer-shell at all and Ghostty links the system library,
# so the small C library is meson-built from a pinned tag first; its runtime
# .so stays in the image (Ghostty links it), the devel droppings are removed.
#
# Ghostty: https://ghostty.org
###############################################################################

echo "::group:: Build gtk4-layer-shell from Source"

# Snapshot the package set: build deps are removed afterwards by name diff
# with --noautoremove. Removing base-image packages (e.g. gettext, pkgconf)
# by name cascade-removes their dependents — gnome-shell/GDM among them.
BEFORE_LIST=/tmp/ghostty-packages-before.txt
rpm -qa --qf '%{NAME}\n' | sort -u >"${BEFORE_LIST}"

# renovate: datasource=github-tags depName=wmww/gtk4-layer-shell
GTK4_LAYER_SHELL_VERSION="v1.3.0"
dnf -y install git meson ninja-build gtk4-devel wayland-devel
git clone --depth 1 --branch "${GTK4_LAYER_SHELL_VERSION}" \
    https://github.com/wmww/gtk4-layer-shell.git /tmp/gtk4-layer-shell
meson setup /tmp/gtk4-layer-shell/build /tmp/gtk4-layer-shell \
    --prefix=/usr --buildtype=release \
    -Dintrospection=false -Dvapi=false -Dsmoke-tests=false
ninja -C /tmp/gtk4-layer-shell/build install
rm -rf /tmp/gtk4-layer-shell

echo "::endgroup::"

echo "::group:: Build Ghostty Terminal from Source"

# IMPORTANT: Update ZIG_VERSION when bumping Ghostty — check the compatibility
# table at https://ghostty.org/docs/install/build
# renovate: datasource=github-releases depName=ghostty-org/ghostty
GHOSTTY_VERSION="1.3.1"
ZIG_VERSION="0.15.2"

# Build-only deps — removed after install (by snapshot diff) to keep the
# image lean. gettext/pkgconf are NOT listed: the base ships them and
# GNOME needs them at runtime.
dnf -y install gtk4-devel libadwaita-devel gettext

# Fetch Zig compiler (static binary, no install needed)
curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C /tmp
ZIG="/tmp/zig-x86_64-linux-${ZIG_VERSION}/zig"

# Fetch and build Ghostty
curl -fsSL "https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz" \
    | tar -xz -C /tmp
cd "/tmp/ghostty-${GHOSTTY_VERSION}"
# -Dcpu=baseline is REQUIRED for an image shipped to other machines: Zig targets the
# *build* host's native CPU by default, so the binary inherits whatever ISA extensions
# the GitHub runner happened to have. Runner hardware varies (Intel Ice Lake Xeons carry
# AVX-512, AMD EPYC does not), which makes the breakage intermittent across rebuilds —
# a build that lands on an AVX-512 runner SIGILLs on first launch on any consumer CPU
# without it (e.g. Whiskey Lake i5-8265U faults on a vptestnmb in a vectorized string
# routine). Ghostty's SIMD hot paths dispatch at runtime via Google Highway, so baseline
# costs no meaningful performance.
# Upstream guidance: https://github.com/ghostty-org/ghostty/blob/main/PACKAGING.md
XDG_CACHE_HOME=/tmp/.cache "${ZIG}" build \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline \
    -Dversion-string="${GHOSTTY_VERSION}" \
    -p /usr
cd /

# Clean up build artifacts and Zig compiler
rm -rf /tmp/zig-* /tmp/ghostty-* /tmp/.cache

# Remove ONLY what this script added (snapshot diff), without dependency
# autoremoval — cascades through pre-existing packages are exactly how a
# devel cleanup deletes GNOME. Then assert the desktop survived.
AFTER_LIST=/tmp/ghostty-packages-after.txt
rpm -qa --qf '%{NAME}\n' | sort -u >"${AFTER_LIST}"
comm -13 "${BEFORE_LIST}" "${AFTER_LIST}" >/tmp/ghostty-packages-added.txt
if [ -s /tmp/ghostty-packages-added.txt ]; then
    xargs -a /tmp/ghostty-packages-added.txt dnf -y remove --noautoremove
fi
rm -f "${BEFORE_LIST}" "${AFTER_LIST}" /tmp/ghostty-packages-added.txt
rpm -q gtk4 libadwaita gnome-shell gdm gettext
rm -rf /usr/include/gtk4-layer-shell /usr/lib64/pkgconfig/gtk4-layer-shell-0.pc
test -e /usr/lib64/libgtk4-layer-shell.so.0

test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop

echo "Ghostty ${GHOSTTY_VERSION} built and installed"
echo "::endgroup::"
