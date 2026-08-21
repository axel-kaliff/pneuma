###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: pneuma
#
# IMPORTANT: Change "pneuma" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

###############################################################################
# BUILD ARCHITECTURE
###############################################################################
# Pneuma layers on Bluefin LTS (CentOS Stream 10 bootc, GNOME + GDM), which
# already composites @projectbluefin/common and @ublue-os/brew system files
# and ships flatpak preinstall infra, ujust, uupd auto-updates, tailscale,
# and firewalld. There are therefore NO extra OCI context stages here — the
# ctx stage carries only local build scripts and custom files.
#
# CentOS Stream 10 has dnf4 only (no dnf5).
#
# See: https://docs.projectbluefin.io/lts/ for the base image documentation
###############################################################################

# Context stage - local build scripts and custom files only
FROM scratch AS ctx

COPY build /build
COPY custom /custom

# Base Image - Bluefin DX LTS HWE (CentOS Stream 10, GNOME + GDM, docker/dx
# tooling, Fedora HWE kernel). This is the exact image the target machine
# (Darter Pro darp11-b) boots today — dx supplies docker and the HWE kernel
# supplies hardware support the el10 6.12 kernel may lack. Revisit when the
# projectbluefin org starts publishing dx/hwe variants (as of 2026-08-17 it
# only publishes the plain image, and ublue-os publishing stalled 2026-07-14
# amid the org migration — the digest pin documents exactly what was tested).
# Renovate will keep the digest pin up to date.
FROM ghcr.io/ublue-os/bluefin-dx:lts-hwe@sha256:5fe156fc76f5a9e754f66aff55a5ba9c9e7ea582efd8717cacda9c37244c77c2

# Image identity - these define how bootc, fastfetch, and the ublue ecosystem
# recognize your image. Change these to match your project name.
ARG IMAGE_NAME="pneuma"
ARG IMAGE_VENDOR="axel-kaliff"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="bluefin-dx"
# Keep in sync with the actual base image above (bluefin-dx:lts-hwe is c10s);
# the Justfile reads this ARG as the source of truth for the version string.
ARG CENTOS_MAJOR_VERSION="10"
ARG VERSION=""
ARG IMAGE_PRETTY_NAME="Pneuma (CentOS Stream 10)"

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directives mount the ctx stage which includes:
##   - Local build scripts from /build
##   - Local custom files from /custom
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Set dnf options before build scripts (persists across subsequent RUN layers).
RUN dnf -y config-manager --save --setopt=keepcache=1 --setopt=install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    for script in /ctx/build/[1-9]*.sh; do \
        echo "Running ${script}..." && \
        bash "${script}" || exit 1; \
    done
    # [1-9]*.sh: 00-image-info.sh is excluded — it already ran in the layer above

### CLEANUP
## Use Bluefin's clean-stage.sh to remove build artifacts before linting.
## /run is deliberately not mounted as tmpfs here: clean-stage.sh must remove
## image-layer files such as /run/dnf so bootc lint's nonempty-run-tmp check
## passes. The script tolerates busy Buildah bind mounts while clearing contents.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
## Makes /opt writeable by default. The base image already does this; re-assert
## it here so the image stays strict after our own RUN layers.
## If you need /opt as an immutable real directory for build-time packages
## (e.g. google-chrome, docker-desktop), replace the next line with:
##   RUN rm /opt && mkdir /opt
RUN rm -rf /opt && ln -s /var/opt /opt

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
## /run/host is a podman runtime mountpoint during earlier RUNs (clean-stage
## must skip it) — clear the leftover directory here. --skip sysusers: the
## bluefin-lts base ships /etc/passwd+group entries (gnome-initial-setup,
## openvpn, ...) without sysusers.d declarations; that base artifact is not
## fixable from this layer.
RUN rm -rf /run/host && bootc container lint --fatal-warnings --skip sysusers
