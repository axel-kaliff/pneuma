#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy v4 "Quattro" — distro packages (CentOS Stream 10 / EPEL 10 / COPR)
###############################################################################
# First of three omarchy scripts:
#   35: everything Omarchy needs that c10s/EPEL10 already carry (this)
#   36: the omedora payload + Hyprland 0.56 stack, prebuilt RPMs from the
#       akaliff/pneuma COPR + yselkowitz/wlroots-epel
#   37: SDDM/session/skel configuration + smoke checks
#
# Deviations from the lateralus (Fedora 44) package set, forced by EL10
# availability — all cosmetic or shimmed:
#   foot            -> from yselkowitz/wlroots-epel in script 36 (omedora's
#                      Requires stays unpatched; kitty stays the visible
#                      fallback terminal, Ghostty stays default)
#   pamixer         -> omarchy v4 audio flows use wireplumber's wpctl (in base)
#   yt-dlp          -> brew (custom/brew/default.Brewfile)
#   yaru-icon-theme -> dropped again, this time with the theme choice pinned.
#                      Every omarchy theme's icons.theme names a Yaru-* variant
#                      and an icon-theme that does not resolve fails silently
#                      at runtime, so script 36 patches the selection itself to
#                      Adwaita rather than shipping 58 MB of Yaru to satisfy it.
#   mpv-mpris, imv, sushi, udiskie -> dropped (papercuts only;
#                      Loupe flatpak covers image viewing)
#   fcitx5*         -> dropped (not in EL10; its environment.d file would also
#                      poison GNOME's ibus — see script 37)
#   bluez-tools     -> dropped (bt-agent user unit removed in 37)
#   wtype, brightnessctl, grim, slurp -> yselkowitz/wlroots-epel in script 36
#   starship        -> pneuma COPR in script 36
#
# Closed gap:
#   adwaita-icon-theme came from c10s at 46.0 while nautilus, gtk4 and
#   libadwaita come from the jreilly1821/c10s-gnome-49 COPR, which does not
#   carry the icon theme. Fedora 43's noarch 49.0 replaces it at the end of
#   this script — drop that block if c10s or the COPR ever rebases past 47.
###############################################################################

echo "::group:: Install Official-Repo Packages for Omarchy"

# Everything Omarchy needs that c10s BaseOS/AppStream/CRB + EPEL 10 carry.
# install_weak_deps is globally 0, so runtime companions must be listed
# explicitly even when they are "usually there".
# chromium is a deliberate RPM exception to the "GUI apps are flatpaks" rule:
# Flatpak Chromium groups all --app windows under one window class, which
# breaks Omarchy's per-webapp window matching (flathub/org.chromium.Chromium#216).
# perl-JSON-PP: omarchy-menu-select/-input build their Quickshell IPC payload
# with `perl -MJSON::PP`; Arch bundles JSON::PP in core perl, EL splits it.
dnf -y install \
    sddm \
    sddm-wayland-generic \
    xdg-desktop-portal-gtk \
    xdg-terminal-exec \
    xdg-user-dirs \
    xdg-utils \
    mesa-dri-drivers \
    kitty \
    ddcutil \
    libnotify \
    inotify-tools \
    perl-JSON-PP \
    socat \
    plocate \
    tesseract \
    tesseract-langpack-eng \
    zbar \
    qrencode \
    ImageMagick \
    mpv \
    nautilus \
    nautilus-python \
    ffmpegthumbnailer \
    gvfs-mtp \
    gvfs-smb \
    gnome-keyring \
    bolt \
    fprintd \
    alsa-utils \
    pipewire-utils \
    sound-theme-freedesktop \
    btop \
    fastfetch \
    jq \
    fzf \
    liberation-fonts \
    google-noto-color-emoji-fonts \
    google-noto-naskh-arabic-fonts \
    google-noto-nastaliq-urdu-fonts \
    chromium

echo "::endgroup::"

echo "::group:: Replace the Icon Theme with Adwaita 49"

# c10s ships adwaita-icon-theme 46.0 under GNOME 49 apps: 134 icons keep their
# GNOME 46 artwork and 12 (battery *-plugged-in, airplane-mode-disabled) do not
# exist at all, so the bar's charging states render blank. Fedora 43 GA is the
# only 49 packaging; all three are noarch, and released Fedora trees are frozen
# so the URLs do not move. 49 split the pre-47 names into a separate
# AdwaitaLegacy theme that its index.theme inherits, which is why the legacy
# package has to land in the same transaction.
F43_PACKAGES=https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/os/Packages/a

dnf -y install \
    "${F43_PACKAGES}/adwaita-icon-theme-49.0-1.fc43.noarch.rpm" \
    "${F43_PACKAGES}/adwaita-icon-theme-legacy-46.2-4.fc43.noarch.rpm" \
    "${F43_PACKAGES}/adwaita-cursor-theme-49.0-1.fc43.noarch.rpm"

# Fail the build if the c10s 46.0 package won the transaction after all.
rpm -q adwaita-icon-theme --qf '%{VERSION}\n' | grep -qE '^(49|[5-9][0-9])' || {
    echo "ERROR: adwaita-icon-theme is $(rpm -q adwaita-icon-theme --qf '%{VERSION}') — expected 49" >&2
    exit 1
}
[[ -f /usr/share/icons/AdwaitaLegacy/index.theme ]]

echo "::endgroup::"

echo "Omarchy distro packages installed!"
