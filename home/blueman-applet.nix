# blueman-applet.nix — BlueZ pairing-agent session service.
#
# Ownership split:
#   BlueZ backend        — NixOS (modules/nixos/bluetooth.nix)
#   Bluetooth UI         — Caelestia shell (Quickshell.Bluetooth)
#   Pairing agent        — blueman-applet (this module)
#
# Quickshell.Bluetooth wraps org.bluez.Adapter1 and org.bluez.Device1
# (adapter toggle, device list, connect/disconnect, pair, forget) but
# does NOT implement org.bluez.Agent1. The shell's pair() calls
# org.bluez.Device1.Pair, which requires a registered agent for
# authentication callbacks (PIN, passkey, confirmation). Without an
# agent, pairing fails for any device requiring authentication.
#
# blueman-applet's AuthAgent plugin provides org.bluez.Agent1 at
# /org/bluez/agent/blueman on the system bus with KeyboardDisplay
# capability and default-agent status. It handles all 8 agent methods
# (RequestPinCode, DisplayPinCode, RequestPasskey, DisplayPasskey,
# RequestConfirmation, RequestAuthorization, AuthorizeService, Cancel)
# via GTK dialogs and notifications.
#
# ## Single owner: the systemd unit, not XDG autostart
#
# The system-side `services.blueman.enable` installs blueman into
# environment.systemPackages, which ships
# `etc/xdg/autostart/blueman.desktop`. systemd-xdg-autostart-generator
# turns that into `app-blueman@autostart.service`, so TWO applets
# started at every login and raced for the BlueZ agent name. The loser
# exits cleanly (status=0) within ~500ms and logs:
#
#   AgentManager:20 on_register_failed: /org/bluez/obex/agent/blueman
#   org.bluez.obex.Error.AlreadyExists  Agent already exists
#
# Which instance won was a race, not a property of the config. The
# generated unit was winning (verified by cgroup of the live pid), so
# the Home Manager unit below was the one dying — while this module's
# header claimed to be the agent owner.
#
# Fix: keep exactly one owner by suppressing the generated autostart
# unit. A `blueman.desktop` with `Hidden=true` in XDG_CONFIG_HOME
# (~/.config/autostart) takes precedence over the system copy, and
# systemd-xdg-autostart-generator then emits no unit for it. Verified
# against the installed generator with a positive control: baseline
# produced app-blueman@autostart.service, with Hidden=true it produced
# none, and unrelated .desktop entries were unaffected.
#
# Result: `services.blueman-applet` is the single, declarative owner of
# the pairing agent.
#
# Side effect: blueman-tray (started by the applet) provides a
# StatusNotifierItem that appears in the Caelestia bar — a minor
# cosmetic duplicate of the shell's own Bluetooth status icon.
# blueman-manager remains available as a manual debug/admin tool via
# the system profile (services.blueman.enable), so it is NOT added to
# home.packages here — doing so re-introduces the duplicate XDG entry
# that caused the race in the first place.
{
  services.blueman-applet.enable = true;

  # Suppress the app-blueman@autostart.service generated from the
  # system-level blueman.desktop, leaving the HM unit as sole owner.
  # See the long comment above for why this is needed and how it was
  # verified.
  xdg.configFile."autostart/blueman.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Blueman Applet
    # systemd-xdg-autostart-generator skips entries marked Hidden=true,
    # so no app-blueman@autostart.service is generated for this name.
    # The Home Manager services.blueman-applet unit owns the applet.
    Hidden=true
  '';
}
