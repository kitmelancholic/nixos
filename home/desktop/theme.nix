{
  config,
  pkgs,
  ...
}:

{
  services.dunst.enable = true;

  stylix = {
    enable = true;
    autoEnable = true;
    image = config.kit.theme.wallpaper;

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
}
