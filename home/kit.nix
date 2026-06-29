{
  constants,
  pkgs,
  ...
}:

let
  inherit (constants) homeDirectory username;
in

{
  imports = [
    ../modules/home/desktop/audio.nix
    ../modules/home/desktop/default-apps.nix
    ../modules/home/desktop/laptop.nix
    ../modules/home/desktop/osd.nix
    ../modules/home/desktop/screenshots.nix
    ../modules/home/desktop/theme.nix
    ../modules/home/desktop/wallpaper.nix
    ../modules/home/development.nix
    ../modules/home/media.nix
    ../modules/home/programs/terminal.nix
    ./packages.nix
    ./hyprland
    ./waybar.nix
    ./zed.nix
  ];

  nixpkgs.config.allowUnfree = true;

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

  systemd.user.services.spice-vdagent = {
    Unit = {
      Description = "SPICE vdagent user session";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.spice-vdagent}/bin/spice-vdagent";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
