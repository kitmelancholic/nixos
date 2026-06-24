{
  services.displayManager = {
    sddm = {
      enable = true;
      thyx.enable = true;
      wayland.enable = true;
    };

    defaultSession = "hyprland-uwsm";
  };
}
