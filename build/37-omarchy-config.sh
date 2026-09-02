#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Omarchy v4 configuration — SDDM, sessions, skel, overrides, smoke checks
###############################################################################
# Third of the three omarchy scripts (see 35 for the package matrix, 36 for
# the payload build). Design decisions:
#   - GNOME (from the bluefin-lts base) stays installed; the Omarchy and GNOME
#     sessions coexist and are both offered by SDDM and GDM.
#   - SDDM becomes the default display manager (Omarchy v4's own login flow);
#     GDM stays installed and switchable via ujust omarchy-greeter gnome.
#   - Ghostty (built in script 30) stays the default terminal; kitty is the
#     fallback (EL10 has no foot).
#   - Update subsystem is remapped to bootc/brew/flatpak via the overrides
#     overlay in /usr/share/pneuma/omarchy-overrides (installed below).
###############################################################################

echo "::group:: Configure SDDM (Omarchy greeter)"

# Vendor config in /usr/lib (repo convention — /etc is user-owned on ostree;
# SDDM reads /usr/lib/sddm/sddm.conf.d before /etc/sddm.conf.d).
install -Dm644 /ctx/build/files/usr/lib/sddm/sddm.conf.d/10-pneuma-wayland.conf \
    /usr/lib/sddm/sddm.conf.d/10-pneuma-wayland.conf
install -Dm644 /ctx/build/files/usr/lib/sddm/sddm.conf.d/20-pneuma-theme.conf \
    /usr/lib/sddm/sddm.conf.d/20-pneuma-theme.conf

# Surface the Omarchy SDDM theme + greeter compositor config where the
# sddm.conf.d files expect them (payload lives under /usr/share/omarchy).
mkdir -p /usr/share/sddm/themes
ln -sfn /usr/share/omarchy/default/sddm/omarchy /usr/share/sddm/themes/omarchy
ln -sfn /usr/share/omarchy/default/sddm/hyprland.lua /usr/share/sddm/hyprland.lua

# EPEL's sddm RPM ships a sysusers.d entry for the sddm user. Assert, and
# self-heal if a future package change drops it (never useradd at build on
# ostree — sysusers materialize the user at first boot).
if ! grep -rqsE '^u[[:space:]]+sddm([[:space:]]|$)' /usr/lib/sysusers.d/; then
    cat > /usr/lib/sysusers.d/pneuma-sddm.conf << 'EOF'
u sddm - "SDDM display manager" /var/lib/sddm
EOF
fi

# Boot-time group membership service: the SDDM greeter session is Hyprland
# here, so the sddm user needs video/render membership for DRM access. On
# bootc, /etc/group persists across rebases and sysusers "m" directives don't
# apply when the groups live in /usr/lib/group — the service fixes it at boot.
install -Dm755 /ctx/build/files/usr/libexec/pneuma-greeter-groups /usr/libexec/pneuma-greeter-groups
install -Dm644 /ctx/build/files/usr/lib/systemd/system/pneuma-greeter-groups.service /usr/lib/systemd/system/pneuma-greeter-groups.service
systemctl enable pneuma-greeter-groups.service

echo "::endgroup::"

echo "::group:: Switch Display Manager to SDDM"

# Both gdm.service and sddm.service alias display-manager.service; release
# the alias held by the base image first or the enable fails.
# Switch back at runtime with: ujust omarchy-greeter gnome
systemctl disable gdm.service
systemctl enable sddm.service

# Belt-and-braces against preset re-application on ostree deploys
cat > /usr/lib/systemd/system-preset/45-pneuma-dm.preset << 'EOF'
enable sddm.service
disable gdm.service
EOF

echo "::endgroup::"

echo "::group:: Keep Ghostty the Default Terminal"

# All Omarchy terminal launches route through xdg-terminal-exec (Super+Return,
# TUI menu entries). Inside a Hyprland session the desktop-specific list wins,
# and omedora-settings ships it with only foot — overwrite both lists with
# Ghostty first. Ghostty's desktop ID is asserted in the smoke checks below.
cat > /usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list << 'EOF'
# Terminal preference order for xdg-terminal-exec in Hyprland sessions.
# Users override via ~/.config/xdg-terminals.list (omarchy default terminal <x>).
com.mitchellh.ghostty.desktop
kitty.desktop
EOF

cat > /usr/share/xdg-terminals.list << 'EOF'
com.mitchellh.ghostty.desktop
kitty.desktop
EOF
# The base's GNOME terminal joins the global fallback list when present
if [ -f /usr/share/applications/org.gnome.Ptyxis.desktop ]; then
    echo "org.gnome.Ptyxis.desktop" >> /usr/share/xdg-terminals.list
fi

# Seed the per-user preference for new users too (settings skel doesn't ship one)
install -Dm644 /usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list \
    /etc/skel/.config/xdg-terminals.list

