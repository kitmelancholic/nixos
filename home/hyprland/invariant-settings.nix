_:

let
  mkEnv = name: value: {
    _args = [
      name
      value
    ];
  };
in

{
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

  config.input = {
    kb_layout = "us,ua";
    kb_options = "grp:alt_shift_toggle";
    follow_mouse = 1;
    touchpad.natural_scroll = true;
  };

  config.misc = {
    disable_hyprland_logo = true;
    disable_splash_rendering = true;
  };
}
