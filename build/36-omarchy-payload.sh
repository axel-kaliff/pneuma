#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy v4 payload + Hyprland 0.56 stack — rpmbuilt from pinned omedora specs
###############################################################################
# The omedora COPR (agaspar/omedora-4) only builds for Fedora 44, and the one
# EL10 Hyprland COPR (alonid/hyprland) still ships 0.55 — but the omarchy v4
# payload needs the 0.56 line (Lua configs; the SDDM greeter boots Hyprland
# with hyprland.lua). So this script rebuilds the pinned spec set from the
# omedora monorepo in-container, in dependency order, exactly as omedora's own
# build-repo.sh does — a local createrepo_c repo lets each spec resolve its
# just-built siblings via dnf builddep.
#
# Build-time additions are snapshotted and removed afterwards; only the final
# runtime set (installed from the local repo in one dnf transaction) persists.
#
# alonid/hyprland stays enabled throughout: it carries the EL10 backports the
# specs assume from Fedora 44 (libinput 1.29, libxkbcommon 1.11, wayland 1.25,
# wayland-protocols 1.49, muParser, jemalloc, ...) both as BuildRequires and
# as runtime libraries for the built stack.
#
# omedora: https://github.com/AndrewGaspar/omedora  ·  Omarchy: https://omarchy.org
###############################################################################

OMEDORA_REPO="https://github.com/AndrewGaspar/omedora.git"
# omedora-4 branch, Quattro beta wave (2026-08-12) — the same payload pin the
# agaspar/omedora-4 COPR builds omedora/omedora-settings from. Bump ONLY in
# lockstep with a hyprland version check: the payload's configs must match the
# hyprland.spec at the same commit.
OMEDORA_PIN="d671261d4e2bdd1f5bbaf500ee98923b058909c9"

# /var/tmp, not /tmp: the tmpfs would hold sources + build trees in RAM
WORK=/var/tmp/omedora-build
SRC="${WORK}/src"
COPR_DIR="${SRC}/omedora/packaging/copr"
TOPDIR="${WORK}/rpmbuild"
LOCAL_REPO="${WORK}/repo"
ALONID_REPOFILE=/etc/yum.repos.d/_copr-alonid-hyprland.repo
LOCAL_REPOFILE=/etc/yum.repos.d/_pneuma-local-build.repo

# Build order from omedora's own build-repo.sh (deep intra-stack BuildRequires:
# each -devel must land in the local repo before the next spec builds).
# v1 skips: omedora-nerd-fonts (326 MB), tensaku/satty (vendored cargo),
# omacut/omawrite/gpu-screen-recorder/voxtype/herdr/ttfx (extras),
# hyprland-preview-share-picker (xdph's own picker path), hypxr* (XR stack).
SPECS=(
    glaze
    hyprland-protocols
    hyprutils
    hyprwayland-scanner
    hyprlang
    hyprgraphics
    hyprwire
    hyprcursor
    aquamarine
    hyprtoolkit
    hyprland
    hyprland-guiutils
    hyprpicker
    hyprsunset
    xdg-desktop-portal-hyprland
    uwsm
    quickshell
    starship
    omedora-settings
    omedora
)

echo "::group:: Snapshot package set + install build tooling"

BEFORE_LIST="${WORK}/packages-before.txt"
mkdir -p "${WORK}" "${LOCAL_REPO}" "${TOPDIR}"/{SOURCES,SPECS,RPMS,SRPMS,BUILD}
rpm -qa --qf '%{NAME}\n' | sort -u >"${BEFORE_LIST}"

