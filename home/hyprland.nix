{
  config,
  constants,
  lib,
  pkgs,
  ...
}:

let
  lua = lib.generators.mkLuaInline;
  mod = ''mod .. " + '';
  dispatch = expr: lua "hl.dsp.${expr}";
  bind = key: dispatcher: {
    _args = [
      (lua "${mod}${key}\"")
      dispatcher
    ];
  };
  bindNoMod = key: dispatcher: {
    _args = [
      key
      dispatcher
    ];
  };
  mouseBind = key: dispatcher: {
    _args = [
      (lua "${mod}${key}\"")
      dispatcher
      { mouse = true; }
    ];
  };
  colors = config.lib.stylix.colors;
  color = name: lua "\"rgb(${colors.${name}})\"";
  workspaceBinds =
    lib.concatMap
      (
        workspace:
        let
          key = toString workspace;
        in
        [
          (bind key (dispatch "focus({ workspace = ${key} })"))
          (bind "SHIFT + ${key}" (dispatch "window.move({ workspace = ${key} })"))
        ]
      )
      [
        1
        2
        3
        4
        5
      ];
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    configType = "lua";
    importantPrefixes = [
      "env"
      "monitor"
      "config"
    ];

    settings = {
      mod._var = "SUPER";
      terminal._var = constants.apps.terminal.command;
      explorer._var = constants.apps.explorer.command;
      launcher._var = constants.apps.launcher.command;
      browser._var = constants.apps.browser.command;

      monitor = {
        output = "";
        mode = "1600x900@60";
        position = "auto";
        scale = 1;
      };

      env = [
        {
          _args = [
            "XCURSOR_SIZE"
            "24"
          ];
        }
        {
          _args = [
            "NIXOS_OZONE_WL"
            "1"
          ];
        }
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
          pseudotile = true;
          preserve_split = true;
        };

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };
      };

      bind = [
        (bind "Return" (lua "hl.dsp.exec_cmd(terminal)"))
        (bind "E" (lua "hl.dsp.exec_cmd(explorer)"))
        (bind "R" (lua "hl.dsp.exec_cmd(launcher)"))
        (bind "B" (lua "hl.dsp.exec_cmd(browser)"))
        (bindNoMod "CTRL + Z" (lua ''hl.dsp.exec_cmd(terminal .. " -e btop")''))
        (bindNoMod "CTRL + B" (lua "hl.dsp.exec_cmd(browser)"))

        (bind "W" (dispatch "window.close()"))
        (bind "SHIFT + W" (dispatch ''exec_cmd("uwsm stop")''))

        (bind "F" (dispatch ''window.fullscreen({ action = "toggle" })''))
        (bind "Space" (dispatch ''window.float({ action = "toggle" })''))

        (bind "H" (dispatch ''focus({ direction = "l" })''))
        (bind "L" (dispatch ''focus({ direction = "r" })''))
        (bind "K" (dispatch ''focus({ direction = "u" })''))
        (bind "J" (dispatch ''focus({ direction = "d" })''))

        (bind "SHIFT + H" (dispatch ''window.move({ direction = "l" })''))
        (bind "SHIFT + L" (dispatch ''window.move({ direction = "r" })''))
        (bind "SHIFT + K" (dispatch ''window.move({ direction = "u" })''))
        (bind "SHIFT + J" (dispatch ''window.move({ direction = "d" })''))
      ]
      ++ workspaceBinds
      ++ [
        (bindNoMod "XF86AudioRaiseVolume" (dispatch ''exec_cmd("swayosd-client --output-volume raise")''))
        (bindNoMod "XF86AudioLowerVolume" (dispatch ''exec_cmd("swayosd-client --output-volume lower")''))
        (bindNoMod "XF86AudioMute" (dispatch ''exec_cmd("swayosd-client --output-volume mute-toggle")''))
        (bindNoMod "XF86AudioMicMute" (dispatch ''exec_cmd("swayosd-client --input-volume mute-toggle")''))
        (bindNoMod "XF86MonBrightnessUp" (dispatch ''exec_cmd("swayosd-client --brightness raise")''))
        (bindNoMod "XF86MonBrightnessDown" (dispatch ''exec_cmd("swayosd-client --brightness lower")''))
        (bindNoMod "XF86KbdBrightnessUp" (dispatch ''exec_cmd("keyboard-backlight-osd raise")''))
        (bindNoMod "XF86KbdBrightnessDown" (dispatch ''exec_cmd("keyboard-backlight-osd lower")''))

        (bindNoMod "Print" (dispatch ''exec_cmd("screenshot-area-edit")''))
        (bindNoMod "SHIFT + Print" (dispatch ''exec_cmd("screenshot-full")''))
        (bind "Print" (dispatch ''exec_cmd("screenshot-window")''))

        (mouseBind "mouse:272" (dispatch "window.drag()"))
        (mouseBind "mouse:273" (dispatch "window.resize()"))
      ];

      on = {
        _args = [
          "hyprland.start"
          (lua ''
            function()
              hl.exec_cmd("${pkgs.hyprpolkitagent}/bin/hyprpolkitagent")
              hl.exec_cmd("wallpaper-apply")
              hl.exec_cmd("waybar")
              hl.exec_cmd("dunst")
            end
          '')
        ];
      };
    };
  };
}
