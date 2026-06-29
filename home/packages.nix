{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kitty # fallback terminal
    wofi
    waybar
    dunst # notifications

    grim
    slurp
    swappy
    wl-clipboard
    pavucontrol

    fastfetch
    btop

    xclip
    xsel

    nnn # explorer
    nautilus
    file-roller
    evince
    loupe
    vivaldi # browser
    vivaldi-ffmpeg-codecs # Extra media codecs for Vivaldi
    qbittorrent
    anki
    telegram-desktop

    unityhub
    mono # Unity/legacy .NET compatibility
    goose-cli

    prismlauncher
  ];
}
