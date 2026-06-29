{
  constants,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/core/boot.nix
    ../../modules/nixos/core/locale.nix
    ../../modules/nixos/core/nix.nix
    ../../modules/nixos/core/nix-ld.nix
    ../../modules/nixos/core/packages.nix
    ../../modules/nixos/core/user.nix
    ../../modules/nixos/desktop/audio.nix
    ../../modules/nixos/desktop/audio-routing.nix
    ../../modules/nixos/desktop/display-manager.nix
    ../../modules/nixos/desktop/fonts.nix
    ../../modules/nixos/desktop/hyprland.nix
    ../../modules/nixos/desktop/plumbing.nix
    ../../modules/nixos/hardware/intel-graphics.nix
    ../../modules/nixos/profiles/development.nix
    ../../modules/nixos/profiles/foundryvtt.nix
    ../../modules/nixos/profiles/gaming.nix
    ../../modules/nixos/profiles/streaming.nix
  ];

  networking = {
    hostName = constants.hostname;
    networkmanager.enable = true;
  };

  services = {
    thermald.enable = true;
    xserver.xkb = {
      layout = "us,ua";
      options = "grp:alt_shift_toggle";
    };
  };

  nixpkgs.config.allowUnfree = true;

  programs.dconf.enable = true;

  system.stateVersion = "26.05";
}
