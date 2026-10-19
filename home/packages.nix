{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:

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
  home.file.".local/share/jdks/25".source = pkgs.jdk25;
  home.file.".local/share/jdks/21".source = pkgs.jdk21;

  home.packages = with pkgs; [
    # Desktop shell
    kitty # fallback terminal

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
    nautilus
    file-roller
    evince
    calibre
    loupe

    # Internet and communication
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser
    vivaldi # browser
    vivaldi-ffmpeg-codecs # Extra media codecs for Vivaldi
    qbittorrent
    anki
    telegram-desktop
    inputs.claude-desktop-extra.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-extra

    # Development adjacent
    unityhub
    mono # Unity/legacy .NET compatibility
    goose-cli
    pkgsUnstable.claude-code # unstable: tracks upstream releases closely; wrapper sets DISABLE_AUTOUPDATER=1
    pkgsUnstable.codex # unstable, no self-update (check_for_update_on_startup = false)
    mcp-nixos # NixOS/Home Manager option and package lookup for both agents
    kccWithKindlegen
    kindlegen # enables KCC MOBI conversion

    # Games
    (prismlauncher.override {
      jdks = [
        jdk25
        jdk21
        jdk8
      ]; # 17 GTNH не потрібна; 8 для старих паків
    })
  ];
}
