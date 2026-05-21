# wlsunset.nix — automatic Wayland night light.
# Adjusts color temperature according to civil twilight at the given
# coordinates (Moscow, 55.75°N 37.62°E). Runs as a HM-managed user
# service.
_: {
  services.wlsunset = {
    enable = true;
    latitude = 55.75;
    longitude = 37.62;
  };
}
