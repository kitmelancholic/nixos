{ pkgs, ... }:

{
  services.easyeffects = {
    enable = true;
    package = pkgs.easyeffects; # Optional PipeWire mic/output processing
  };

  home.packages = with pkgs; [
    pulsemixer # Terminal mixer for PipeWire/PulseAudio streams and devices
    qpwgraph # Visual PipeWire patchbay for OBS/game/browser routing
    pwvucontrol # PipeWire-native volume and device control
  ];
}
