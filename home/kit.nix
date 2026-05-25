{ config, pkgs, ... }:

{
  imports = [
    ./packages.nix
    ./hyprland.nix
    ./waybar.nix
    ./zed.nix
  ];

  home.username = "kit";
  home.homeDirectory = "/home/kit";
  home.stateVersion = "25.11";

  xdg.enable = true;

  #for integration of link openning etc
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
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
