{
  config,
  inputs,
  lib,
  ...
}:

{
  imports = [
    inputs.caelestia.homeManagerModules.default
    ../common/hyprpolkitagent.nix
  ];

  assertions = [
    {
      assertion = config.programs.caelestia.enable;
      message = "Caelestia profile: programs.caelestia.enable must be true";
    }
    {
      assertion = config.programs.caelestia.systemd.enable;
      message = "Caelestia profile: programs.caelestia.systemd.enable must be true";
    }
    {
      assertion = config.programs.caelestia.cli.enable;
      message = "Caelestia profile: programs.caelestia.cli.enable must be true";
    }
  ];

  programs.caelestia = {
    enable = true;
    systemd.enable = true;
    cli.enable = true;
    cli.settings.theme.enableGtk = false;
  };

  wayland.windowManager.hyprland.settings = {
    mod._var = "SUPER";
    terminal._var = config.kit.apps.terminal.command;
    explorer._var = config.kit.apps.explorer.command;
    browser._var = config.kit.apps.browser.command;
    bind = import ./binds.nix { inherit lib; };
  };
}
