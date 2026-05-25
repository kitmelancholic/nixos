{ pkgs, ... }:

{
  home.packages = with pkgs; [
    git
    kitty
    wofi
    waybar 
    dunst #notifications

    grim
    slurp
    wl-clipboard
    pavucontrol

    fastfetch

    spice-vdagent
    xclip
    xsel

    nnn #explorer
    firefox #browser
    qbittorrent
    mpv
    anki
    telegram-desktop

    unityhub
    vulkan-tools
    #zed-editor via zed.nix

    #steam via steam.nix
    prismlauncher
  ];
}
