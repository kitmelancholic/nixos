{
  config,
  constants,
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
    settings = import ./settings.nix {
      inherit
        config
        constants
        lib
        pkgs
        ;
    };
  };
}
