{
  config,
  lib,
  pkgs,
  ...
}:

{
  # One icon theme for every theme: GTK apps and the Quickshell shells' tray
  # menus, which otherwise draw a missing-icon checkerboard for names like
  # `window-close` that hicolor lacks.
  gtk = {
    enable = true;
    iconTheme = lib.mapAttrs (_: lib.mkDefault) {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
    };
  };

  # Quickshell resolves icons through Qt, which reads no GTK setting.
  systemd.user.sessionVariables.QS_ICON_THEME = config.gtk.iconTheme.name;
}
