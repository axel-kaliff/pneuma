#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy v4 payload + Hyprland 0.56 stack — prebuilt RPMs from COPR
###############################################################################
# The stack is no longer rpmbuilt in-image. The pinned omedora spec set — plus
# the EL10 patches that used to live here as build-time seds — is built once
# per version bump in the axel-kaliff/pneuma COPR (chroot epel-10-x86_64) from
# the pneuma-el10 branch of github.com/axel-kaliff/omedora (a fork of
# AndrewGaspar/omedora, the same monorepo the agaspar/omedora-4 Fedora COPR
# builds from, reusing its .copr/srpm.sh make_srpm machinery and sha256 source
# pins). This script only enables the repos for one transaction and installs
# the runtime set — image builds went from ~1-2 h of compiling to a dnf install.
#
#   axel-kaliff/pneuma ......... hypr 0.56 stack, quickshell, uwsm, starship,
#                                omedora(+settings), keyd, muParser, and
#                                libxkbcommon >= 1.11 (CS10 ships 1.7 — the
#                                single remaining base-lib override; drop it
#                                when CS10 rebases past 1.11)
#   yselkowitz/wlroots-epel .... leaf Wayland tools EL10 lacks (foot, grim,
#                                slurp, wtype, brightnessctl) — trusted Fedora
#                                maintainer, real epel-10 chroot
#
# alonid/hyprland is gone entirely: CS10 has caught up on the base libs
# (wayland 1.25, wayland-protocols 1.49, libinput >= 1.29), so no third-party
# lib backports are needed at build or runtime.
#
# To rebuild the stack after an omedora upstream bump:
#   cd ~/omedora && git fetch upstream && git rebase upstream/omedora-4 \
#     && git push  →  COPR rebuilds (webhook)  →  rebuild this image.
###############################################################################

PNEUMA_REPOFILE=/etc/yum.repos.d/_copr-axel-kaliff-pneuma.repo
YS_REPOFILE=/etc/yum.repos.d/_copr-yselkowitz-wlroots-epel.repo

cleanup_repos() {
    rm -f "${PNEUMA_REPOFILE}" "${YS_REPOFILE}"
}
trap cleanup_repos EXIT

cat >"${PNEUMA_REPOFILE}" <<'EOF'
[copr-axel-kaliff-pneuma]
name=Copr repo for axel-kaliff/pneuma (epel-10)
baseurl=https://download.copr.fedorainfracloud.org/results/axel-kaliff/pneuma/epel-10-$basearch/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/axel-kaliff/pneuma/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF

cat >"${YS_REPOFILE}" <<'EOF'
[copr-yselkowitz-wlroots-epel]
name=Copr repo for yselkowitz/wlroots-epel (epel-10)
baseurl=https://download.copr.fedorainfracloud.org/results/yselkowitz/wlroots-epel/epel-10-$basearch/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/yselkowitz/wlroots-epel/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF

echo "::group:: Install the Omarchy runtime set"

# One transaction with both COPRs enabled together, so omedora's Requires
# chain (foot from yselkowitz; hyprland-no-session, uwsm, quickshell,
# omedora-settings from pneuma) resolves in a single depsolve.
#   libxkbcommon: listed explicitly so the pneuma 1.11 build out-versions the
#     c10s 1.7 in the base image (soname-stable additive upgrade).
#   libinput: pulls CS10's current build (hyprland is built against >= 1.29;
#     the runtime dependency is soname-level and the base may predate it).
#   muParser rides in as hyprland's automatic soname dependency.
#   epel-multimedia: openh264 — EPEL's noopenh264 conflicts with the base's
#     real openh264 (same reason the rpmbuild flow needed it).
dnf -y --best install --enablerepo=epel-multimedia \
    hyprland \
    hyprland-guiutils \
    hyprpicker \
    hyprsunset \
    xdg-desktop-portal-hyprland \
    starship \
    omedora \
    libinput \
    libxkbcommon \
    foot \
    grim \
    slurp \
    wtype \
    brightnessctl

echo "::endgroup::"

echo "::group:: Post-install assertions"

# The base libs really did catch up — fail the build here if hyprland got
# linked against anything the image can't satisfy from CS10 + the two COPRs.
rpm -q libinput --qf '%{VERSION}\n' | grep -qE '^1\.(29|[3-9][0-9])' || {
    echo "ERROR: libinput $(rpm -q libinput --qf '%{VERSION}') < 1.29 — hyprland runtime mismatch" >&2
    exit 1
}
rpm -q libxkbcommon --qf '%{VERSION}\n' | grep -qE '^1\.(1[1-9]|[2-9][0-9])' || {
    echo "ERROR: libxkbcommon $(rpm -q libxkbcommon --qf '%{VERSION}') < 1.11 — pneuma COPR build did not win" >&2
    exit 1
}
if ldd /usr/bin/Hyprland | grep -q 'not found'; then
    echo "ERROR: Hyprland has unresolved shared libraries:" >&2
    ldd /usr/bin/Hyprland | grep 'not found' >&2
    exit 1
fi

echo "::endgroup::"

cleanup_repos
trap - EXIT

echo "Omarchy payload + Hyprland stack installed from COPR!"
