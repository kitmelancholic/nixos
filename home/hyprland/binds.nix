# The core key bindings: one list of records that calls the roles of the theme
# contract (themes/contract.nix). A bind whose role the theme leaves empty is
# left out. The descriptions stay in Nix; hyprland.lua gets only key and action.
{ config, lib, ... }:

let
  helpers = import ./lua-helpers.nix { inherit lib; };
  inherit (helpers) lua mkBind mkBindWithFlags;
  inherit (lib) mkOption types;

  cfg = config.dangonix.hyprland;
  roles = config.dangonix.roles;

  mod = key: lua ''mod .. " + ${key}"'';
  shiftMod = key: lua ''mod .. " + SHIFT + ${key}"'';

  bind = description: key: action: {
    inherit description key action;
    flags = null;
  };
  mouseBind =
    description: key: action:
    (bind description key action)
    // {
      flags = {
        mouse = true;
      };
    };

  # A role is a shell command or null; the action runs it.
  exec = command: if command == null then null else ''hl.dsp.exec_cmd("${command}")'';
  role =
    description: key: command:
    bind description key (exec command);

  workspaceBinds = builtins.concatLists (
    builtins.genList (
      index:
      let
        workspace = toString (index + 1);
      in
      [
        (bind "Go to workspace ${workspace}" (mod workspace) "hl.dsp.focus({ workspace = ${workspace} })")
        (bind "Move the window to workspace ${workspace}" (shiftMod workspace)
          "hl.dsp.window.move({ workspace = ${workspace} })"
        )
      ]
    ) 5
  );

  binds = [
    (bind "Open the terminal" (mod "Return") "hl.dsp.exec_cmd(terminal)")
    (bind "Open the file manager" (mod "E") "hl.dsp.exec_cmd(explorer)")
    (bind "Open Claude Desktop" (mod "A") ''hl.dsp.exec_cmd("claude-desktop")'')
    (role "Open the launcher" (mod "R") roles.launcher)
    (role "Open the control center" (mod "S") roles.controlCenter)
    (role "Open the shell settings" (mod "comma") roles.settings)
    (role "Switch between windows" "ALT + Tab" roles.windowSwitcher)
    (bind "Open the browser" (mod "B") "hl.dsp.exec_cmd(browser)")
    (bind "Open Neovim in the terminal" (mod "N") ''hl.dsp.exec_cmd(terminal .. " -e nvim")'')
    (bind "Open btop in the terminal" (mod "Z") ''hl.dsp.exec_cmd(terminal .. " -e btop")'')
    (bind "Open the browser" "CTRL + B" "hl.dsp.exec_cmd(browser)")

    (bind "Close the window" (mod "W") "hl.dsp.window.close()")
    (role "Open the session menu" (mod "Escape") roles.session)
    (role "Open the session menu" (shiftMod "W") roles.session)

    (bind "Toggle fullscreen" (mod "F") ''hl.dsp.window.fullscreen({ action = "toggle" })'')
    (bind "Toggle floating" (mod "Space") ''hl.dsp.window.float({ action = "toggle" })'')

    (bind "Focus the window to the left" (mod "H") ''hl.dsp.focus({ direction = "l" })'')
    (bind "Focus the window to the right" (mod "L") ''hl.dsp.focus({ direction = "r" })'')
    (bind "Focus the window above" (mod "K") ''hl.dsp.focus({ direction = "u" })'')
    (bind "Focus the window below" (mod "J") ''hl.dsp.focus({ direction = "d" })'')

    (bind "Move the window to the left" (shiftMod "H") ''hl.dsp.window.move({ direction = "l" })'')
    (bind "Move the window to the right" (shiftMod "L") ''hl.dsp.window.move({ direction = "r" })'')
    (bind "Move the window up" (shiftMod "K") ''hl.dsp.window.move({ direction = "u" })'')
    (bind "Move the window down" (shiftMod "J") ''hl.dsp.window.move({ direction = "d" })'')
  ]
  ++ workspaceBinds
  ++ [
    (role "Raise the volume" "XF86AudioRaiseVolume" roles.osd.volumeUp)
    (role "Lower the volume" "XF86AudioLowerVolume" roles.osd.volumeDown)
    (role "Mute the output" "XF86AudioMute" roles.osd.volumeMute)
    (role "Mute the microphone" "XF86AudioMicMute" roles.osd.micMute)
    (role "Raise the screen brightness" "XF86MonBrightnessUp" roles.osd.brightnessUp)
    (role "Lower the screen brightness" "XF86MonBrightnessDown" roles.osd.brightnessDown)
    (role "Raise the keyboard backlight" "XF86KbdBrightnessUp" roles.osd.keyboardBacklightUp)
    (role "Lower the keyboard backlight" "XF86KbdBrightnessDown" roles.osd.keyboardBacklightDown)
    (role "Screenshot of a region" "Print" roles.screenshot.region)
    (role "Screenshot of every screen" "SHIFT + Print" roles.screenshot.full)
    (mouseBind "Drag the window with the mouse" (mod "mouse:272") "hl.dsp.window.drag()")
    (mouseBind "Resize the window with the mouse" (mod "mouse:273") "hl.dsp.window.resize()")
  ];

  emit =
    entry:
    if entry.flags == null then
      mkBind entry.key entry.action
    else
      mkBindWithFlags entry.key entry.action entry.flags;
in
{
  options.dangonix.hyprland = {
    coreBinds = mkOption {
      type = types.bool;
      default = true;
      description = "Emit the core binds; a theme that does not meet the role contract yet turns it off and keeps its own list.";
    };
    binds = mkOption {
      type = types.listOf types.attrs;
      readOnly = true;
      default = lib.filter (entry: entry.action != null) binds;
      description = "The core binds as records (description, key, action, flags).";
    };
  };

  config.wayland.windowManager.hyprland.settings = {
    mod._var = "SUPER";
    terminal._var = config.dangonix.apps.terminal.command;
    explorer._var = config.dangonix.apps.explorer.command;
    browser._var = config.dangonix.apps.browser.command;
    bind = lib.mkIf cfg.coreBinds (map emit cfg.binds);
  };
}
