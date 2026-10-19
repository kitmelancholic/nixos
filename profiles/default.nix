{
  default = "noctalia";

  profiles = {
    catppuccin = {
      name = "Catppuccin";
      description = "The classic kitOS desktop with Catppuccin colors.";
      module = ../themes/catppuccin;
    };
    tokyo-night = {
      name = "Tokyo Night";
      description = "The classic kitOS desktop with Tokyo Night colors.";
      module = ../themes/tokyo-night;
    };
    gruvbox = {
      name = "Gruvbox";
      description = "The classic kitOS desktop with Gruvbox colors.";
      module = ../themes/gruvbox;
    };
    kit-dark = {
      name = "Kit Dark";
      description = "The classic kitOS desktop with Kit Dark colors.";
      module = ../themes/kit-dark;
    };
    noctalia = {
      name = "Noctalia";
      description = "Noctalia v5 as the complete Wayland desktop shell.";
      module = ./noctalia;
    };
    caelestia = {
      name = "Caelestia";
      description = "Caelestia as the complete Hyprland desktop shell.";
      module = ./caelestia;
    };
  };
}
