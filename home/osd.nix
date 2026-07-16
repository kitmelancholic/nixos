{ config, pkgs, ... }:

let
  colors = config.lib.stylix.colors;
  swayosdStyle = pkgs.writeText "swayosd-style.css" ''
    window {
      background: transparent;
    }

    box {
      background: #${colors.base00};
      border: 2px solid #${colors.base0D};
      border-radius: 10px;
      color: #${colors.base05};
      padding: 12px;
    }

    image,
    label {
      color: #${colors.base05};
    }

    scale trough {
      background: #${colors.base02};
      border-radius: 999px;
      min-height: 8px;
      min-width: 180px;
    }

    scale trough highlight {
      background: #${colors.base0D};
      border-radius: 999px;
    }
  '';

  keyboardBacklightOsd = pkgs.writeShellApplication {
    name = "keyboard-backlight-osd";
    runtimeInputs = with pkgs; [
      brightnessctl # Backlight and keyboard LED control
      coreutils
      gawk # Parse brightnessctl device and percentage output
      gnugrep
      swayosd
    ];
    text = ''
      action="''${1:-}"
      case "$action" in
        raise) change="5%+" ;;
        lower) change="5%-" ;;
        *) exit 2 ;;
      esac

      device="$(
        brightnessctl --list |
          awk -F"'" "/^Device / && /class 'leds'/ && \$2 ~ /(kbd|keyboard|backlight)/ { print \$2; exit }"
      )"

      [ -n "$device" ] || exit 0

      brightnessctl --device "$device" set "$change" >/dev/null
      percent="$(
        brightnessctl --machine-readable --device "$device" info |
          awk -F, '{ gsub("%", "", $4); print $4; exit }'
      )"
      percent="''${percent:-0}"
      progress="$(awk -v value="$percent" 'BEGIN { printf "%.2f", value / 100 }')"

      swayosd-client \
        --custom-icon input-keyboard-symbolic \
        --custom-progress "$progress" \
        --custom-progress-text "$percent%" ||
        swayosd-client --brightness "$percent" --device "$device" ||
        true
    '';
  };
in
{
  services.swayosd = {
    enable = true;
    package = pkgs.swayosd; # OSD server and client for hardware keys
    stylePath = swayosdStyle;
    topMargin = 0.85;
  };

  home.packages = [
    keyboardBacklightOsd # Keyboard backlight OSD wrapper with hardware auto-detection
  ];
}
