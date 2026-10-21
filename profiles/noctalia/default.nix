{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    inputs.noctalia.homeModules.default
    ../common/hyprpolkitagent.nix
  ];

  dangonix.look.appearance = "shell";

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    settings = {
      shell = {
        launch_apps_as_systemd_services = true;
        polkit_agent = false;
      };
    };
  };

  assertions = [
    {
      assertion = config.programs.noctalia.enable;
      message = "Noctalia profile: programs.noctalia.enable must be true";
    }
    {
      assertion = config.programs.noctalia.systemd.enable;
      message = "Noctalia profile: programs.noctalia.systemd.enable must be true";
    }
    {
      assertion = config.programs.noctalia.settings.shell.launch_apps_as_systemd_services;
      message = "Noctalia profile: shell.launch_apps_as_systemd_services must be true";
    }
  ];

  wayland.windowManager.hyprland.settings = {
    mod._var = "SUPER";
    terminal._var = config.kit.apps.terminal.command;
    explorer._var = config.kit.apps.explorer.command;
    browser._var = config.kit.apps.browser.command;
    bind = import ./binds.nix { inherit lib; };
  };
}
