{
  config,
  lib,
  pkgs,
  ...
}:

{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    package = null;
    portalPackage = null;
    settings = import ./invariant-settings.nix {
      inherit
        config
        lib
        pkgs
        ;
    };
  };
}
