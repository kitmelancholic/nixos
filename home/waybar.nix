{ config, lib, ... }:

let
  colors = config.lib.stylix.colors;
in

{
  programs.waybar = {
    enable = lib.mkDefault true;
    systemd.enable = lib.mkDefault true;

    settings.mainBar = {
      layer = lib.mkDefault "top";
      position = lib.mkDefault "top";
      height = lib.mkDefault 30;

      modules-left = lib.mkDefault [
        "hyprland/workspaces"
      ];

      modules-center = lib.mkDefault [
        "clock"
      ];

      modules-right = lib.mkDefault [
        "pulseaudio"
        "network"
        "backlight"
        "battery"
        "power-profiles-daemon"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        format = lib.mkDefault "{id}";
        on-click = lib.mkDefault "activate";
        sort-by-number = lib.mkDefault true;
        all-outputs = lib.mkDefault true;

        persistent-workspaces = {
          "*" = lib.mkDefault 5;
        };
      };

      clock = {
        format = lib.mkDefault "{:%H:%M  %d.%m.%Y}";
      };

      pulseaudio = {
        format = lib.mkDefault "  {volume}%";
        format-muted = lib.mkDefault "󰝟 muted";
      };

      network = {
        format-wifi = lib.mkDefault "  {essid}";
        format-ethernet = lib.mkDefault "󰈀  Ethernet";
        format-disconnected = lib.mkDefault "󰖪  Offline";
      };

      backlight = {
        format = lib.mkDefault "󰃠  {percent}%";
      };

      battery = {
        format = lib.mkDefault "{icon}  {capacity}%";
        format-charging = lib.mkDefault "󰂄  {capacity}%";
        format-icons = lib.mkDefault [
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
        format = lib.mkDefault "{icon}";
        tooltip-format = lib.mkDefault "Power profile: {profile}";
        format-icons = {
          performance = lib.mkDefault "󰓅";
          balanced = lib.mkDefault "󰾅";
          power-saver = lib.mkDefault "󰾆";
        };
      };

      "custom/power" = {
        format = lib.mkDefault "󰐥";
        tooltip-format = lib.mkDefault "Power menu";
        on-click = lib.mkDefault "power-menu";
        on-click-right = lib.mkDefault "loginctl lock-session";
      };
    };

    style = lib.mkDefault ''
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
      #power-profiles-daemon,
      #custom-power {
        padding: 0 10px;
      }

      #custom-power {
        color: #${colors.base08};
      }

      #custom-power:hover {
        background: #${colors.base02};
        color: #${colors.base05};
      }
    '';
  };
}
