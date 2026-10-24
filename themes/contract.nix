# The theme contract (docs/design.md §3, "Ролі"): the core calls roles, a
# theme fills them. A required role without a value is an evaluation error
# (`theme <id>: role <role> has no provider`); in an `experimental` theme it
# is only a warning (warning mode, until Caelestia meets the contract in
# campaign II). `keybindings`, `clipboard` and `search` are registered then;
# `appearance` is `dangonix.look.appearance`, not an option of its own.
{
  config,
  lib,
  profileRegistry,
  ...
}:

let
  inherit (lib) mkOption types;
  cfg = config.dangonix.roles;
  themeId = config.dangonix.theme.id;
  inherit (profileRegistry.themes.${themeId}) status;

  command =
    description:
    mkOption {
      type = types.nullOr types.str;
      default = null;
      inherit description;
    };

  providerType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "The program that provides the role.";
      };
      unit = mkOption {
        type = types.strMatching ".+\\.service";
        description = "The user unit that runs it.";
      };
      registered = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Journal line of the unit that shows the provider registered (a fixed string `dangonix doctor` looks for).";
      };
    };
  };

  provider =
    description:
    mkOption {
      type = types.nullOr providerType;
      default = null;
      inherit description;
    };

  osdKeys = {
    volumeUp = "Raise the volume (XF86AudioRaiseVolume).";
    volumeDown = "Lower the volume (XF86AudioLowerVolume).";
    volumeMute = "Mute the output (XF86AudioMute).";
    micMute = "Mute the microphone (XF86AudioMicMute).";
    brightnessUp = "Raise the screen brightness (XF86MonBrightnessUp).";
    brightnessDown = "Lower the screen brightness (XF86MonBrightnessDown).";
    keyboardBacklightUp = "Raise the keyboard backlight (XF86KbdBrightnessUp).";
    keyboardBacklightDown = "Lower the keyboard backlight (XF86KbdBrightnessDown).";
  };

  # Required roles by kind; each is the option path under dangonix.roles.
  required = [
    [ "launcher" ]
    [ "session" ]
  ]
  ++ map (key: [
    "osd"
    key
  ]) (builtins.attrNames osdKeys)
  ++ [
    [
      "screenshot"
      "region"
    ]
    [
      "screenshot"
      "full"
    ]
    [ "lock" ]
    [ "idle" ]
    [ "bar" ]
    [ "notifications" ]
    [ "polkit" ]
    [ "wallpaper" ]
    [ "palette" ]
    [ "toolkit" ]
  ];

  missing = map (lib.concatStringsSep ".") (
    lib.filter (path: lib.attrByPath path null cfg == null) required
  );

  providers = lib.filterAttrs (_: value: value != null) (
    lib.getAttrs [
      "lock"
      "idle"
      "bar"
      "notifications"
      "polkit"
      "wallpaper"
    ] cfg
  );

  noProvider = role: "theme ${themeId}: role ${role} has no provider";
in
{
  options.dangonix.roles = {
    launcher = command "Open the launcher (SUPER+R).";
    session = command "Open the session menu (SUPER+Escape, SUPER+Shift+W).";
    osd = lib.mapAttrs (_: command) osdKeys;
    screenshot = {
      region = command "Screenshot of a region (Print).";
      full = command "Screenshot of every screen (Shift+Print).";
      window = command "Screenshot of a window (SUPER+Print); optional.";
    };

    lock = provider "Locks the session (`loginctl lock-session`, idle, suspend).";
    idle = provider "Idle daemon.";
    bar = provider "The bar.";
    notifications = provider "Owner of org.freedesktop.Notifications.";
    polkit = provider "Registered polkit authentication agent.";
    wallpaper = provider "Draws the wallpaper.";

    palette = mkOption {
      type = types.nullOr (
        types.enum [
          "shell"
          "static"
        ]
      );
      default = null;
      description = "Where the palette comes from: the shell's own theming engine, or a fixed one.";
    };
    toolkit = mkOption {
      type = types.nullOr (
        types.enum [
          "shell"
          "none"
        ]
      );
      default = null;
      description = "Who themes GTK, Qt and the cursor: the shell, or nobody.";
    };

    windowSwitcher = command "Window switcher (ALT+Tab); optional.";
    controlCenter = command "Control center (SUPER+S); optional.";
    settings = command "Shell settings (SUPER+comma); optional.";
  };

  options.dangonix.rolesMissing = mkOption {
    type = types.listOf types.str;
    readOnly = true;
    default = missing;
    description = "Required roles the theme leaves empty.";
  };

  config = {
    assertions =
      lib.optionals (status == "stable") (
        map (role: {
          assertion = false;
          message = noProvider role;
        }) missing
      )
      ++ lib.mapAttrsToList (role: value: {
        assertion = config.systemd.user.services ? ${lib.removeSuffix ".service" value.unit};
        message = "theme ${themeId}: role ${role}: no user unit ${value.unit} is defined";
      }) providers;

    warnings = lib.optional (status != "stable" && missing != [ ]) (
      "theme ${themeId} (${status}): roles without a provider, tolerated until campaign II: "
      + lib.concatStringsSep " " missing
    );
  };
}
