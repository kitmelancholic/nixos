{ pkgs, ... }:

{
  services.easyeffects = {
    enable = true;
    package = pkgs.easyeffects; # Optional PipeWire mic/output processing
  };

  home.packages = with pkgs; [
    qpwgraph # Visual PipeWire patchbay for OBS/game/browser routing
    pwvucontrol # PipeWire-native volume and device control
  ];
}
