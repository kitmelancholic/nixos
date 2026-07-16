{ pkgs, ... }:

{
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
