#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy v4 "Quattro" — distro packages (CentOS Stream 10 / EPEL 10 / COPR)
###############################################################################
# First of three omarchy scripts:
#   35: everything Omarchy needs that c10s/EPEL10/COPR already carry (this)
#   36: the omedora payload + Hyprland 0.56 stack, rpmbuilt from pinned specs
#   37: SDDM/session/skel configuration + smoke checks
#
# Deviations from the lateralus (Fedora 44) package set, forced by EL10
# availability — all cosmetic or shimmed:
#   foot            -> kitty is the fallback terminal (Ghostty stays default)
#   pamixer         -> omarchy v4 audio flows use wireplumber's wpctl (in base)
#   yt-dlp          -> brew (custom/brew/default.Brewfile)
#   mpv-mpris, imv, sushi, udiskie, yaru-icon-theme -> dropped (papercuts only;
#                      Loupe flatpak covers image viewing)
#   fcitx5*         -> dropped (not in EL10; its environment.d file would also
#                      poison GNOME's ibus — see script 37)
#   bluez-tools     -> dropped (bt-agent user unit removed in 37)
#   wtype, brightnessctl -> built from source in script 36
#   starship        -> rpmbuilt in script 36 (binary repackage spec)
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

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

echo "::group:: Install Screenshot Tools from COPR (isolated)"

# alonid/hyprland (rhel+epel-10) carries the wlroots-adjacent leaf tools EL10
# lacks. The Hyprland compositor itself is NOT taken from this COPR — its
# current hyprland-git predates the 0.56 configs the omarchy v4 payload needs,
# so script 36 builds the pinned 0.56 stack from the omedora specs instead.
copr_install_isolated "alonid/hyprland" \
    grim \
    slurp

echo "::endgroup::"

echo "Omarchy distro packages installed!"
