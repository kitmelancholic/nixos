{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Desktop shell
    kitty # fallback terminal
    wofi
    waybar
    dunst # notifications

    # Wayland utilities
    grim
    slurp
    swappy
    wl-clipboard
    pavucontrol

    # System tools
    fastfetch
    btop
    xclip
    xsel

    # Files and documents
    nnn # explorer
    nautilus
    file-roller
    evince
    loupe

    # Internet and communication
    vivaldi # browser
    vivaldi-ffmpeg-codecs # Extra media codecs for Vivaldi
    qbittorrent
    anki
    telegram-desktop

    # Development adjacent
    unityhub
    mono # Unity/legacy .NET compatibility
    goose-cli

    # Games
    prismlauncher
  ];
}
