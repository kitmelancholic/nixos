{ config, ... }:

let
  colors = config.lib.stylix.colors;
in

{
  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;

        modules-left = [
          "hyprland/workspaces"
        ];

        modules-center = [
          "clock"
        ];

        modules-right = [
          "pulseaudio"
          "network"
          "backlight"
          "battery"
          "power-profiles-daemon"
        ];

        "hyprland/workspaces" = {
          format = "{id}";
          on-click = "activate";
          sort-by-number = true;
          all-outputs = true;

          persistent-workspaces = {
            "*" = 5;
          };
        };

        clock = {
          format = "{:%H:%M  %d.%m.%Y}";
        };

        pulseaudio = {
          format = "  {volume}%";
          format-muted = "󰝟 muted";
        };

        network = {
          format-wifi = "  {essid}";
          format-ethernet = "󰈀  Ethernet";
          format-disconnected = "󰖪  Offline";
        };

        backlight = {
          format = "󰃠  {percent}%";
        };

        battery = {
          format = "{icon}  {capacity}%";
          format-charging = "󰂄  {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
        };

        power-profiles-daemon = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}";
          format-icons = {
            performance = "󰓅";
            balanced = "󰾅";
            power-saver = "󰾆";
          };
        };
      };
    };

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
      }

      window#waybar {
        background: #${colors.base00};
        color: #${colors.base05};
      }

      #workspaces button {
        padding: 0 9px;
        color: #${colors.base03};
        background: transparent;
        border: none;
        border-radius: 6px;
      }

      /* Workspace with at least one window */
      #workspaces button:not(.empty) {
        color: #${colors.base0A};
      }

      /* Empty workspace */
      #workspaces button.empty {
        color: #${colors.base03};
      }

      /* Current workspace */
      #workspaces button.active {
        color: #${colors.base00};
        background: #${colors.base0D};
      }

      #workspaces button.urgent {
        color: #${colors.base00};
        background: #${colors.base08};
      }

      #clock,
      #pulseaudio,
      #network,
      #backlight,
      #battery,
      #power-profiles-daemon {
        padding: 0 10px;
      }
    '';
  };
}
