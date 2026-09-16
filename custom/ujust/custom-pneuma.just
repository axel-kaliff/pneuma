# vim: set ft=make :
########################
### custom-pneuma.just
########################
## Pneuma desktop management (Hyprland + Quickshell alongside GNOME)

# Enable SDDM autologin into the Pneuma session for the current user
[group('Pneuma')]
pneuma-autologin:
    #!/usr/bin/pkexec bash
    /usr/libexec/pneuma-sddm-autologin enable "{{ `id -un` }}"
    rm -f /etc/pneuma/no-autologin
    echo "Autologin takes effect on next boot."

# Disable SDDM autologin and stop the LUKS auto-enable from re-adding it
[group('Pneuma')]
pneuma-autologin-off:
    #!/usr/bin/pkexec bash
    /usr/libexec/pneuma-sddm-autologin disable
    mkdir -p /etc/pneuma
    touch /etc/pneuma/no-autologin
    echo "The SDDM greeter will be shown on next boot."

# Switch the display manager: sddm (Pneuma) or gnome (GDM)
[group('Pneuma')]
pneuma-greeter greeter:
    #!/usr/bin/pkexec bash
    # No --now: never kill the running session; takes effect on reboot
    case "{{ greeter }}" in
    sddm)
        systemctl disable gdm.service
        systemctl enable sddm.service
        ;;
    gnome | gdm)
        systemctl disable sddm.service
        systemctl enable gdm.service
        ;;
    *)
        echo "Usage: ujust pneuma-greeter <sddm|gnome>"
        exit 1
        ;;
    esac
    echo "Display manager set to {{ greeter }} — reboot to apply."

# Re-seed the Pneuma desktop defaults for the current user (never overwrites your files)
[group('Pneuma')]
pneuma-setup:
    #!/usr/bin/bash
    sudo /usr/libexec/pneuma-skel-seed --force --user "$(id -un)"
    echo ""
    echo "Done. Pick the 'Pneuma' session at the login screen (or run"
    echo "'ujust pneuma-autologin' to boot straight into it)."

# Reset the Pneuma desktop configs in $HOME to shipped defaults (destructive, confirms first)
[group('Pneuma')]
pneuma-reset-configs:
    #!/usr/bin/bash
    omarchy-reinstall-configs

# Open the LocalSend firewall port (firewalld replaces Omarchy's ufw rule)
[group('Pneuma')]
pneuma-localsend-firewall:
    #!/usr/bin/pkexec bash
    firewall-cmd --permanent --add-service=localsend
    firewall-cmd --reload
    echo "LocalSend port 53317 (tcp+udp) opened."
