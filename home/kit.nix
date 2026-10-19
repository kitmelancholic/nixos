{
  settings,
  ...
}:

let
  inherit (settings) homeDirectory username;
in

{
  imports = [
    ./options.nix
    ./agents.nix
    ./dangonix.nix
    ./desktop.nix
    ./foundry.nix
    ./programs.nix
    ./packages.nix
    ./theme-switcher.nix
    ./hyprland
    ./zed.nix
    ./claude-desktop.nix
    ./openmpi.nix
    ./pdf2md.nix
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

  fonts.fontconfig.enable = true;

  programs.home-manager.enable = true;

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
