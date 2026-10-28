#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Hyprglass plugin (built against the installed Hyprland)
###############################################################################
# Match hyprland-devel to the installed runtime EVR. Upstream pins v0.11.0
# to Hyprland 0.56.2, but it builds against 0.56.1 headers: 0.56.2 only adds
# one non-virtual renderer method.
# The user's Hyprland config loads /usr/lib64/hyprland/hyprglass.so by
# absolute path via hl.plugin.load in the dotfiles' hypr/looknfeel.lua.
# Nothing loads the plugin automatically.
###############################################################################

echo "::group:: Build Hyprglass from Source"

# /tmp is tmpfs during image builds; compiling there can trip systemd-oomd.
BUILD_DIR=$(mktemp -d /var/tmp/hyprglass.XXXXXX)
BEFORE_LIST="${BUILD_DIR}/pkgs-before.txt"
rpm -qa --qf '%{NAME}\n' | sort -u >"${BEFORE_LIST}"
HYPR_RUNTIME=(hyprland-no-session aquamarine hyprutils hyprlang hyprgraphics hyprcursor hyprwire)
rpm -q "${HYPR_RUNTIME[@]}" >"${BUILD_DIR}/runtime-before.txt"
HYPRLAND_EVR=$(rpm -q --qf '%{VERSION}-%{RELEASE}' hyprland-no-session)

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh
copr_install_isolated "akaliff/pneuma" "hyprland-devel-${HYPRLAND_EVR}"
pkg-config --print-requires hyprland | awk '{print "pkgconfig(" $1 ")"}' >"${BUILD_DIR}/pkgconfig-deps.txt"
mapfile -t PKGCONFIG_DEPS <"${BUILD_DIR}/pkgconfig-deps.txt"
copr_install_isolated "akaliff/pneuma" "${PKGCONFIG_DEPS[@]}"
dnf -y install glslang-devel pixman-devel libdrm-devel wayland-devel \
    gcc-toolset-15-gcc-c++ make git
pkg-config --cflags hyprland pixman-1 libdrm wayland-server

# Hyprland links Lua 5.5.0 statically but ships no Lua headers; EL10's
# lua-devel is 5.4 (another ABI). Expose these headers only to the build.
curl --fail --silent --show-error --location --max-time 60 \
    -o "${BUILD_DIR}/lua-5.5.0.tar.gz" https://www.lua.org/ftp/lua-5.5.0.tar.gz
echo "57ccc32bbbd005cab75bcc52444052535af691789dba2b9016d5c50640d68b3d  ${BUILD_DIR}/lua-5.5.0.tar.gz" | sha256sum -c -
tar -xzf "${BUILD_DIR}/lua-5.5.0.tar.gz" -C "${BUILD_DIR}"

# renovate: datasource=github-tags depName=hyprnux/hyprglass
HYPRGLASS_VERSION="v0.11.0"
HYPRGLASS_COMMIT="7fc328064c63d9fbaaac8d8204eadf85dcdeae19"
timeout 300 git clone --branch "${HYPRGLASS_VERSION}" \
    https://github.com/hyprnux/hyprglass "${BUILD_DIR}/hyprglass"
cd "${BUILD_DIR}/hyprglass"
git checkout "${HYPRGLASS_COMMIT}"
test "$(git rev-parse "refs/tags/${HYPRGLASS_VERSION}^{commit}")" = "${HYPRGLASS_COMMIT}"
# Keep .git: the Makefile uses git describe for the version.
CPLUS_INCLUDE_PATH="${BUILD_DIR}/lua-5.5.0/src" \
    PATH="/opt/rh/gcc-toolset-15/root/usr/bin:${PATH}" make -j"$(nproc)"
install -Dm755 hyprglass.so /usr/lib64/hyprland/hyprglass.so
install -Dm644 LICENSE /usr/share/licenses/hyprglass/LICENSE
cd /

# Remove only added package names, without autoremoving base-image deps.
AFTER_LIST="${BUILD_DIR}/pkgs-after.txt"
rpm -qa --qf '%{NAME}\n' | sort -u >"${AFTER_LIST}"
comm -13 "${BEFORE_LIST}" "${AFTER_LIST}" >"${BUILD_DIR}/pkgs-added.txt"
if [ -s "${BUILD_DIR}/pkgs-added.txt" ]; then
    xargs -a "${BUILD_DIR}/pkgs-added.txt" dnf -y remove --noautoremove
fi
rpm -q "${HYPR_RUNTIME[@]}" >"${BUILD_DIR}/runtime-after.txt"
diff -u "${BUILD_DIR}/runtime-before.txt" "${BUILD_DIR}/runtime-after.txt"
rpm -q gnome-shell gdm
ldd /usr/lib64/hyprland/hyprglass.so >"${BUILD_DIR}/ldd.txt"
if grep -q 'not found' "${BUILD_DIR}/ldd.txt"; then
    exit 1
fi
rm -rf "${BUILD_DIR}"

echo "::endgroup::"
