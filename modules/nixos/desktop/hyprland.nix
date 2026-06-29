{ inputs, pkgs, ... }:

let
  hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.hyprland = {
    enable = true;
    package = hyprlandPackages.hyprland;
    portalPackage = hyprlandPackages.xdg-desktop-portal-hyprland;
    withUWSM = true;
    xwayland.enable = true;
  };
}
