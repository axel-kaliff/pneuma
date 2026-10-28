---
name: finpilot-build
description: >-
  Containerfile multi-stage build, image digest pinning in FROM lines,
  Justfile local build recipes, and build script conventions.
  Use when changing Containerfile, Justfile, or build/*.sh.
---

# finpilot Build System

## When to Use

- Editing `Containerfile` (ARGs, stages, base image, RUN directives)
- Editing `Justfile` (build recipe, tag strategy, version computation)
- Adding or modifying `build/*.sh` scripts
- Debugging why a local build fails differently from CI

## When NOT to Use

- CI workflow changes (`.github/workflows/`) — use `finpilot-ci`
- Runtime customizations (`custom/`) — use `finpilot-custom`

## Core Process

1. **Identify which `FROM` line or ARG drives your change**
2. **All image digests** are pinned directly in `Containerfile` `FROM` lines; Renovate updates them
3. **Run `just build`** locally before opening a PR; `just lint` to shellcheck
4. **Add `00-` prefix** for metadata scripts, `10-` for main packages, `20+` for extras

## Image Pinning Pattern

All OCI images are pinned directly in `Containerfile` `FROM` lines. Renovate's
built-in `dockerfile` manager updates every digest.

```dockerfile
# OCI context images
FROM ghcr.io/projectbluefin/common:latest@sha256:<current> AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:<current> AS brew

# Base image
ARG FEDORA_MAJOR_VERSION="44"
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:<current>
```

**Never update digests manually.** Let Renovate open PRs for digest bumps.

To change an image or tag, edit its `FROM` line. To bump the Fedora major
release, update both the `FEDORA_MAJOR_VERSION` ARG and the base image tag.

## Build Script Conventions

### Numbering

| Prefix             | Purpose                                                                               |
| ------------------ | ------------------------------------------------------------------------------------- |
| `00-image-info.sh` | Metadata only: writes `image-info.json`, customises `os-release`                      |
| `10-build.sh`      | Main script: copies custom files, `dnf install`                                       |
| `20-*.sh`          | Optional extras: third-party repos, COPR packages                                     |
| `30-*.sh`          | Optional desktop swaps                                                                |
| `37-hyprglass.sh`  | Hyprglass built against the installed Hyprland EVR; user's config loads the plugin    |
| `clean-stage.sh`   | Always runs last: reverts `keepcache`, disables fedora flatpak repo, clears artefacts |

### Template build script rules

- **Default packages**: build scripts in the template must have **no packages installed by default** — only commented examples. Users add their own.
- **Exception**: `dnf -y install tmux` is intentionally present as a minimal smoke-test that the DNF cache is warm. Do not remove it.
- Always use `dnf` (dnf4) — dnf5 does not exist on CentOS Stream 10; never `yum` or `rpm-ostree`
- Always use `dnf -y install` (non-interactive)
- COPR: enable → install → `copr_install_isolated` (auto-disables); never leave a repo enabled

### NVIDIA GPU support

NVIDIA support is a build-time option activated by renaming the example script and adding its explicit Containerfile `RUN` block:

```bash
mv build/40-nvidia.sh.example build/40-nvidia.sh
# Add the standard RUN block for /ctx/build/40-nvidia.sh after 10-build.sh.
# See build/README.md.
just build
```

All NVIDIA logic is self-contained in `40-nvidia.sh`. When both the script and its explicit Containerfile `RUN` block are activated, it provisions the NVIDIA driver, CDI container toolkit, Mutter kms-modifiers, and bootc kernel args directly into the base image — no separate image variant, no `IMAGE_NAME` gating.

Deactivate by removing its Containerfile `RUN` block and renaming the script back to `.example`. See `build/40-nvidia.sh.example` for the full implementation.

### 00-image-info.sh branding

The comment in the `os-release` append block must use `${IMAGE_NAME}`:

```bash
cat >> "${OS_RELEASE}" << EOF

# ${IMAGE_NAME} image identity   ← use variable, not literal "finpilot"
VARIANT_ID="${IMAGE_FLAVOR}"
...
EOF
```

## Base Image

Pneuma follows `ghcr.io/ublue-os/bluefin:lts-hwe-testing-50`, built by
`ublue-os/bluefin-lts` from its `main` branch: CentOS Stream 10, GNOME 50,
Fedora CoreOS stable kernel. `sync-base-image.yml` owns the digest pin;
`.github/renovate.json` disables Renovate for it.

- Tag choice: `-hwe` keeps the CoreOS kernel (plain `lts-testing` ships the
  el10 6.12 kernel) and `-50` keeps GNOME 50 (plain `lts-hwe-testing` is
  GNOME 49). No non-testing `lts*` tag exists; the upstream `lts` branch has
  not been promoted since 2026-06-21.
- A green sync run does not prove the base is fresh. The job compares
  digests, so an abandoned upstream reads as "already pinned":
  `projectbluefin/bluefin-lts:stable` stopped rebuilding on 2026-10-12 and
  its repo was archived as `thallium-suite/uranium` on 2026-10-15 while sync
  stayed green. Judge freshness by the upstream image's `Created` date
  (`skopeo inspect docker://<base-tag>`).
- Switching the base: change the `FROM` repo:tag and digest and the Renovate
  `matchDepNames` rule, then compare the kernel (`ostree.linux` label), the
  GNOME version and the `ujust devmode` recipe against the running image.
- The kernel must find `modprobe` at its `CONFIG_MODPROBE_PATH`
  (`grep MODPROBE_PATH /usr/lib/modules/*/config`). Fedora kernels use
  `/usr/bin/modprobe`; el10 kmod ships only `/usr/sbin/modprobe`, so
  `10-build.sh` adds the link. Without it the initramfs cannot autoload `xfs`
  and boot stops at `Failed to mount sysroot.mount` with no journal saved
  (2026-10-28; tunaOS#2518 is the same failure).

## Common Rationalizations

| Rationalization                                                      | Reality                                                                                                |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| "I'll skip the digest pin and use a floating tag."                   | Non-reproducible builds and breaks supply-chain traceability. The `FROM` line should always be pinned. |
| "Renovate won't notice a manually pinned digest in `Containerfile`." | Renovate is disabled for the base pin on purpose — `sync-base-image.yml` owns it (see Base Image).     |
| "I'll use `dnf5` like upstream Bluefin does."                        | Never. CentOS Stream 10 ships dnf4 only — `dnf` is the canonical tool here (bluefin-lts does the same). |

## Red Flags

- Floating tags (`FROM image:latest` without `@sha256:...`)
- `FROM ${FOO}@${BAR}` where `BAR` could be empty
- `dnf`, `yum`, or `rpm-ostree` in any build script
- COPR left enabled after package install (repo file not removed by `copr_install_isolated`)
- `# finpilot image identity` hardcoded instead of `# ${IMAGE_NAME} image identity`

## Verification

- [ ] Are all `FROM` lines pinned with `@sha256:...`?
- [ ] Does `build/00-image-info.sh` use `${IMAGE_NAME}` in the os-release comment?
- [ ] Does `just build` succeed locally?
- [ ] Does `just lint` pass clean (shellcheck)?
- [ ] Does `bootc container lint --fatal-warnings` pass in CI?
