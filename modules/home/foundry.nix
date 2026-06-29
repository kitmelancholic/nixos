{ constants, pkgs, ... }:

let
  inherit (constants) foundry;
  systemctl = "${pkgs.systemd}/bin/systemctl";

  foundryStart = pkgs.writeShellApplication {
    name = "foundry";
    runtimeInputs = with pkgs; [
      coreutils
      xdg-utils
    ];
    text = ''
      if ! ${systemctl} is-active --quiet '${foundry.service}'; then
        /run/wrappers/bin/sudo ${systemctl} start '${foundry.service}'
      fi

      exec xdg-open '${foundry.url}'
    '';
  };

  foundryStop = pkgs.writeShellApplication {
    name = "foundry-stop";
    text = ''
      exec /run/wrappers/bin/sudo ${systemctl} stop '${foundry.service}'
    '';
  };

  foundryRestart = pkgs.writeShellApplication {
    name = "foundry-restart";
    runtimeInputs = [ pkgs.xdg-utils ];
    text = ''
      /run/wrappers/bin/sudo ${systemctl} restart '${foundry.service}'
      exec xdg-open '${foundry.url}'
    '';
  };

  foundryStatus = pkgs.writeShellApplication {
    name = "foundry-status";
    text = ''
      exec ${systemctl} status '${foundry.service}'
    '';
  };

  desktopEntry =
    {
      name,
      exec,
    }:
    ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      GenericName=Virtual tabletop
      Exec=${exec}
      Terminal=false
      Categories=Game;Network;
    '';
in

{
  home.packages = [
    foundryRestart
    foundryStart
    foundryStatus
    foundryStop
  ];

  xdg.dataFile = {
    "applications/foundryvtt.desktop".text = desktopEntry {
      name = "Foundry VTT";
      exec = "${foundryStart}/bin/foundry";
    };

    "applications/foundryvtt-stop.desktop".text = desktopEntry {
      name = "Stop Foundry VTT";
      exec = "${foundryStop}/bin/foundry-stop";
    };

    "applications/foundryvtt-restart.desktop".text = desktopEntry {
      name = "Restart Foundry VTT";
      exec = "${foundryRestart}/bin/foundry-restart";
    };
  };
}
