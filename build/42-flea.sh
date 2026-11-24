#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# flea GUI file manager
#
# Upstream packages for Arch; install the pinned x86_64 release on EL10
# using the Makefile's layout and Omarchy's shared QML modules. The release
# needs at most GLIBC_2.39, matching CentOS Stream 10.
# Deliberately omit qt6-qtwebengine (~94 MB, only HTML previews), quickjs-ng
# (not in EL10/EPEL, Markdown maths/diagram previews), and gvfs-afc (not in
# EL10, iPhone files). Skip flea.hook: pacman alpm hooks do not apply on EL.
###############################################################################

# Version and checksum move together.
FLEA_VERSION="0.4.3"
FLEA_SHA256="98427acddcb4122d86549f7f0f79532329c8c12dc7da46e7c9a41c50b334ed4a"

echo "::group:: Install flea Runtime Dependencies"

dnf -y install bubblewrap expect gvfs gvfs-gphoto2 gvfs-mtp gvfs-smb \
    libheif mpv-libs poppler-glib python3-gobject qt6-qtpdf ripgrep bat \
    udisks2 usbmuxd util-linux vulkan-loader mesa-vulkan-drivers \
    libxkbcommon-x11 shared-mime-info xdg-terminal-exec xdg-utils \
    libarchive 7zip ffmpegthumbnailer

echo "::endgroup::"

echo "::group:: Install flea Release"

BUILD_DIR="$(mktemp -d)"
curl -fsSL --retry 3 --max-time 300 \
    -o "${BUILD_DIR}/flea.tar.gz" \
    "https://github.com/thisisgm/flea/releases/download/v${FLEA_VERSION}/flea-v${FLEA_VERSION}-linux-x86_64.tar.gz"
echo "${FLEA_SHA256}  ${BUILD_DIR}/flea.tar.gz" | sha256sum -c -
tar -xzf "${BUILD_DIR}/flea.tar.gz" -C "${BUILD_DIR}"
cd "${BUILD_DIR}/flea-${FLEA_VERSION}-linux-x86_64"

install -Dm755 -t /usr/bin flea flea-gui
install -Dm755 -t /usr/lib/flea \
    tools/flea-gio-auth tools/flea-udisks tools/flea-portal \
    tools/flea-filemanager1 tools/flea-mpris
install -Dm644 packaging/flea.portal /usr/share/xdg-desktop-portal/portals/flea.portal
install -Dm644 -t /usr/share/dbus-1/services \
    packaging/org.freedesktop.impl.portal.desktop.flea.service \
    packaging/com.thisisgm.flea.FileManager1.service
install -Dm644 packaging/com.thisisgm.flea.desktop /usr/share/applications/com.thisisgm.flea.desktop
install -Dm644 packaging/com.thisisgm.flea.svg /usr/share/icons/hicolor/scalable/apps/com.thisisgm.flea.svg
install -Dm644 -t /usr/share/licenses/flea LICENSE THIRD-PARTY-LICENSES.txt

install -Dm644 -t /usr/share/flea/ui ui/qmldir ui/*.qml ui/*.js
install -Dm644 -t /usr/share/flea/ui/js ui/js/*.js ui/js/*.mjs
install -Dm644 -t /usr/share/flea/ui/vendor ui/vendor/*.mjs
install -Dm644 -t /usr/share/flea/ui/vendor/LICENSES ui/vendor/LICENSES/*
install -Dm644 -t /usr/share/flea/ui/boot \
    ui/boot/shell.qml ui/boot/picker.qml ui/boot/fleatab.qml ui/boot/tabtearoff.qml
install -Dm644 -t /usr/share/flea/shelf shelf/manifest.json shelf/README.md shelf/*.qml shelf/*.js
for translation in i18n/*/flea.json; do
    install -Dm644 "${translation}" "/usr/share/flea/${translation}"
done

sed -i "s/^  \"version\": \"[^\"]*\",$/  \"version\": \"${FLEA_VERSION}\",/" \
    /usr/share/flea/shelf/manifest.json
grep -Fxq "  \"version\": \"${FLEA_VERSION}\"," /usr/share/flea/shelf/manifest.json

for module in Commons Ui; do
    ln -sfn "/usr/share/omarchy/shell/${module}" "/usr/share/flea/ui/${module}"
    ln -sfn "/usr/share/omarchy/shell/${module}" "/usr/share/flea/ui/boot/${module}"
done

cd /
find "${BUILD_DIR}" -depth -delete

echo "::endgroup::"

echo "::group:: Smoke Checks"

timeout 30 flea --version > /dev/null || timeout 30 flea --help > /dev/null
test -f /usr/share/flea/ui/boot/shell.qml
for module in Commons Ui; do
    test -d "/usr/share/flea/ui/${module}"
    test -d "/usr/share/flea/ui/boot/${module}"
done

# Offscreen cannot provide a Wayland session; fail only on QML import/type errors.
flea_log="$(XDG_RUNTIME_DIR="$(mktemp -d)" QT_QPA_PLATFORM=offscreen \
    timeout 30 qs -p /usr/share/flea/ui/boot/shell.qml 2>&1)" || true
if grep -qE 'is not installed|is not a type|module ".*" .*not|Cannot assign to non-existent' <<< "${flea_log}"; then
    echo "ERROR: flea UI does not load:" >&2
    grep -E 'is not installed|is not a type|module ".*" .*not|Cannot assign to non-existent' <<< "${flea_log}" >&2
    exit 1
fi

echo "::endgroup::"

echo "flea installation complete!"
