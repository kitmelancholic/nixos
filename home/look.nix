{ config, lib, ... }:

let
  cfg = config.dangonix.look;
in
{
  options.dangonix.look = {
    appearance = lib.mkOption {
      type = lib.types.enum [
        "shell"
        "dark"
        "light"
      ];
      description = "Who decides dark or light: the shell (it writes color-scheme itself) or a fixed value.";
    };

    terminal = {
      dark = lib.mkOption {
        type = lib.types.str;
        default = "manuscript-dark";
        description = "Ghostty theme in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.str;
        default = "manuscript-light";
        description = "Ghostty theme in light mode.";
      };
    };

    editor = {
      dark = lib.mkOption {
        type = lib.types.str;
        default = "Manuscript Dark";
        description = "Zed theme in dark mode.";
      };
      light = lib.mkOption {
        type = lib.types.str;
        default = "Manuscript Light";
        description = "Zed theme in light mode.";
      };
    };

    fonts = {
      mono = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "Rec Mono Casual"
          "Maple Mono"
        ];
        description = "Code font families: the first, then its fallbacks.";
      };
      monoSize = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Terminal code font size, in points.";
      };
      ui = lib.mkOption {
        type = lib.types.str;
        default = "Miriam Libre";
        description = "Interface font family.";
      };
    };
  };

  config = {
    dconf.settings = lib.mkIf (cfg.appearance != "shell") {
      "org/gnome/desktop/interface".color-scheme = "prefer-${cfg.appearance}";
    };

    xdg.configFile."dangonix/theme-id".text = config.dangonix.theme.id;

    xdg.configFile."dangonix/look.json".text = builtins.toJSON {
      inherit (cfg) appearance;
      theme = config.dangonix.theme.id;
    };
  };
}
