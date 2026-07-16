{ pkgs, settings, ... }:

{
  virtualisation.docker.enable = true;

  users.users.${settings.username}.extraGroups = [ "docker" ];

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      protontricks.enable = true;
    };

    gamemode.enable = true;
    gamescope = {
      enable = true;
      capSysNice = true;
    };

    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture # OBS per-app PipeWire audio capture
        obs-vaapi # VAAPI hardware encoding support
        obs-vkcapture # Vulkan game capture support
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    gamescope # Nested compositor for Steam/game launch options
    mangohud # Gaming performance overlay
    protonup-qt # Proton-GE manager
    discord
  ];
}
