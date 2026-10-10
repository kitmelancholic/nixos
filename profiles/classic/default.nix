{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.kit.classic = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Human-readable name of the classic palette profile.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.path;
      description = "Wallpaper used by the classic profile.";
    };
  };

  imports = [
    ../../home/desktop/theme.nix
    ../../home/desktop/wallpaper.nix
    ../../home/osd.nix
    ../../home/power.nix
    ../../home/screenshots.nix
    ../../home/waybar.nix
    ../common/hyprpolkitagent.nix
  ];

  config = {
    services.dunst.enable = true;
    home.packages = [ pkgs.wofi ];

    wayland.windowManager.hyprland.settings = import ../../home/hyprland/settings.nix {
      inherit config lib;
    };
  };
}