# alonid/hyprland repo — enabled for the whole script (see header).
# alonid/gcc-toolset-15 provides the SCL-style gcc 15 the hypr 0.56 sources
# need (C++23 library features like std::vector::append_range are missing
# from c10s gcc 14's libstdc++); newer C++ symbols are statically linked from
# the toolset's libstdc++_nonshared, so built binaries run on the base
# runtime. Build-time only — removed with the rest of the tooling below.
cat >"${ALONID_REPOFILE}" <<'EOF'
[copr-alonid-hyprland]
name=Copr repo for alonid/hyprland (rhel+epel-10)
baseurl=https://download.copr.fedorainfracloud.org/results/alonid/hyprland/rhel+epel-10-$basearch/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/alonid/hyprland/pubkey.gpg
repo_gpgcheck=0
enabled=1
# The hypr stack itself comes from our local 0.56-line builds — alonid's
# 0.55-line packages (higher Release, older ABI) must never shadow them.
# Only the system-lib backports (libinput, libxkbcommon, wayland*, muParser,
# jemalloc, breakpad, ...) and grim/slurp are taken from this repo.
excludepkgs=glaze* hyprland* hyprutils* hyprlang* hyprgraphics* hyprcursor* hyprwire* aquamarine* hyprtoolkit* hyprpicker* hyprsunset* xdg-desktop-portal-hyprland* quickshell* hyprlock* hypridle* hyprwayland-scanner* SwayNotificationCenter*

[copr-alonid-gcc-toolset-15]
name=Copr repo for alonid/gcc-toolset-15 (rhel+epel-10)
baseurl=https://download.copr.fedorainfracloud.org/results/alonid/gcc-toolset-15/rhel+epel-10-$basearch/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/alonid/gcc-toolset-15/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF

createrepo_c_refresh() {
    createrepo_c --quiet --update "${LOCAL_REPO}"
    dnf -y makecache --disablerepo='*' --enablerepo=pneuma-local-build --refresh
}

# RPM payloads cannot unpack through the bootc /opt -> /var/opt symlink; the
# SCL toolset installs under /opt/rh. Make /opt a real directory for the
# build phase — restored to the symlink in the cleanup group below (and the
# Containerfile re-asserts it after this script regardless).
if [ -L /opt ]; then
    rm /opt
    mkdir /opt
fi

# Tooling first — the local repo file can only be enabled once createrepo_c
# has produced metadata for the (initially empty) repo directory.
dnf -y install rpm-build rpmdevtools 'dnf-command(builddep)' createrepo_c \
    gcc-toolset-15-gcc-c++ gcc-toolset-15-binutils gcc-toolset-15-gcc-plugin-annobin
GCC15_BIN=/opt/rh/gcc-toolset-15/root/usr/bin
test -x "${GCC15_BIN}/g++"
createrepo_c --quiet "${LOCAL_REPO}"

# Local repo of just-built RPMs (metadata_expire=0: re-read after every update)
cat >"${LOCAL_REPOFILE}" <<EOF
[pneuma-local-build]
name=Pneuma local build repo
baseurl=file://${LOCAL_REPO}
gpgcheck=0
enabled=1
metadata_expire=0
EOF
createrepo_c_refresh

echo "::endgroup::"

echo "::group:: Clone omedora at payload pin"

git clone "${OMEDORA_REPO}" "${SRC}"
git -C "${SRC}" checkout --quiet "${OMEDORA_PIN}"

# EL10 dependency shims (grep-asserted so payload pin bumps can't drift past
# them silently):
# 1. foot is not packaged for EL10; kitty is the fallback terminal.
grep -qE '^Requires:[[:space:]]+foot$' "${COPR_DIR}/omedora.spec"
sed -i 's/^Requires:\([[:space:]]\+\)foot$/Requires:\1kitty/' "${COPR_DIR}/omedora.spec"
# 2. libstdc++ 15 (the newest EL10 toolset) lacks std::ranges::starts_with —
#    a GCC 16 library feature Fedora 44 has. Patch the one use site to the
#    semantically identical ranges::mismatch form (see build/patches/).
grep -qE '^Source2:' "${COPR_DIR}/hyprland.spec"
if ! grep -q '^Patch1:' "${COPR_DIR}/hyprland.spec"; then
    cp /ctx/build/patches/hyprland-el10-ranges-starts-with.patch "${COPR_DIR}/"
    sed -i '/^Source2:/a Patch1:         hyprland-el10-ranges-starts-with.patch' "${COPR_DIR}/hyprland.spec"
