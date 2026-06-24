{ pkgs, ... }:

{
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
  };

  environment.systemPackages = with pkgs; [
    gamescope # Nested compositor for Steam/game launch options
    mangohud # Gaming performance overlay
    protonup-qt # Proton-GE manager
  ];
}
