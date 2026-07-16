{ config, pkgs, ... }:

let
  colors = config.lib.stylix.colors;

  powerMenu = pkgs.writeShellApplication {
    name = "power-menu";
    runtimeInputs = with pkgs; [
      procps
      wlogout
    ];
    text = ''
      if pgrep --exact wlogout >/dev/null; then
        pkill --exact wlogout
        exit 0
      fi

      exec wlogout \
        --buttons-per-row 5 \
        --show-binds \
        --no-span
    '';
  };

  suspendSession = pkgs.writeShellApplication {
    name = "suspend-session";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      loginctl lock-session
      systemctl suspend
    '';
  };
in
{
  programs = {
    hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = true;
          hide_cursor = true;
          immediate_render = true;
        };

        background = [
          {
            monitor = "";
            path = config.stylix.image;
            blur_passes = 3;
            blur_size = 8;
            brightness = 0.65;
          }
        ];

        label = [
          {
            monitor = "";
            text = "$TIME";
            color = "rgb(${colors.base05})";
            font_family = "JetBrains Mono";
            font_size = 86;
            position = "0, 140";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Locked";
            color = "rgb(${colors.base04})";
            font_family = "Noto Sans";
            font_size = 18;
            position = "0, 55";
            halign = "center";
            valign = "center";
          }
        ];

        "input-field" = [
          {
            monitor = "";
            size = "320, 58";
            position = "0, -70";
            halign = "center";
            valign = "center";
            outline_thickness = 2;
            dots_center = true;
            fade_on_empty = false;
            placeholder_text = "<i>Enter password</i>";
            font_color = "rgb(${colors.base05})";
            inner_color = "rgb(${colors.base01})";
            outer_color = "rgb(${colors.base0D})";
            check_color = "rgb(${colors.base0A})";
            fail_color = "rgb(${colors.base08})";
            rounding = 12;
            shadow_passes = 2;
          }
        ];
      };
    };

    wlogout = {
      enable = true;
      layout = [
        {
          label = "lock";
          action = "loginctl lock-session";
          text = "󰌾  Lock";
          keybind = "l";
          width = 0.16;
          height = 0.26;
        }
        {
          label = "suspend";
          action = "${suspendSession}/bin/suspend-session";
          text = "󰒲  Sleep";
          keybind = "s";
          width = 0.16;
          height = 0.26;
        }
        {
          label = "logout";
          action = "uwsm stop";
          text = "󰗽  Log out";
          keybind = "e";
          width = 0.16;
          height = 0.26;
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "󰜉  Restart";
          keybind = "r";
          width = 0.16;
          height = 0.26;
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "󰐥  Shut down";
          keybind = "p";
          width = 0.16;
          height = 0.26;
        }
      ];

      style = ''
        * {
          background-image: none;
          box-shadow: none;
        }

        window {
          background-color: alpha(#${colors.base00}, 0.92);
        }

        button {
          margin: 16px;
          border: 2px solid #${colors.base03};
          border-radius: 18px;
          background-color: #${colors.base01};
          color: #${colors.base05};
          font-family: "JetBrainsMono Nerd Font";
          font-size: 20px;
          transition: all 180ms ease-in-out;
        }

        button:hover,
        button:focus {
          border-color: #${colors.base0D};
          background-color: #${colors.base02};
          color: #${colors.base0D};
          outline-style: none;
        }

        #shutdown:hover,
        #shutdown:focus {
          border-color: #${colors.base08};
          color: #${colors.base08};
        }

        #suspend:hover,
        #suspend:focus {
          border-color: #${colors.base0A};
          color: #${colors.base0A};
        }
      '';
    };
  };

  services.hypridle = {
    enable = true;
    settings.general = {
      lock_cmd = "pidof hyprlock || hyprlock";
      before_sleep_cmd = "loginctl lock-session";
      after_sleep_cmd = "hyprctl dispatch dpms on";
    };
  };

  home.packages = [
    powerMenu
    suspendSession
  ];
}
