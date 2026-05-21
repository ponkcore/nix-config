# lib/color.nix — color-token helpers used by theme submodules.
#
# Single source of truth for converting palette hex tokens (`#RRGGBB`)
# into the surface representations that different consumers expect:
#
#   hyprlandRGBA  hex alpha → "rgba(RRGGBBAA)"  (Hyprland 8-digit literal)
#   rasiRGBA      hex       → "rgba(R, G, B, 100%)"  (rofi rasi 4-arg)
#   rasiRGBAof    hex alpha → "rgba(R, G, B, NN%)"   (rofi rasi 4-arg)
#   gtkRGBA       hex alpha → "rgba(R, G, B, A.AA)"  (GTK CSS / hyprlock)
#
# `alpha` is a string fragment (e.g. "ee" / "0.71") — its formatting is
# the responsibility of the consumer. The helpers do NOT validate input
# beyond what is required to extract R/G/B from the hex literal.
#
# Why a dedicated module rather than three lambdas in three files: a
# single place to fix once when a fourth consumer appears (and to be
# obviously correct now — no more `builtins.fromTOML` parser hacks).
let
  # Parse a single 2-character hex pair into an integer 0-255.
  # Implemented via base16 decoding rather than fromTOML's number
  # parser so the helper has no dependency on TOML semantics.
  hexDigitValue = c: let
    digit = {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
      "8" = 8;
      "9" = 9;
      "a" = 10;
      "b" = 11;
      "c" = 12;
      "d" = 13;
      "e" = 14;
      "f" = 15;
      "A" = 10;
      "B" = 11;
      "C" = 12;
      "D" = 13;
      "E" = 14;
      "F" = 15;
    };
  in
    digit.${c}
    or (throw "lib/color.nix: invalid hex digit '${c}'");

  hexPairToInt = pair:
    16 * (hexDigitValue (builtins.substring 0 1 pair)) + (hexDigitValue (builtins.substring 1 1 pair));

  # Strip an optional leading '#' so callers can pass either form.
  stripHash = hex:
    if builtins.substring 0 1 hex == "#"
    then builtins.substring 1 6 hex
    else hex;

  # Decompose a `#RRGGBB` (or `RRGGBB`) literal into its three integer
  # channels. Anything other than a 6-digit hex literal triggers a
  # throw via hexDigitValue above.
  rgbOf = hex: let
    h = stripHash hex;
  in {
    r = hexPairToInt (builtins.substring 0 2 h);
    g = hexPairToInt (builtins.substring 2 2 h);
    b = hexPairToInt (builtins.substring 4 2 h);
  };
in {
  inherit rgbOf stripHash;

  # Hyprland color literals are 8-digit RRGGBBAA hex with no separator.
  # Returns "rgba(RRGGBBAA)".
  hyprlandRGBA = hex: alpha: "rgba(${stripHash hex}${alpha})";

  # Rofi rasi: 4-argument rgba(R, G, B, P%) form. Default 100% opacity.
  rasiRGBA = hex: let
    c = rgbOf hex;
  in "rgba(${toString c.r}, ${toString c.g}, ${toString c.b}, 100%)";

  # Same form with explicit percentage (0-100).
  rasiRGBAof = hex: percent: let
    c = rgbOf hex;
  in "rgba(${toString c.r}, ${toString c.g}, ${toString c.b}, ${toString percent}%)";

  # GTK CSS / hyprlock: floating-point alpha in [0.0, 1.0].
  gtkRGBA = hex: alpha: let
    c = rgbOf hex;
  in "rgba(${toString c.r}, ${toString c.g}, ${toString c.b}, ${toString alpha})";
}
