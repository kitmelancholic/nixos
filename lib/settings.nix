{
  system,
  username,
}:

let
  foundryPort = 30000;
in
{
  inherit system username;
  hostname = "nixos";
  homeDirectory = "/home/${username}";

  apps = {
    browser = {
      command = "vivaldi";
      desktop = "vivaldi-stable.desktop";
    };
    terminal.command = "ghostty";
    explorer.command = "ghostty -e nnn -Q";
    launcher.command = "wofi --show drun";
    fileManager.desktop = "org.gnome.Nautilus.desktop";
    imageViewer.desktop = "org.gnome.Loupe.desktop";
    mediaPlayer.desktop = "mpv.desktop";
    pdfViewer.desktop = "org.gnome.Evince.desktop";
    textEditor.desktop = "dev.zed.Zed.desktop";
    archiveManager.desktop = "org.gnome.FileRoller.desktop";
  };

  foundry = {
    version = "14.0.0+361";
    shortVersion = "14.361";
    filename = "FoundryVTT-Linux-14.361.zip";
    hash = "sha256-zafI0qgSyToAIt0qs4zRkhUspFSFoNaS0B+uAcVrERc=";
    port = foundryPort;
    service = "foundryvtt.service";
    url = "http://127.0.0.1:${toString foundryPort}";
  };
}
