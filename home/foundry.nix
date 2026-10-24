{
  settings,
  lib,
  ...
}:

let
  inherit (settings) foundry;
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
  config = lib.mkIf foundry.enable {
    xdg.dataFile = {
      "applications/foundryvtt.desktop".text = desktopEntry {
        name = "Foundry VTT";
        exec = "dangonix foundry open";
      };

      "applications/foundryvtt-stop.desktop".text = desktopEntry {
        name = "Stop Foundry VTT";
        exec = "dangonix foundry stop";
      };

      "applications/foundryvtt-restart.desktop".text = desktopEntry {
        name = "Restart Foundry VTT";
        exec = "dangonix foundry restart";
      };
    };
  };
}
