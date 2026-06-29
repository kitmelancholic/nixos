{ lib }:

let
  helpers = import ./lua-helpers.nix { inherit lib; };
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
in
[
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
]
