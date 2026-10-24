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

  exec = command: ''hl.dsp.exec_cmd("${command}")'';
  caelestia = command: exec "caelestia ${command}";
  drawer = name: caelestia "shell drawers toggle ${name}";
in
# The same keys as Noctalia's binds.nix; Caelestia's shell IPC where Noctalia
# has a panel, wpctl and brightnessctl where Caelestia has no IPC.
[
  (mkModBind "Return" "hl.dsp.exec_cmd(terminal)")
  (mkModBind "E" "hl.dsp.exec_cmd(explorer)")
  (mkModBind "A" ''hl.dsp.exec_cmd("claude-desktop")'')
  (mkModBind "R" (drawer "launcher"))
  (mkModBind "S" (drawer "dashboard"))
  (mkModBind "comma" (caelestia "shell nexus open"))
  (mkBind "ALT + Tab" "hl.dsp.window.cycle_next()")
  (mkModBind "B" "hl.dsp.exec_cmd(browser)")
  (mkModBind "N" ''hl.dsp.exec_cmd(terminal .. " -e nvim")'')
  (mkModBind "Z" ''hl.dsp.exec_cmd(terminal .. " -e btop")'')
  (mkBind "CTRL + B" "hl.dsp.exec_cmd(browser)")

  (mkModBind "W" "hl.dsp.window.close()")
  (mkModBind "Escape" (drawer "session"))
  (mkShiftModBind "W" (drawer "session"))

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
  (mkBind "XF86AudioRaiseVolume" (exec "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"))
  (mkBind "XF86AudioLowerVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
  (mkBind "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
  (mkBind "XF86AudioMicMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
  (mkBind "XF86MonBrightnessUp" (caelestia "shell brightness set +5%"))
  (mkBind "XF86MonBrightnessDown" (caelestia "shell brightness set 5%-"))
  (mkBind "XF86KbdBrightnessUp" (exec "brightnessctl -d '*::kbd_backlight' set +1"))
  (mkBind "XF86KbdBrightnessDown" (exec "brightnessctl -d '*::kbd_backlight' set 1-"))
  (mkBind "Print" (caelestia "screenshot -r"))
  (mkBind "SHIFT + Print" (caelestia "screenshot"))
  (mkBindWithFlags (lua ''mod .. " + mouse:272"'') "hl.dsp.window.drag()" { mouse = true; })
  (mkBindWithFlags (lua ''mod .. " + mouse:273"'') "hl.dsp.window.resize()" { mouse = true; })
]
