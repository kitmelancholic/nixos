{ lib }:

let
  helpers = import ../../home/hyprland/lua-helpers.nix { inherit lib; };
  inherit (helpers)
    lua
    mkBind
    mkBindWithFlags
    mkModBind
    mkShiftModBind
    ;

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

  noctalia = command: ''hl.dsp.exec_cmd("noctalia msg ${command}")'';
in
[
  (mkModBind "Return" "hl.dsp.exec_cmd(terminal)")
  (mkModBind "E" "hl.dsp.exec_cmd(explorer)")
  (mkModBind "A" ''hl.dsp.exec_cmd("claude-desktop")'')
  (mkModBind "R" (noctalia "panel-toggle launcher"))
  (mkModBind "S" (noctalia "panel-toggle control-center"))
  (mkModBind "comma" (noctalia "settings-toggle"))
  (mkBind "ALT + Tab" (noctalia "window-switcher"))
  (mkModBind "B" "hl.dsp.exec_cmd(browser)")
  (mkModBind "N" ''hl.dsp.exec_cmd(terminal .. " -e nvim")'')
  (mkModBind "Z" ''hl.dsp.exec_cmd(terminal .. " -e btop")'')
  (mkBind "CTRL + B" "hl.dsp.exec_cmd(browser)")

  (mkModBind "W" "hl.dsp.window.close()")
  (mkModBind "Escape" (noctalia "panel-toggle session"))
  (mkShiftModBind "W" (noctalia "panel-toggle session"))

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
  (mkBind "XF86AudioRaiseVolume" (noctalia "volume-up"))
  (mkBind "XF86AudioLowerVolume" (noctalia "volume-down"))
  (mkBind "XF86AudioMute" (noctalia "volume-mute"))
  (mkBind "XF86AudioMicMute" (noctalia "mic-mute"))
  (mkBind "XF86MonBrightnessUp" (noctalia "brightness-up"))
  (mkBind "XF86MonBrightnessDown" (noctalia "brightness-down"))
  (mkBind "XF86KbdBrightnessUp" (noctalia "keyboard-backlight-up"))
  (mkBind "XF86KbdBrightnessDown" (noctalia "keyboard-backlight-down"))
  (mkBind "Print" (noctalia "screenshot-region"))
  (mkBind "SHIFT + Print" (noctalia "screenshot-fullscreen all"))
  (mkBindWithFlags (lua ''mod .. " + mouse:272"'') "hl.dsp.window.drag()" { mouse = true; })
  (mkBindWithFlags (lua ''mod .. " + mouse:273"'') "hl.dsp.window.resize()" { mouse = true; })
]
