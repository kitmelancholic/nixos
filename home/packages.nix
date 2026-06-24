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

    spice-vdagent # VM clipboard/display integration
    xclip
    xsel

    nnn # explorer
    nautilus
    file-rollerwhy in kit.nix there is 25.11
    evince
    loupe
    vivaldi # browser
    vivaldi-ffmpeg-codecs # Extra media codecs for Vivaldi
    qbittorrent
    anki
    telegram-desktop

    unityhub
    mono # Unity/legacy .NET compatibility
    #zed-editor via zed.nix

    #steam via modules/nixos/profiles/gaming.nix
    prismlauncher
  ];
}
