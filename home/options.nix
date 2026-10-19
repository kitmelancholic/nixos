{ config, lib, ... }:

{
  options.kit = {
    repo = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/nixos";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/nixos"'';
      description = "The dangoNix checkout dangonix works on when run outside one.";
    };

    profile.id = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      readOnly = true;
      description = "Stable identifier of the selected Home Manager desktop profile.";
    };

    apps = {
      browser = {
        command = lib.mkOption {
          type = lib.types.str;
          default = "zen";
          description = "Command used to launch the web browser.";
        };
        desktop = lib.mkOption {
          type = lib.types.str;
          default = "zen.desktop";
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
        default = "nautilus";
        description = "Command used to launch the file explorer.";
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
