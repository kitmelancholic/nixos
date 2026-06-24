{ pkgs, ... }:

let
  themeSet = import ../../../themes;
  theme = themeSet.active;
  wallpaperApply = pkgs.writeShellApplication {
    name = "wallpaper-apply";
    runtimeInputs = with pkgs; [
      awww # Wayland wallpaper daemon
      coreutils
      procps # Detect running wallpaper daemon
    ];
    text = ''
      if ! pgrep -x awww-daemon >/dev/null; then
        awww-daemon >/dev/null 2>&1 &
        sleep 0.2
      fi

      awww img "${theme.wallpaper}" --transition-type fade --transition-duration 1
    '';
  };
in
{
  home.packages = [
    pkgs.awww # Wayland wallpaper daemon
    wallpaperApply
  ];
}
