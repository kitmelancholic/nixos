{ pkgs, ... }:

let
  themeSet = import ../../../themes;
  theme = themeSet.active;
  inherit (theme) base16Scheme polarity;
in
{
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
      waybar.enable = false;
      zed.enable = false;
    };
  };
}
