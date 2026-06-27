{
  config,
  constants,
  pkgs,
  ...
}:

let
  colors = config.lib.stylix.colors;
  color = name: "rgb(${colors.${name}})";
  workspaceBinds = builtins.concatLists (
    builtins.genList (
      index:
      let
        workspace = toString (index + 1);
      in
      [
        "$mod, ${workspace}, workspace, ${workspace}"
        "$mod SHIFT, ${workspace}, movetoworkspace, ${workspace}"
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
      "$mod" = "SUPER";

      monitor = ",preferred,auto,1";

      env = [
        "XCURSOR_SIZE,24"
        "NIXOS_OZONE_WL,1"
      ];

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

      bind = [
        "$mod, Return, exec, ${constants.apps.terminal.command}"
        "$mod, E, exec, ${constants.apps.explorer.command}"
        "$mod, R, exec, ${constants.apps.launcher.command}"
        "$mod, B, exec, ${constants.apps.browser.command}"
        "CTRL, Z, exec, ${constants.apps.terminal.command} -e btop"
        "CTRL, B, exec, ${constants.apps.browser.command}"

        "$mod, W, killactive"
        "$mod SHIFT, W, exec, uwsm stop"

        "$mod, F, fullscreen"
        "$mod, Space, togglefloating"

        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"

        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, L, movewindow, r"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, J, movewindow, d"
      ]
      ++ workspaceBinds
      ++ [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ", XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
        ", XF86KbdBrightnessUp, exec, keyboard-backlight-osd raise"
        ", XF86KbdBrightnessDown, exec, keyboard-backlight-osd lower"

        ", Print, exec, screenshot-area-edit"
        "SHIFT, Print, exec, screenshot-full"
        "$mod, Print, exec, screenshot-window"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      exec-once = [
        "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent"
        "wallpaper-apply"
        "waybar"
        "dunst"
      ];
    };
  };
}
