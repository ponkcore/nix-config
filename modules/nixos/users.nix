# users.nix — primary user account, shell, group memberships.
#
# Username is injected by lib/mkHost.nix as specialArg. Adding a new
# user means duplicating mkHost call and importing this module twice
# is wrong — instead, add another `users.users.<name>` block in a
# host-specific module and pass extra usernames through specialArgs.
#
# Universal: applies to any host. The `docker` group is included even
# when Docker isn't enabled — it's harmless if the daemon never starts.
{
  pkgs,
  username,
  ...
}: {
  users.users.${username} = {
    isNormalUser = true;
    description = "Primary user";
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "render"
      "libvirtd"
      "docker"
    ];
    shell = pkgs.fish;
  };

  # Fish — system-level enable, full configuration in Home Manager.
  programs.fish.enable = true;
}
