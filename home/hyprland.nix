{
  config,
  constants,
  lib,
  pkgs,
  ...
}:

let
  lua = lib.generators.mkLuaInline;
  colors = config.lib.stylix.colors;
  color = name: "rgb(${colors.${name}})";
  mod = "SUPER";
  mkArgs = args: { _args = args; };
  mkEnv =
    name: value:
    mkArgs [
      name
      value
    ];
  mkBind =
    key: action:
    mkArgs [
      key
      (lua action)
    ];
  mkBindWithFlags =
    key: action: flags:
    mkArgs [
      key
      (lua action)
      flags
    ];
  mkModBind = key: action: mkBind (lua ''mod .. " + ${key}"'') action;
  mkShiftModBind = key: action: mkBind (lua ''mod .. " + SHIFT + ${key}"'') action;
  startupCommands = [
    "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent"
    "wallpaper-apply"
    "waybar"
    "dunst"
  ];
  workspaceBinds = builtins.concatLists (
    builtins.genList (
      index:
      let
        workspace = toString (index + 1);
      in
      [
        (mkModBind workspace "hl.dsp.focus({ workspace = ${workspace} })")
        (mkShiftModBind workspace "hl.dsp.window.move({ workspace = ${workspace} })")
      ]
    ) 5
  );
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    package = null;
    portalPackage = null;

    settings = {
      mod = {
        _var = mod;
      };

      terminal = {
        _var = constants.apps.terminal.command;
      };

      explorer = {
        _var = constants.apps.explorer.command;
      };

      launcher = {
        _var = constants.apps.launcher.command;
      };

      browser = {
        _var = constants.apps.browser.command;
      };

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

          touchpad = {
            natural_scroll = true;
          };
        };

        general = {
          gaps_in = 4;
          gaps_out = 8;
          border_size = 2;
          layout = "dwindle";
          "col.active_border" = color "base0D";
          "col.inactive_border" = color "base03";
        };

        decoration = {
          rounding = 8;
        };

        group = {
          "col.border_active" = color "base0D";
          "col.border_inactive" = color "base03";
        };

        animations = {
          enabled = true;
        };

        dwindle = {
          preserve_split = true;
        };

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };
      };

      bind = [
        (mkModBind "Return" "hl.dsp.exec_cmd(terminal)")
        (mkModBind "E" "hl.dsp.exec_cmd(explorer)")
        (mkModBind "R" "hl.dsp.exec_cmd(launcher)")
        (mkModBind "B" "hl.dsp.exec_cmd(browser)")
        (mkBind "CTRL + Z" ''hl.dsp.exec_cmd(terminal .. " -e btop")'')
        (mkBind "CTRL + B" "hl.dsp.exec_cmd(browser)")

        (mkModBind "W" "hl.dsp.window.close()")
        (mkShiftModBind "W" ''hl.dsp.exec_cmd("uwsm stop")'')

        (mkModBind "F" ''hl.dsp.window.fullscreen({ action = "toggle" })'')
        (mkModBind "Space" ''hl.dsp.window.float({ action = "toggle" })'')

        (mkModBind "H" ''hl.dsp.focus({ direction = "l" })'')
        (mkModBind "L" ''hl.dsp.focus({ direction = "r" })'')
        (mkModBind "K" ''hl.dsp.focus({ direction = "u" })'')
        (mkModBind "J" ''hl.dsp.focus({ direction = "d" })'')

        (mkShiftModBind "H" ''hl.dsp.window.move({ direction = "l" })'')
        (mkShiftModBind "L" ''hl.dsp.window.move({ direction = "r" })'')
        (mkShiftModBind "K" ''hl.dsp.window.move({ direction = "u" })'')
        (mkShiftModBind "J" ''hl.dsp.window.move({ direction = "d" })'')
      ]
      ++ workspaceBinds
      ++ [
        (mkBind "XF86AudioRaiseVolume" ''hl.dsp.exec_cmd("swayosd-client --output-volume raise")'')
        (mkBind "XF86AudioLowerVolume" ''hl.dsp.exec_cmd("swayosd-client --output-volume lower")'')
        (mkBind "XF86AudioMute" ''hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle")'')
        (mkBind "XF86AudioMicMute" ''hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle")'')
        (mkBind "XF86MonBrightnessUp" ''hl.dsp.exec_cmd("swayosd-client --brightness raise")'')
        (mkBind "XF86MonBrightnessDown" ''hl.dsp.exec_cmd("swayosd-client --brightness lower")'')
        (mkBind "XF86KbdBrightnessUp" ''hl.dsp.exec_cmd("keyboard-backlight-osd raise")'')
        (mkBind "XF86KbdBrightnessDown" ''hl.dsp.exec_cmd("keyboard-backlight-osd lower")'')
        (mkBind "Print" ''hl.dsp.exec_cmd("screenshot-area-edit")'')
        (mkBind "SHIFT + Print" ''hl.dsp.exec_cmd("screenshot-full")'')
        (mkModBind "Print" ''hl.dsp.exec_cmd("screenshot-window")'')
        (mkBindWithFlags (lua ''mod .. " + mouse:272"'') "hl.dsp.window.drag()" { mouse = true; })
        (mkBindWithFlags (lua ''mod .. " + mouse:273"'') "hl.dsp.window.resize()" { mouse = true; })
      ];

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
    };
  };
}
