# Build Scripts

This directory contains build scripts used during image creation. The default Containerfile explicitly runs the required scripts; extra scripts must be explicitly added to the Containerfile.

## How It Works

Scripts are named with a number prefix (e.g., `10-build.sh`, `20-onepassword.sh`) and run in ascending order during the container build process.

## Included Scripts

- **`10-build.sh`** - Main build script for base system modifications, package installation, and service configuration
- **`20-dotfiles.sh`** - Nerd Fonts and the pneuma dotfiles snapshot (stowed per-user at first boot)
- **`30-ghostty.sh`** - Source-built Ghostty terminal (pinned Zig toolchain, `-Dcpu=baseline`)
- **`35-omarchy-packages.sh`** - Omarchy dependencies from c10s/EPEL 10/COPR
- **`36-omarchy-payload.sh`** - Omedora payload + Hyprland 0.56 stack, rpmbuilt from pinned specs
- **`37-omarchy-config.sh`** - SDDM/session/skel configuration + smoke checks; makes SDDM the default display manager
- **`38-omarchy-qml-patches.sh`** - EL10/Qt 6.10 QML source fixes for the omarchy shell (ES3 reserved words used as identifiers); also fixed upstream in the pneuma-el10 omedora fork
- **`39-pomodoro.sh`** - `pneuma.pomodoro` focus-timer bar plugin seeded into `/etc/skel`
- **`40-branding.sh`** - Plymouth boot splash and GRUB theme (runs last so the pneuma splash owns the initramfs)

## Example Scripts

- **`20-onepassword.sh.example`** - Example showing how to install software from third-party RPM repositories (Google Chrome, 1Password)
- **`40-nvidia.sh.example`** - Example showing how to add NVIDIA drivers and CDI container support

To use an example script:
1. Rename it to remove the `.example` extension (for example, `mv build/20-onepassword.sh.example build/20-onepassword.sh`).
2. Add the standard `RUN` block below after the `10-build.sh` block in `Containerfile`, replacing `NN-example.sh` with the renamed script.
3. Run `just build`.

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/NN-example.sh
```

## Creating Your Own Scripts

Create numbered scripts for different purposes:

```bash
# 10-build.sh - Base system (already exists)
# 20-drivers.sh - Hardware drivers
# 30-development.sh - Development tools
# 40-gaming.sh - Gaming software
# 50-cleanup.sh - Final cleanup tasks
```

### Script Template

```bash
#!/usr/bin/env bash
set -oue pipefail

echo "Running custom setup..."
# Your commands here
```

### Best Practices

- **Use descriptive names**: `40-nvidia.sh` is better than `40-stuff.sh`
- **One purpose per script**: Easier to debug and maintain
- **Clean up after yourself**: Remove temporary files and disable temporary repos
- **Test incrementally**: Add one script at a time and test builds
- **Comment your code**: Future you will thank present you

### Disabling Scripts

To disable an activated script, remove its corresponding `RUN` block from `Containerfile` and rename it back to `.example` (or remove it).

## Execution Order

The template runs scripts explicitly, rather than automatically discovering files by prefix. Place extra script blocks after `10-build.sh` and before `clean-stage.sh`. Use numbered names to communicate the intended order.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx`
- Use dnf (dnf4) for package management — dnf5 does not exist on CentOS Stream 10
- Always use `-y` flag for non-interactive installs
