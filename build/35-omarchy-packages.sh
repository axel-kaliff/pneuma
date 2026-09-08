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
#   yaru-icon-theme -> akaliff/pneuma COPR in script 36. Was dropped here as
#                      a papercut; it is not one. Every omarchy theme's
#                      icons.theme names a Yaru-* variant, so without the
#                      package icon-theme points at a directory that does not
#                      exist — GTK4 cannot read its index.theme, never sees
#                      Inherits=, and drops to hicolor, skipping Adwaita.
#                      Measured: 2 of 18 file/folder icons resolved.
#   mpv-mpris, imv, sushi, udiskie -> dropped (papercuts only;
#                      Loupe flatpak covers image viewing)
#   fcitx5*         -> dropped (not in EL10; its environment.d file would also
#                      poison GNOME's ibus — see script 37)
#   bluez-tools     -> dropped (bt-agent user unit removed in 37)
#   wtype, brightnessctl, grim, slurp -> yselkowitz/wlroots-epel in script 36
#   starship        -> pneuma COPR in script 36
#
# Known gap, accepted:
#   adwaita-icon-theme stays at c10s 46.0 while nautilus, gtk4 and libadwaita
#   come from the jreilly1821/c10s-gnome-49 COPR, which does not carry the
#   icon theme. With Yaru installed, 35 of the 37 symbolic names nautilus 49
#   references resolve; the two that do not are cut-symbolic and
#   cut-large-symbolic, the Adwaita 48 rename of edit-cut-symbolic, carried
#   by neither Adwaita 46 nor Yaru. They render blank in the context menu.
#   Revisit if c10s or that COPR ever rebases adwaita-icon-theme past 47.
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

echo "Omarchy distro packages installed!"
