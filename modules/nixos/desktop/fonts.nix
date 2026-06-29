{ pkgs, ... }:

{
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      jetbrains-mono
      nerd-fonts.jetbrains-mono
    ];
  };
}