fi
grep -q '^Patch1:' "${COPR_DIR}/hyprland.spec"
# 3. rpm 4.19 (c10s) expands section macros inside comments — a comment
#    mentioning %install injects a stray line into the preamble and the spec
#    fails to parse ("Name field must be present"). rpm 4.20 (F44) doesn't.
#    Neutralize section-macro mentions in comment lines (idempotent: requires
#    a non-% character before the macro).
sed -i '/^#/s/\([^%]\)%\(install\|prep\|build\|check\|files\|description\|package\)\b/\1%%\2/g' \
    "${COPR_DIR}/omedora-settings.spec" "${COPR_DIR}/omedora.spec"
# 4. c10s iniparser-devel 4.1 ships headers but no .pc file, so it has no
#    pkgconfig(iniparser) provide. Install it, give the build phase a minimal
#    pkg-config module (removed in cleanup), and relax the BuildRequires.
grep -qE '^BuildRequires:[[:space:]]+pkgconfig\(iniparser\)' "${COPR_DIR}/hyprtoolkit.spec"
sed -i 's/^BuildRequires:\([[:space:]]\+\)pkgconfig(iniparser)$/BuildRequires:\1iniparser-devel/' "${COPR_DIR}/hyprtoolkit.spec"
dnf -y install iniparser-devel
cat > /usr/lib64/pkgconfig/iniparser.pc <<'EOF'
Name: iniparser
Description: INI file parser (pkg-config shim for EL10 iniparser-devel)
Version: 4.1
Libs: -liniparser
Cflags: -I/usr/include/iniparser
EOF

echo "::endgroup::"

echo "::group:: Build the pinned spec set"

# Stage a spec's sources into SOURCES/: bare-filename Sources/Patches come
# from the copr dir (sibling files in the monorepo), URL sources are
# downloaded with spectool, and omedora-self.tar.gz is generated from the
# pinned checkout (self-source mode, mirroring omedora's build-local.sh).
# Downloads are then verified against the committed sha256 pins.
stage_sources() {
    local spec="$1"
    local entry
    if grep -qE '^Source0:[[:space:]]*omedora-self\.tar\.gz[[:space:]]*$' "${spec}"; then
        local self_version
        self_version=$(grep -E '^Version:' "${spec}" | head -n1 | awk '{print $2}')
        git -C "${SRC}" archive --format=tar.gz --prefix="omedora-${self_version}/" \
            -o "${TOPDIR}/SOURCES/omedora-self.tar.gz" "${OMEDORA_PIN}"
    else
        spectool -g -C "${TOPDIR}/SOURCES" "${spec}"
    fi
    # Local sibling files (e.g. omedora.desktop) referenced as bare filenames
    while read -r entry; do
        case "${entry}" in
        *://*) ;;
        omedora-self.tar.gz) ;;
        *)
            if [ -f "${COPR_DIR}/${entry}" ]; then
                cp "${COPR_DIR}/${entry}" "${TOPDIR}/SOURCES/"
            fi
            ;;
        esac
    done < <(rpmspec -P "${spec}" 2>/dev/null | grep -E '^(Source|Patch)[0-9]*:' | awk '{print $2}')
    # Verify downloaded sources against the committed pins (supply-chain gate)
    if [ -f "${spec}.sources" ]; then
        (cd "${TOPDIR}/SOURCES" && sha256sum -c "${spec}.sources")
    fi
}

