{
  config,
  constants,
  lib,
  pkgs,
}:

let
  helpers = import ./lua-helpers.nix { inherit lib; };
  inherit (helpers) lua mkEnv;

  colors = config.lib.stylix.colors;
  color = name: "rgb(${colors.${name}})";
  startupCommands = [
    "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent"
    "wallpaper-apply"
    "waybar"
    "dunst"
  ];
in
{
  mod._var = "SUPER";
  terminal._var = constants.apps.terminal.command;
  explorer._var = constants.apps.explorer.command;
  launcher._var = constants.apps.launcher.command;
  browser._var = constants.apps.browser.command;

  monitor = {
    output = "";
    mode = "preferred";
    position = "auto";
    scale = 1;
  };

  env = [
    (mkEnv "XCURSOR_SIZE" "24")
    (mkEnv "NIXOS_OZONE_WL" "1")
  ];

  config = {
    input = {
      kb_layout = "us,ua";
      kb_options = "grp:alt_shift_toggle";
      follow_mouse = 1;
      touchpad.natural_scroll = true;
    };

    general = {
      gaps_in = 4;
      gaps_out = 8;
      border_size = 2;
      layout = "dwindle";
      "col.active_border" = color "base0D";
      "col.inactive_border" = color "base03";
    };

    decoration.rounding = 8;

    group = {
      "col.border_active" = color "base0D";
      "col.border_inactive" = color "base03";
    };

    animations.enabled = true;
    dwindle.preserve_split = true;

    misc = {
      disable_hyprland_logo = true;
      disable_splash_rendering = true;
    };
  };

  bind = import ./binds.nix { inherit lib; };

  on = {
    _args = [
      "hyprland.start"
      (lua ''
        function()
          ${lib.concatMapStringsSep "\n  " (command: ''hl.exec_cmd("${command}")'') startupCommands}
        end
      '')
    ];
  };
}
