{ inputs, pkgs, ... }:

let
  screenshotsDir = "$HOME/Pictures/Screenshots";
  timestamp = "$(date +%F-%H%M%S)";
  hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  screenshotArea = pkgs.writeShellApplication {
    name = "screenshot-area";
    runtimeInputs = with pkgs; [
      coreutils
      grim # Wayland screenshot capture
      slurp # Wayland region selection
      wl-clipboard # Wayland clipboard CLI
    ];
    text = ''
      mkdir -p "${screenshotsDir}"
      file="${screenshotsDir}/screenshot-area-${timestamp}.png"
      grim -g "$(slurp)" "$file"
      wl-copy < "$file"
      printf '%s\n' "$file"
    '';
  };
  screenshotAreaEdit = pkgs.writeShellApplication {
    name = "screenshot-area-edit";
    runtimeInputs = with pkgs; [
      coreutils
      grim # Wayland screenshot capture
      slurp # Wayland region selection
      swappy # Screenshot annotation editor
      wl-clipboard # Wayland clipboard CLI
    ];
    text = ''
      mkdir -p "${screenshotsDir}"
      file="${screenshotsDir}/screenshot-area-${timestamp}.png"
      tmp="$(mktemp --suffix=.png)"
      trap 'rm -f "$tmp"' EXIT
      grim -g "$(slurp)" "$tmp"
      swappy -f "$tmp" -o "$file"
      wl-copy < "$file"
      printf '%s\n' "$file"
    '';
  };
  screenshotFull = pkgs.writeShellApplication {
    name = "screenshot-full";
    runtimeInputs = with pkgs; [
      coreutils
      grim # Wayland screenshot capture
      wl-clipboard # Wayland clipboard CLI
    ];
    text = ''
      mkdir -p "${screenshotsDir}"
      file="${screenshotsDir}/screenshot-full-${timestamp}.png"
      grim "$file"
      wl-copy < "$file"
      printf '%s\n' "$file"
    '';
  };
  screenshotWindow = pkgs.writeShellApplication {
    name = "screenshot-window";
    runtimeInputs = [
      hyprland
      pkgs.coreutils
      pkgs.grim # Wayland screenshot capture
      pkgs.jq # Parse Hyprland active-window geometry
      pkgs.wl-clipboard # Wayland clipboard CLI
    ];
    text = ''
      mkdir -p "${screenshotsDir}"
      file="${screenshotsDir}/screenshot-window-${timestamp}.png"
      geometry="$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
      grim -g "$geometry" "$file"
      wl-copy < "$file"
      printf '%s\n' "$file"
    '';
  };
in
{
  home.packages = [
    screenshotArea
    screenshotAreaEdit
    screenshotFull
    screenshotWindow
  ];

  home.file."Pictures/Screenshots/.keep".text = "";
}
