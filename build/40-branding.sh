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

# dracut logs a non-fatal `dracut-install: ERROR: installing '/root'` here and
# still exits 0: /root is a symlink to var/roothome, which bootc only creates at
# deploy time. Assert on content instead of exit status so a real dracut abort
# (which would leave the previous initramfs in place) fails the build.
# Read the listing into a variable rather than piping into `grep -q`: grep
# exits on the first match, lsinitrd then dies of SIGPIPE (141), and pipefail
# turns a passing assert into a failed build.
initramfs_listing="$(lsinitrd "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img")"
grep -q 'plymouth/themes/pneuma/pneuma.script' <<< "${initramfs_listing}"

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

# SDDM greeter wordmark. The Omarchy theme draws logo.png (Main.qml) as the
# only branding on the login screen, so rebranding it is a file swap. Assert
# the target exists first: a theme rename would otherwise silently leave
# "OMARCHY" on the most visible screen in the system.
SDDM_THEME="/usr/share/sddm/themes/omarchy"
[[ -f "${SDDM_THEME}/logo.png" ]]
install -Dm644 /ctx/build/files/usr/share/pneuma/branding/sddm-logo.png \
    "${SDDM_THEME}/logo.png"
sed -i 's/^Name=Omarchy$/Name=Pneuma/' "${SDDM_THEME}/metadata.desktop"

echo "::endgroup::"

echo "Branding complete!"