echo "::endgroup::"

echo "::group:: Image Viewer Default (Loupe, not imv)"

# Script 35 drops imv (no EL10 package) and relies on the Loupe flatpak for
# image viewing, but omedora-settings still seeds an imv.desktop into skel.
# With no explicit default anywhere, xdg falls back to the mimeinfo.cache
# association and opens a binary that does not exist -- images silently fail.
rm -f /etc/skel/.local/share/applications/imv.desktop

# Seed an explicit default so the fallback never gets a vote (same approach as
# the xdg-terminals.list seed above). Loupe ships in custom/flatpaks/install.list.
install -dm755 /etc/skel/.config
cat > /etc/skel/.config/mimeapps.list << 'EOF'
[Default Applications]
image/png=org.gnome.Loupe.desktop
image/jpeg=org.gnome.Loupe.desktop
image/gif=org.gnome.Loupe.desktop
image/webp=org.gnome.Loupe.desktop
image/bmp=org.gnome.Loupe.desktop
image/tiff=org.gnome.Loupe.desktop
EOF

test ! -e /etc/skel/.local/share/applications/imv.desktop

echo "::endgroup::"

echo "::group:: Chromium Compat Shims"

# Omarchy scripts hardcode Arch's names (chromium binary, chromium.desktop);
# Fedora/EPEL ship chromium-browser. Shim rather than patch a dozen scripts.
test -x /usr/bin/chromium-browser
if [ ! -e /usr/bin/chromium ]; then
    ln -s /usr/bin/chromium-browser /usr/bin/chromium
fi
if [ ! -e /usr/share/applications/chromium.desktop ] &&
    [ -f /usr/share/applications/chromium-browser.desktop ]; then
    ln -s chromium-browser.desktop /usr/share/applications/chromium.desktop
fi

echo "::endgroup::"

echo "::group:: Scope Omarchy User Units to Hyprland Sessions"

# omedora-settings ships user units WantedBy=graphical-session.target with no
# desktop condition — they would also start under GNOME. uwsm sets
# XDG_CURRENT_DESKTOP=Hyprland (omedora.desktop: uwsm start ... -D Hyprland)
# and imports it into the user manager before graphical-session.target, so
# this condition scopes them cleanly. Under GNOME the variable is GNOME and
# the units are skipped.
shopt -s nullglob
for unit in /usr/lib/systemd/user/omarchy-*.service; do
    dropin_dir="${unit}.d"
    mkdir -p "${dropin_dir}"
    cat > "${dropin_dir}/50-pneuma-hyprland-only.conf" << 'EOF'
# Installed by pneuma (build/37-omarchy-config.sh):
# don't start Omarchy session services under GNOME.
[Unit]
ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland
EOF
done

# Dropped-package cleanup: bluez-tools (bt-agent) and fcitx5 are not packaged
# for EL10 (see script 35). Remove their user units so they can't fail at
# login, and the fcitx environment.d file — it applies to ALL systemd user
# sessions, which would force fcitx IM variables onto GNOME's ibus setup.
rm -f /usr/lib/systemd/user/bt-agent.service
rm -f /usr/lib/systemd/user/omarchy-fcitx5.service
rm -f /usr/lib/environment.d/10-omarchy-fcitx.conf

# limine/snapper don't exist on bootc — drop the notifier so it can't error
# at login (bootc deployments are the rollback mechanism).
rm -f /etc/skel/.config/autostart/limine-snapper-notify.desktop

