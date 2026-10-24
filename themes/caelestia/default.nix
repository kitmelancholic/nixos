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

  # Caelestia does not write color-scheme; switch to "shell" once it does.
  dangonix.look.appearance = "dark";

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
    {
      assertion = config.systemd.user.services.caelestia.Service.KillMode == "process";
      message = "Caelestia profile: caelestia.service must keep KillMode=process (apps launched from the shell live in its cgroup)";
    }
  ];

  # Apps start from the shell live in caelestia.service's cgroup; stopping the
  # unit (home activation) must not kill them.
  systemd.user.services.caelestia.Service.KillMode = "process";

  programs.caelestia = {
    enable = true;
    systemd.enable = true;
    cli.enable = true;
    cli.settings.theme.enableGtk = false;
  };

  wayland.windowManager.hyprland.settings = {
    mod._var = "SUPER";
    terminal._var = config.dangonix.apps.terminal.command;
    explorer._var = config.dangonix.apps.explorer.command;
    browser._var = config.dangonix.apps.browser.command;
    bind = import ./binds.nix { inherit lib; };
  };
}
