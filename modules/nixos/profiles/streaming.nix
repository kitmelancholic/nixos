{ pkgs, ... }:

{
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-pipewire-audio-capture # OBS per-app PipeWire audio capture
      obs-vaapi # VAAPI hardware encoding support
      obs-vkcapture # Vulkan game capture support
    ];
  };
}
