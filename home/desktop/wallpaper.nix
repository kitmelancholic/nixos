{ config, pkgs, ... }:

let
  wallpaperApply = pkgs.writeShellApplication {
    name = "wallpaper-apply";
    runtimeInputs = with pkgs; [
      awww # Wayland wallpaper daemon
      coreutils
      systemd # Start the Home Manager-owned daemon
    ];
    text = ''
      systemctl --user start awww.service

      attempt=0
      while [ "$attempt" -lt 10 ]; do
        attempt=$((attempt + 1))
        if awww img "${config.kit.theme.wallpaper}" --transition-type fade --transition-duration 1; then
          exit 0
        fi
        sleep 0.2
      done

      echo "wallpaper-apply: awww did not accept the wallpaper" >&2
      exit 1
    '';
  };
in
{
  services.awww.enable = true;

  home.packages = [
    pkgs.awww # Wayland wallpaper daemon
    wallpaperApply
  ];
}
