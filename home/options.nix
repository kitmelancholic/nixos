{ lib, ... }:

{
  options.kit = {
    theme = {
      id = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
        readOnly = true;
        description = "Stable identifier of the Home Manager theme profile.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "Catppuccin";
        description = "Human-readable name of the active theme.";
      };

      wallpaper = lib.mkOption {
        type = lib.types.path;
        default = ../assets/wallpapers/catppuccin.png;
        description = "Wallpaper used by the active theme.";
      };
    };

    apps = {
      browser = {
        command = lib.mkOption {
          type = lib.types.str;
          default = "vivaldi";
          description = "Command used to launch the web browser.";
        };
        desktop = lib.mkOption {
          type = lib.types.str;
          default = "vivaldi-stable.desktop";
          description = "Desktop entry used for browser associations.";
        };
      };

      terminal.command = lib.mkOption {
        type = lib.types.str;
        default = "ghostty";
        description = "Command used to launch the terminal.";
      };

      explorer.command = lib.mkOption {
        type = lib.types.str;
        default = "ghostty -e nnn -Q";
        description = "Command used to launch the file explorer.";
      };

      launcher.command = lib.mkOption {
        type = lib.types.str;
        default = "wofi --show drun";
        description = "Command used to launch the application launcher.";
      };

      fileManager.desktop = lib.mkOption {
        type = lib.types.str;
        default = "org.gnome.Nautilus.desktop";
        description = "Desktop entry used for directory associations.";
      };

      imageViewer.desktop = lib.mkOption {
        type = lib.types.str;
        default = "org.gnome.Loupe.desktop";
        description = "Desktop entry used for image associations.";
      };

      mediaPlayer.desktop = lib.mkOption {
        type = lib.types.str;
        default = "mpv.desktop";
        description = "Desktop entry used for media associations.";
      };

      pdfViewer.desktop = lib.mkOption {
        type = lib.types.str;
        default = "org.gnome.Evince.desktop";
        description = "Desktop entry used for PDF associations.";
      };

      textEditor.desktop = lib.mkOption {
        type = lib.types.str;
        default = "dev.zed.Zed.desktop";
        description = "Desktop entry used for text associations.";
      };

      archiveManager.desktop = lib.mkOption {
        type = lib.types.str;
        default = "org.gnome.FileRoller.desktop";
        description = "Desktop entry used for archive associations.";
      };
    };
  };
}
