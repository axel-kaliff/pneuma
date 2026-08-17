#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Branding: Plymouth boot splash, GRUB theme
###############################################################################

echo "::group:: Install Plymouth Boot Theme"

# Install the Pneuma plymouth theme ("Pneuma Breath" — a breathing core with
# rippling breath-waves, drawn procedurally by the script plugin).
# Theme files are shipped in build/files/usr/share/plymouth/themes/pneuma/
THEME_DIR="/usr/share/plymouth/themes/pneuma"
mkdir -p "${THEME_DIR}"
cp /ctx/build/files/usr/share/plymouth/themes/pneuma/* "${THEME_DIR}"/

# Set as default plymouth theme
plymouth-set-default-theme pneuma

# The omarchy payload (script 36) ships its own Plymouth theme — assert the
# pneuma splash is still what gets baked into the initramfs below.
[[ "$(plymouth-set-default-theme)" == "pneuma" ]]

# Regenerate initramfs so the plymouth theme is baked in
# On bootc, the initramfs must be built during container image build
QUALIFIED_KERNEL="$(find /lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n 1)"
/usr/bin/dracut \
    --no-hostonly \
    --kver "${QUALIFIED_KERNEL}" \
    --reproducible \
    --zstd \
    --add ostree \
    -f "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"

echo "::endgroup::"

echo "::group:: Install GRUB Theme"

# Ship GRUB theme in the image — a first-boot service copies it to /boot
# because /boot is a separate partition not available during container build
GRUB_SRC="/usr/share/pneuma/grub-theme"
mkdir -p "${GRUB_SRC}"
cp /ctx/build/files/usr/share/pneuma/grub-theme/* "${GRUB_SRC}"/

# Install the GRUB setup service and script
install -Dm755 /ctx/build/files/usr/libexec/pneuma-grub-setup /usr/libexec/pneuma-grub-setup
install -Dm644 /ctx/build/files/usr/lib/systemd/system/pneuma-grub-setup.service /usr/lib/systemd/system/pneuma-grub-setup.service
systemctl enable pneuma-grub-setup.service

echo "::endgroup::"

echo "Branding complete!"
