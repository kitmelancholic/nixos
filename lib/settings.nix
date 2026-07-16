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
    version = "13.0.0+351";
    shortVersion = "13.351";
    filename = "FoundryVTT-Linux-13.351.zip";
    hash = "sha256-SzzAnYJ00HkiKr9xRAvJjgGm3sfGl44Rel09NcNLqr4=";
    port = foundryPort;
    service = "foundryvtt.service";
    url = "http://127.0.0.1:${toString foundryPort}";
  };
}
