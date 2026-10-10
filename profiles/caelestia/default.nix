{ inputs, ... }:

{
  imports = [
    inputs.caelestia.homeManagerModules.default
    ../common/hyprpolkitagent.nix
  ];

  programs.caelestia = {
    enable = true;
    systemd.enable = true;
    cli.enable = true;
    cli.settings.theme.enableGtk = false;
  };
}
