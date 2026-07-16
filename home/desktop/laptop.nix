{ pkgs, ... }:

let
  lowBatteryNotify = pkgs.writeShellApplication {
    name = "low-battery-notify";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      libnotify
      upower
    ];
    text = ''
      battery="$(upower -e | grep -m1 battery || true)"
      [ -n "$battery" ] || exit 0

      state="$(upower -i "$battery" | awk '/state:/ { print $2 }')"
      percentage="$(upower -i "$battery" | awk '/percentage:/ { gsub("%", "", $2); print $2 }')"

      if [ "$state" = "discharging" ] && [ "''${percentage:-100}" -le 15 ]; then
        notify-send -u critical "Low battery" "Battery is at ''${percentage}%"
      fi
    '';
  };
in
{
  home.packages = [
    pkgs.pamixer # PipeWire/PulseAudio volume CLI
    lowBatteryNotify
  ];

  systemd.user.services.low-battery-notify = {
    Unit.Description = "Low battery notification";
    Service = {
      Type = "oneshot";
      ExecStart = "${lowBatteryNotify}/bin/low-battery-notify";
    };
  };

  systemd.user.timers.low-battery-notify = {
    Unit.Description = "Low battery notification timer";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Unit = "low-battery-notify.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
