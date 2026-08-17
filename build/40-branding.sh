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

echo "::group:: Rebrand Omedora Desktop as Pneuma"

# The omedora payload brands the user-visible desktop as "Omedora". Rebrand
# the spots users actually see; runs after 36-omarchy-payload.sh so the RPM
# files exist.

# Screensaver text art (ttfx animates ~/.config/omarchy/branding/screensaver.txt;
# per-user copies are seeded from skel). Art: pyfiglet -f delta_corps_priest_1.
install -Dm644 /ctx/build/files/usr/share/pneuma/branding/screensaver.txt \
    /etc/skel/.config/omarchy/branding/screensaver.txt

# Menu: the update entry is labeled "Omedora". Override just the label via the
# supported extensions mechanism (partial overrides merge by id).
menu_ext=/etc/skel/.config/omarchy/extensions/omarchy-menu.jsonc
grep -q '^}$' "${menu_ext}"
sed -i 's|^}$|  // Pneuma branding: rename the update entry (default label "Omedora")\n  "update.omarchy": {"label":"Pneuma"}\n}|' "${menu_ext}"

# SDDM session picker entry
sed -i 's/^Name=Omedora$/Name=Pneuma/' /usr/share/wayland-sessions/omedora.desktop
grep -q '^Name=Pneuma$' /usr/share/wayland-sessions/omedora.desktop

echo "::endgroup::"

echo "Branding complete!"
