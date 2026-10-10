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

  wayland.windowManager.hyprland.settings = {
    mod._var = "SUPER";
    terminal._var = config.kit.apps.terminal.command;
    explorer._var = config.kit.apps.explorer.command;
    browser._var = config.kit.apps.browser.command;
    bind = import ./binds.nix { inherit lib; };
  };
}
