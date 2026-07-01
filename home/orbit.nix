# orbit.nix — Wayland network/bluetooth/VPN/ethernet manager.
#
# Replaces adw-network on this host. Orbit is a Rust + GTK4 +
# layer-shell glassmorphism applet whose CLI exposes a daemon mode
# plus `orbit toggle` / `show` / `hide` / `waybar-status`. The
# daemon is stood up by a Home Manager systemd user unit so it is
# alive at session start and survives waybar reloads; clicks on the
# Waybar wifi tile go through `network-toggle`, which simply runs
# `orbit toggle` (see home/desktop/sessions/hyprland/scripts.nix).
#
# Pulled from our local pkgs overlay (see pkgs/orbit) — upstream is
# not in nixpkgs as of 2026-05.
#
# Theme + position config — declarative under XDG_CONFIG_HOME so the
# daemon picks it up at startup and `orbit reload-theme` /
# `orbit reload-config` keep working live. Colors come from the
# Gruvbox dark medium palette (lib/palette.nix); the only Orbit-specific
# tunables are window position (top-right under the Waybar) and
# window opacity.
{
  pkgs,
  p,
  ...
}: {
  home.packages = [pkgs.orbit];

  # Background daemon — required for `orbit toggle` to have anything
  # to toggle. Mirrors the upstream `orbit.service` from the repo,
  # adapted for Home Manager.
  systemd.user.services.orbit = {
    Unit = {
      Description = "Orbit WiFi/Bluetooth manager daemon";
      # Wait for graphical session and bluetooth.target so
      # bluetoothd is up before Orbit registers its BlueZ pairing
      # agent (org.bluez.Agent1 at /com/orbit/agent, capability
      # KeyboardDisplay). Without this ordering the agent
      # registration can race with bluetoothd startup and silently
      # fail — all subsequent pairing attempts then get "No agent
      # available for request type 2".
      #
      # bluetooth.target is the user-session Bluetooth target that
      # systemd pulls in when bluetooth.service (system unit) is
      # active. It is the correct dependency for user-session units
      # that need bluetoothd. BindsTo is not used because system
      # units are not bindable from user units — if bluetoothd is
      # restarted independently, run:
      #   systemctl --user restart orbit.service
      # to re-register the agent.
      After = ["graphical-session.target" "bluetooth.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.orbit}/bin/orbit daemon";
      Restart = "always";
      RestartSec = 3;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # ── Window placement ────────────────────────────────────────────────
  # The Waybar on this host is centre-anchored and shorter than the
  # monitor (744 px wide, sitting from x≈2028 to x≈2772 on the
  # 1920-wide HDMI). A `top-right` Orbit anchor would park the popup
  # off the bar, hugging the monitor edge. Centring keeps it under
  # the bar's body.
  #
  # margin_top: GTK Layer Shell measures margins from the **inside**
  # of the bar's exclusive zone, so the bar's own 40 px height is
  # already accounted for. 0 lets the popup sit flush against the
  # bar so the two read as a single surface.
  xdg.configFile."orbit/config.toml".text = ''
    position = "top-center"
    margin_top = 0
    margin_right = 8
    margin_bottom = 10
    margin_left = 8

    window_transition = "slidedown"
    window_transition_duration = 200

    stack_transition = "slidehorizontal"
    stack_transition_duration = 200
  '';

  # ── Theme tokens ────────────────────────────────────────────────────
  # Mirrors the Gruvbox dark medium palette used everywhere else in the
  # config. accent_primary is the "highlighted action" colour — we
  # use accent_warm (the same warm beige Waybar uses as @accent) so
  # Orbit's selection rectangles do not clash with the bar's tone.
  # accent_secondary is the "info / link" colour (bright_blue);
  # foreground/background match the Waybar surface so the panel
  # reads as part of the same surface family.
  xdg.configFile."orbit/theme.toml".text = ''
    accent_primary = "${p.accent_warm}"
    accent_secondary = "${p.bright_blue}"
    background = "${p.bg}"
    foreground = "${p.fg}"
    destructive = "${p.bright_red}"
    opacity = 0.95
  '';

  # ── Custom CSS ──────────────────────────────────────────────────────
  # Override Orbit's default 8 px window padding (it carries GTK4's
  # client-side decoration aura into the layer-shell surface,
  # showing up as faint angular corners at the top edge where the
  # popup butts against the Waybar). Set padding to 0 and override
  # the window's box-shadow + decoration to flatten the surface.
  xdg.configFile."orbit/style.css".text = ''
    window {
      padding: 0;
      margin: 0;
      box-shadow: none;
    }

    decoration {
      box-shadow: none;
      margin: 0;
    }

    /* Square every corner so the popup reads as a slab; the
       angular antialiasing artefacts that show on dark
       backgrounds around curved edges are gone when the radius
       is 0. */
    .background {
      box-shadow: none;
      border-radius: 0;
    }

    window {
      border-radius: 0;
    }

    /* Footer slab — upstream paints it with `section_bg` as a
       distinct opaque card under the action buttons. On the warm
       Gruvbox surface this reads as a brighter rectangle behind
       the row, breaking the "single slab" illusion. Make it
       transparent and drop the top divider so the footer dissolves
       into the panel body. */
    .orbit-footer {
      background-color: transparent;
      background-image: none;
      border-top: none;
      border-radius: 0;
    }
  '';
}
