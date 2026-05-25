{ ... }:

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
      };
    };

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
      }

      window#waybar {
        background: rgba(20, 20, 20, 0.85);
        color: #ffffff;
      }

      #workspaces button {
        padding: 0 9px;
        color: #666666;
        background: transparent;
        border: none;
        border-radius: 6px;
      }

      /* Workspace with at least one window */
      #workspaces button:not(.empty) {
        color: #ff9f1c;
      }

      /* Empty workspace */
      #workspaces button.empty {
        color: #555555;
      }

      /* Current workspace */
      #workspaces button.active {
        color: #ffffff;
        background: rgba(255, 159, 28, 0.35);
      }

      #workspaces button.urgent {
        color: #ffffff;
        background: #ff4d4d;
      }

      #clock,
      #pulseaudio,
      #network {
        padding: 0 10px;
      }
    '';
  };
}
