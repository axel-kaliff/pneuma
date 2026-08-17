# Rebasing a machine onto Pneuma

Runbook for moving an existing `bluefin-dx:lts-hwe` machine to Pneuma. Every
step below was exercised in the Stage-2 VM first; the "Known issues" section
lists what was observed and why it does not block the rebase.

## What survives the rebase

`bootc switch` replaces `/usr` and leaves your data in place:

| Location | Contents | Survives |
|---|---|---|
| `/var/home/<user>` | dotfiles, `.config`, `.ssh`, project trees | yes |
| `/var/lib/flatpak` | installed flatpaks | yes |
| `/var/lib/docker` | images, volumes | yes |
| `/var/lib/tailscale` | node identity, so no re-auth | yes |
| `/var/home/linuxbrew` | brew prefix and packages | yes |
| `/etc` | merged per deployment (see caveat below) | mostly |

**`/etc` caveat.** Each deployment carries its own `/etc`, reconciled with a
3-way merge against the image defaults. Local edits normally carry over, but
this is the one tree where a surprise is possible — hence the backups below.
Freeze config changes during the trial window: edits made under one deployment
are not automatically visible to the other after a rollback.

## Pre-flight

```bash
sudo cp -a /etc/wireguard /root/wireguard.bak     # the one thing you cannot re-derive
nmcli connection show               > ~/nm-pre.txt
flatpak list --app                  > ~/flatpaks-pre.txt
sudo bootc status --format json     > ~/bootc-pre.json
systemctl --failed                                 # expect: 0 loaded units listed
```

Note your two locally-built flatpaks (Felt, PropertyROI) are origin-fragile
regardless of this rebase — they have no remote to reinstall from.

## Rebase

Stage only. Do **not** pass `--apply`; that reboots immediately.

```bash
sudo bootc switch ghcr.io/axel-kaliff/pneuma:stable
sudo bootc status          # booted = bluefin-dx, staged = pneuma
```

Reboot at a time of your choosing. Nothing changes until you do.

```bash
systemctl reboot
```

## The login screen changes — read this before rebooting

Pneuma makes **SDDM** the display manager with the Omarchy greeter. That
greeter is single-user and single-session by design (`Main.qml`): it renders a
password box only — **no username field and no session picker**. It logs in as
`userModel.lastUser` into the session whose name matches `uwsm`.

A first-boot service (`pneuma-omarchy-autologin`) seeds
`/var/lib/sddm/state.conf` with your user and the Omarchy session so the
greeter has someone to authenticate. This was verified working in the VM, on a
machine with exactly one human user.

**If the greeter will not accept a login, or Hyprland fails to start**, switch
to a TTY and fall back to GNOME:

```
Ctrl+Alt+F3
ujust omarchy-greeter gnome
systemctl reboot
```

GDM *does* have a session picker (gear icon), so from there you can choose
either GNOME or Pneuma. Switch back with `ujust omarchy-greeter sddm`.

Autologin is only enabled when all of: exactly one human user, SDDM is the
display manager, and the root filesystem is LUKS-encrypted. Otherwise you get
a normal password prompt.

## Post-boot verification, in this order

```bash
sudo bootc status                     # booted = pneuma, rollback = bluefin-dx
systemctl --failed
sudo wg show                          # handshake against your peer
tailscale status
docker run --rm hello-world
flatpak list --app | diff - ~/flatpaks-pre.txt
brew --version
journalctl -b -p err --no-pager | tail -40
sudo ausearch -m avc --input-logs     # NOT -ts boot, see below
```

Log into GNOME first (it is the lower-risk session), confirm the machine is
healthy, then try the Pneuma/Omarchy session.

## Rollback

```bash
sudo bootc rollback
systemctl reboot
```

This returns to the bluefin-dx deployment. Note it discards any *staged*
update, and the previous deployment's `/etc` comes back with it.

## Known issues (observed in the VM, none blocking)

- **`ausearch -m avc -ts boot` reports zero denials even when denials exist.**
  Use `ausearch -m avc --input-logs`. The `-ts boot` form silently returned 0
  against a log holding 22 real AVCs, so it is not a trustworthy check.
- **`ublue-motd` prints `env.sh: No such file or directory`.** Cosmetic, and
  present in the upstream `bluefin-dx:lts-hwe` base too — not introduced here.
- **`systemd-oomd` can fail on a freshly provisioned `/var`** with
  `226/NAMESPACE`, because its `PrivateTmp` namespace needs `/var/tmp` before
  tmpfiles has created it. A rebase keeps your existing `/var`, where
  `/var/tmp` already exists, so this is a fresh-install artifact.
- **Plymouth splash could not be verified under QEMU.** The initramfs carries
  the Pneuma theme and ships zero DRM kernel modules — exactly matching the
  upstream base image's initramfs — so behaviour on real hardware should match
  what bluefin does today. It is not a Pneuma regression, but it is untested
  on metal.
- **On bib/ISO-provisioned installs** (not rebases) the user's home is created
  with the `default_t` SELinux label, because `genhomedircon` ran before the
  user existed. sshd and sddm-helper are then denied reading it. A rebase is
  unaffected — your home already carries correct labels.
