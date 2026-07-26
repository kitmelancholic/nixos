{
  config,
  lib,
  pkgs,
  ...
}:

let
  themeSet = import ../../themes;
  theme = themeSet.themes.${config.kit.theme.active};
  inherit (theme) base16Scheme polarity;
in
{
  options.kit.theme.active = lib.mkOption {
    type = lib.types.enum (builtins.attrNames themeSet.themes);
    inherit (themeSet) default;
    description = "The declarative theme profile used by the Home configuration.";
  };

  config = {
    services.dunst.enable = true;

    stylix = {
      enable = true;
      autoEnable = true;
      inherit base16Scheme polarity;
      image = theme.wallpaper;

      cursor = {
        package = pkgs.bibata-cursors; # Stylix-managed cursor theme
        name = "Bibata-Modern-Ice";
        size = 24;
      };

      fonts = {
        sansSerif = {
          package = pkgs.noto-fonts;
          name = "Noto Sans";
        };
        serif = {
          package = pkgs.noto-fonts;
          name = "Noto Serif";
        };
        monospace = {
          package = pkgs.jetbrains-mono;
          name = "JetBrains Mono";
        };
        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };

      targets = {
        hyprland.enable = false;
        hyprlock.enable = false;
        qt.enable = true;
        waybar.enable = false;
        zed.enable = false;
      };
    };
  };
}
