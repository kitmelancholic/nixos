{ pkgs, ... }:

let
  kindlegen = pkgs.stdenvNoCC.mkDerivation {
    pname = "kindlegen";
    version = "2.9";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@hakuneko/kindlegen-binaries/-/kindlegen-binaries-2.9.0-3.tgz";
      hash = "sha256-Thpd2seTZgRNT1NXdMa7shSKyNR+be0+hJqx2/Wmek4=";
    };

    installPhase = ''
      install -Dm755 bin/linux/amd64/kindlegen "$out/bin/kindlegen"
    '';

    meta = {
      description = "Amazon KindleGen e-book compiler for KCC MOBI conversion";
      homepage = "https://github.com/ciromattia/kcc/wiki/Installation#kindlegen";
      license = pkgs.lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };

  kccWithKindlegen = pkgs.kcc.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--prefix PATH : ${pkgs.lib.makeBinPath [ kindlegen ]}"
    ];
  });
in
{
  home.packages = with pkgs; [
    # Desktop shell
    kitty # fallback terminal
    wofi
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
    calibre
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
    kccWithKindlegen
    kindlegen # enables KCC MOBI conversion

    # Games
    prismlauncher
  ];
}