# Same scoping for XDG autostart entries seeded from /etc/skel:
# systemd's xdg-autostart-generator honors OnlyShowIn.
for desktop in /etc/skel/.config/autostart/*.desktop; do
    grep -q '^OnlyShowIn=' "${desktop}" || echo 'OnlyShowIn=Hyprland;' >> "${desktop}"
done
shopt -u nullglob

# Pre-seed migration markers: a fresh install has nothing to migrate, so every
# shipped migration is marked done (upstream's installer does this via
# omarchy-provision-user --first-install, which nothing calls on pneuma).
# Without markers every login toasts "N pending migrations" and omarchy-migrate
# would replay years of Arch-era migrations against a pristine home.
install -d /etc/skel/.local/state/omarchy/migrations
for migration in /usr/share/omarchy/migrations/*.sh; do
    touch "/etc/skel/.local/state/omarchy/migrations/$(basename "${migration}")"
done

echo "::endgroup::"

echo "::group:: Default Keyboard Layouts (US + Swedish)"

# omedora-settings ships the skel input.lua fully commented; append an active
# override so every user seeded from skel gets both layouts. Existing users
# keep their own copy (pneuma-omarchy-user-setup never clobbers).
cat >> /etc/skel/.config/hypr/input.lua << 'EOF'

-- Pneuma default: US + Swedish layouts, toggle with Left Alt + Right Alt.
hl.config({
  input = {
    kb_layout = "us,se",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
  },
})
EOF

echo "::endgroup::"

echo "::group:: Vim-Style Window Navigation"

# Same skel-append pattern as the layouts above: omedora-settings ships
# bindings.lua fully commented. SUPER + hjkl focuses, + SHIFT swaps. The three
# defaults that owned those keys move to the same key with ALT added, except
# SUPER + ALT + K (already the tmux cheatsheet), so the Omarchy keybindings
# menu takes SHIFT + ALT. Unbinds must precede the rebinds.
cat >> /etc/skel/.config/hypr/bindings.lua << 'EOF'

-- Pneuma default: vim-style window navigation.
hl.unbind("SUPER + J") -- was: Toggle window split
hl.unbind("SUPER + K") -- was: Keybindings
hl.unbind("SUPER + L") -- was: Toggle workspace layout

o.bind("SUPER + ALT + J", "Toggle window split", hl.dsp.layout("togglesplit"))
o.bind("SUPER + SHIFT + ALT + K", "Keybindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

o.bind("SUPER + H", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + J", "Focus on below window", hl.dsp.focus({ direction = "d" }))
o.bind("SUPER + K", "Focus on above window", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + L", "Focus on right window", hl.dsp.focus({ direction = "r" }))

o.bind("SUPER + SHIFT + H", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + SHIFT + J", "Swap window down", hl.dsp.window.swap({ direction = "d" }))
o.bind("SUPER + SHIFT + K", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + SHIFT + L", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
EOF

echo "::endgroup::"

echo "::group:: Laptop Panel Below External Monitors"

# Same skel-append pattern again. Hyprland resolves eDP-1 first (monitor ID 0),
# so putting auto-center-down on it leaves nothing to center against and the
# monitors land side by side. Inverting it works: pin eDP-1 as the anchor and
# let everything else auto-center above. Both rules reuse the file's own
# omarchy_monitor_scale local, so omarchy-hyprland-monitor-scaling (which only
# rewrites that one line) keeps working. Machines with no eDP-1 fall through
# the second rule; a desktop with several externals stacks them upward.
cat >> /etc/skel/.config/hypr/monitors.lua << 'EOF'

-- Pneuma default: the laptop panel sits centered below any external monitor.
hl.monitor({ output = "", mode = "preferred", position = "auto-center-up", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
EOF

echo "::endgroup::"

echo "::group:: Brew PATH for uwsm Sessions"

# uwsm recomposes the session environment at login (prepare-env.sh sources
# uwsm/env.d/* fragments) and exports its PATH into the systemd user manager,
# overriding the base's profile.d plumbing for GUI-launched apps. Without this
# fragment, omarchy menu -> ghostty -e nvim/lazygit can't find brew binaries.
# Users can override via ~/.config/uwsm/env.d/. (POSIX sh)
mkdir -p /usr/share/uwsm/env.d
cat > /usr/share/uwsm/env.d/50-pneuma-brew << 'UWSMBREWEOF'
# Append Homebrew to the uwsm session PATH (system binaries keep priority).
if [ -d /home/linuxbrew/.linuxbrew ]; then
  HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
  export HOMEBREW_PREFIX
  case ":${PATH}:" in
  *":${HOMEBREW_PREFIX}/bin:"*) ;;
  *) export PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin" ;;
  esac
fi
UWSMBREWEOF

echo "::endgroup::"

echo "::group:: Install Pneuma Omarchy Integration"

# First-boot per-user config seeding + conditional SDDM autologin
install -Dm755 /ctx/build/files/usr/libexec/pneuma-omarchy-user-setup /usr/libexec/pneuma-omarchy-user-setup
install -Dm755 /ctx/build/files/usr/libexec/pneuma-omarchy-autologin /usr/libexec/pneuma-omarchy-autologin
install -Dm755 /ctx/build/files/usr/libexec/pneuma-sddm-autologin /usr/libexec/pneuma-sddm-autologin
install -Dm644 /ctx/build/files/usr/lib/systemd/system/pneuma-omarchy-setup.service /usr/lib/systemd/system/pneuma-omarchy-setup.service
install -Dm644 /ctx/build/files/usr/lib/systemd/system/pneuma-omarchy-autologin.service /usr/lib/systemd/system/pneuma-omarchy-autologin.service
systemctl enable pneuma-omarchy-setup.service
systemctl enable pneuma-omarchy-autologin.service

# firewalld service definition for LocalSend (Omarchy expects ufw; pneuma
# keeps firewalld). Enable with: firewall-cmd --permanent --add-service=localsend
install -Dm644 /ctx/build/files/usr/lib/firewalld/services/localsend.xml \
    /usr/lib/firewalld/services/localsend.xml

# Overrides overlay: remap the pacman/snapper update subsystem to
# bootc/brew/flatpak. The omarchy dispatcher execs subcommands by absolute
# path from its own directory, so PATH shadowing can't intercept them — the
# binaries must be replaced. On bootc RPMs never change at runtime, so
# install-over-RPM at build time is deterministic on every rebuild.
# Sources stay visible in /usr/share/pneuma/omarchy-overrides for docs.
mkdir -p /usr/share/pneuma
cp -r /ctx/build/files/usr/share/pneuma/omarchy-overrides /usr/share/pneuma/omarchy-overrides
for override in /usr/share/pneuma/omarchy-overrides/bin/*; do
    install -m755 "${override}" "/usr/bin/$(basename "${override}")"
done

# Note: omedora-settings ships /etc drop-ins (sysctl, logind, resolved, oomd,
# sudoers) reviewed and accepted as-is. Judgment call kept Omarchy-authentic:
# logind HandlePowerKey=ignore applies system-wide (also GNOME) — drop with
# `rm -f /etc/systemd/logind.conf.d/10-ignore-power-button.conf` if unwanted.

echo "::endgroup::"

echo "::group:: Record Manifest + Smoke Checks"

# Manifest for supportability — record exactly what each build shipped (the
# COPR stack is pinned, but the yselkowitz and EPEL packages drift).
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    'omedora*' 'hypr*' 'quickshell*' 'uwsm*' 'sddm*' chromium kitty starship libinput libxkbcommon | sort \
    > /usr/share/pneuma/omarchy-build-manifest.txt
cat /usr/share/pneuma/omarchy-build-manifest.txt

# Cheap in-container assertions — fail the build here, not in a VM.
rpm -q omedora omedora-settings hyprland hyprland-no-session quickshell uwsm \
    sddm sddm-wayland-generic xdg-desktop-portal-hyprland chromium kitty starship ttfx
test -x /usr/bin/ttfx # omarchy-launch-screensaver exits silently without it
test -x /usr/bin/Hyprland
test -x /usr/bin/start-hyprland
test -x /usr/bin/omarchy-menu
test -x /usr/bin/uwsm
test -x /usr/bin/wtype
test -x /usr/bin/brightnessctl
test -f /usr/share/wayland-sessions/omedora.desktop
test -f /usr/share/wayland-sessions/hyprland.desktop # omedora.desktop Exec needs it
# GNOME must survive as the second session (bluefin-lts base)
compgen -G '/usr/share/wayland-sessions/gnome*.desktop' > /dev/null
rpm -q gnome-shell gdm gnome-session-wayland-session gnome-control-center gettext
# Portal selection stays per-desktop: hyprland-portals.conf for Hyprland
# sessions, gnome's own for GNOME — a global portals.conf would break one side
test -f /usr/share/xdg-desktop-portal/hyprland-portals.conf
test ! -f /usr/share/xdg-desktop-portal/portals.conf
test -e /usr/share/sddm/themes/omarchy
test -e /usr/share/sddm/hyprland.lua
test -f /usr/share/applications/com.mitchellh.ghostty.desktop # terminal-list ID
[[ "$(readlink /etc/systemd/system/display-manager.service)" == *sddm.service ]]
[[ "$(grep -v '^#' /usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list | head -n1)" == "com.mitchellh.ghostty.desktop" ]]
grep -rqs 'sddm' /usr/lib/sysusers.d/
grep -q 'kb_layout = "us,se"' /etc/skel/.config/hypr/input.lua
grep -q 'o.bind("SUPER + H", "Focus on left window"' /etc/skel/.config/hypr/bindings.lua
grep -q 'position = "auto-center-up"' /etc/skel/.config/hypr/monitors.lua
# No grep -q here: -q exits at first match and fc-list's remaining writes
# then die with SIGPIPE (exit 141), which pipefail turns into a build failure.
fc-list | grep -i 'JetBrainsMono Nerd Font' > /dev/null
# Minimum-version guard: the Quickshell shell + Lua configs need Hyprland 0.56+
rpm -q --qf '%{VERSION}' hyprland-no-session | grep -qE '^(0\.(5[6-9]|[6-9][0-9])|[1-9])'
# Every shipped migration must have a pre-seeded skel marker (fresh installs
# have nothing to migrate); count equality catches payload layout changes too.
[[ "$(find /usr/share/omarchy/migrations -maxdepth 1 -name '*.sh' | wc -l)" -gt 0 ]]
[[ "$(find /usr/share/omarchy/migrations -maxdepth 1 -name '*.sh' | wc -l)" == \
    "$(find /etc/skel/.local/state/omarchy/migrations -maxdepth 1 -name '*.sh' | wc -l)" ]]

echo "::endgroup::"

echo "Omarchy desktop configuration complete!"
