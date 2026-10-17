{ lib, pkgs, ... }:

{
  # One cursor for every theme: GTK apps (Nautilus), X11 and Hyprland. The
  # classic themes' Stylix sets the same cursor and wins until c1q09.
  home.pointerCursor = lib.mapAttrs (_: lib.mkDefault) {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };
}
