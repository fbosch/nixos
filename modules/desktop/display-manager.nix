_:
{
  flake.modules.nixos.desktop = { pkgs, lib, meta, ... }: {
    services.getty.autologinUser = meta.user.username;
  };
}