for name in "${SPECS[@]}"; do
    spec="${COPR_DIR}/${name}.spec"
    test -f "${spec}"
    echo "==> Building ${name}"
    stage_sources "${spec}"
    # epel-multimedia (negativo17, disabled by default but shipped in the base)
    # provides openh264-devel — EPEL's libheif-devel needs pkgconfig(openh264),
    # and EPEL's noopenh264 conflicts with the base's real openh264.
    dnf -y builddep --enablerepo=epel-multimedia "${spec}"
    # _smp_build_ncpus 4: full-width gcc on 8-core hosts peaks past what
    # 16 GB machines survive alongside the tmpfs and dnf caches
    PATH="${GCC15_BIN}:${PATH}" rpmbuild --define "_topdir ${TOPDIR}" \
        --define "_smp_build_ncpus 4" -bb "${spec}"
    # Fold the fresh RPMs into the local repo so the NEXT spec resolves them
    find "${TOPDIR}/RPMS" -name '*.rpm' -exec cp -u {} "${LOCAL_REPO}/" \;
    createrepo_c_refresh
    # /tmp is a tmpfs during image builds — keep the working set small
    rm -rf "${TOPDIR}/BUILD"/* "${TOPDIR}/SOURCES"/* "${TOPDIR}/RPMS"/*
done

echo "::endgroup::"

echo "::group:: Build wtype + brightnessctl from source"

# Tiny C tools omarchy's paste/emoji and brightness flows call; not packaged
# for EL10 anywhere. Build deps ride on the snapshot/removal cycle below.
dnf -y install meson ninja-build wayland-devel libxkbcommon-devel

# renovate: datasource=github-tags depName=atx/wtype
WTYPE_VERSION="v0.4"
git clone --depth 1 --branch "${WTYPE_VERSION}" https://github.com/atx/wtype.git "${WORK}/wtype"
meson setup "${WORK}/wtype/build" "${WORK}/wtype" --prefix=/usr --buildtype=release
ninja -C "${WORK}/wtype/build" install

# renovate: datasource=github-tags depName=Hummer12007/brightnessctl
BRIGHTNESSCTL_VERSION="0.5.1"
git clone --depth 1 --branch "${BRIGHTNESSCTL_VERSION}" https://github.com/Hummer12007/brightnessctl.git "${WORK}/brightnessctl"
make -C "${WORK}/brightnessctl" install PREFIX=/usr

echo "::endgroup::"

echo "::group:: Remove build-time packages"

# Everything dnf added since the snapshot goes — build tools and the large
# -devel closure builddep pulled in. Runtime needs are reinstalled cleanly in
# the next step (source-built binaries above are plain files; removal of their
# build deps does not touch them).
AFTER_LIST="${WORK}/packages-after.txt"
rpm -qa --qf '%{NAME}\n' | sort -u >"${AFTER_LIST}"
comm -13 "${BEFORE_LIST}" "${AFTER_LIST}" >"${WORK}/packages-added.txt"
if [ -s "${WORK}/packages-added.txt" ]; then
    # --noautoremove: never let dependency cleanup sweep pre-existing packages
    # (kernel-devel/gcc closures and GNOME leaves are collateral otherwise)
    xargs -a "${WORK}/packages-added.txt" dnf -y remove --noautoremove
fi

echo "::endgroup::"

echo "::group:: Install the Omarchy runtime set"

# One transaction from the local repo (+ alonid for the lib backports the
# stack was built against — pin libinput/libxkbcommon explicitly so dnf can't
# satisfy the soname with the older c10s builds).
dnf -y --best install --enablerepo=epel-multimedia \
    hyprland \
    hyprland-guiutils \
    hyprpicker \
    hyprsunset \
    xdg-desktop-portal-hyprland \
    starship \
    omedora \
    libinput \
    libxkbcommon

echo "::endgroup::"

echo "::group:: Clean up"

rm -f "${ALONID_REPOFILE}" "${LOCAL_REPOFILE}"
rm -f /usr/lib64/pkgconfig/iniparser.pc
rm -rf "${WORK}"

# Restore the bootc /opt -> /var/opt symlink (toolset RPMs were removed above;
# anything left under /opt is build-phase residue)
if [ ! -L /opt ]; then
    rm -rf /opt
    ln -s /var/opt /opt
fi

echo "::endgroup::"

echo "Omarchy payload + Hyprland stack built and installed!"
