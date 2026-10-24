# Noctalia fills every role of the contract (themes/contract.nix); the
# commands are the ones in binds.nix.
_:

let
  noctalia = command: "noctalia msg ${command}";
  shell = {
    name = "noctalia";
    unit = "noctalia.service";
  };
in
{
  dangonix.roles = {
    launcher = noctalia "panel-toggle launcher";
    session = noctalia "panel-toggle session";
    osd = {
      volumeUp = noctalia "volume-up";
      volumeDown = noctalia "volume-down";
      volumeMute = noctalia "volume-mute";
      micMute = noctalia "mic-mute";
      brightnessUp = noctalia "brightness-up";
      brightnessDown = noctalia "brightness-down";
      keyboardBacklightUp = noctalia "keyboard-backlight-up";
      keyboardBacklightDown = noctalia "keyboard-backlight-down";
    };
    screenshot = {
      region = noctalia "screenshot-region";
      full = noctalia "screenshot-fullscreen all";
    };

    lock = shell;
    idle = shell;
    bar = shell;
    notifications = shell;
    wallpaper = shell;
    # shell.polkit_agent = false: hyprpolkitagent registers instead.
    polkit = {
      name = "hyprpolkitagent";
      unit = "hyprpolkitagent.service";
      registered = "Adding new listener";
    };

    palette = "shell";
    toolkit = "shell";

    windowSwitcher = noctalia "window-switcher";
    controlCenter = noctalia "panel-toggle control-center";
    settings = noctalia "settings-toggle";
  };
}
