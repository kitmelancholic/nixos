{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  runtimeKeys = import ./runtime-keys.nix;
  runtimeKeysScript = runtimeKeys.mkScript pkgs runtimeKeys.keys;
  settingsToml = "${config.xdg.stateHome}/noctalia/settings.toml";
in
{
  imports = [
    inputs.noctalia.homeModules.default
    ../common/hyprpolkitagent.nix
    ./roles.nix
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

  # Noctalia rewrites settings.toml from memory on every settings change.
  systemd.user.services.noctalia.Service.ExecStartPre =
    "-${lib.getExe runtimeKeysScript} ${settingsToml}";

  home.activation.noctaliaRuntimeKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe runtimeKeysScript} ${lib.escapeShellArg settingsToml}
  '';

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
    terminal._var = config.dangonix.apps.terminal.command;
    explorer._var = config.dangonix.apps.explorer.command;
    browser._var = config.dangonix.apps.browser.command;
    bind = import ./binds.nix { inherit lib; };
  };
}
