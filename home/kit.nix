{
  settings,
  ...
}:

let
  inherit (settings) homeDirectory username;
in

{
  imports = [
    ./desktop.nix
    ./foundry.nix
    ./graphify.nix
    ./osd.nix
    ./power.nix
    ./programs.nix
    ./screenshots.nix
    ./packages.nix
    ./hyprland
    ./waybar.nix
    ./zed.nix
  ];

  home = {
    inherit homeDirectory username;
    stateVersion = "26.05";
  };

  xdg = {
    enable = true;

    # For integration of link opening etc.
    portal.xdgOpenUsePortal = true;
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
