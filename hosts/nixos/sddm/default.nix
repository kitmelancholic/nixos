{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  pamModules = "${config.security.pam.package}/lib/security";

  # The greeter binds wl_pointer after weston focused it, so the enter it
  # gets carries serial 0 and Qt never sets a cursor.
  weston = pkgs.weston.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./weston-pointer-focus-serial.patch ];
  });
in
{
  services.displayManager.sddm = {
    # A typed password replaces the theme's pending fingerprint login.
    package = pkgs.kdePackages.sddm.override {
      sddm-unwrapped = pkgs.kdePackages.sddm.unwrapped.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./cancel-fingerprint-auth.patch ];
      });
    };

    # nixpkgs' weston command and weston.ini, with the patched weston.
    wayland.compositorCommand =
      builtins.replaceStrings [ (lib.getExe pkgs.weston) ] [ (lib.getExe weston) ]
        options.services.displayManager.sddm.wayland.compositorCommand.default;

    settings.Theme = {
      CursorTheme = "Bibata-Modern-Ice";
      CursorSize = 24;
    };
  };

  environment.systemPackages = [
    pkgs.bibata-cursors # Greeter pointer, the cursor every theme uses
  ];

  # A typed password succeeds at unix and unlocks the keyring; the theme's
  # empty one fails fast and waits for a finger in the login substack. The
  # keyring only sees a password unix-early accepted: an empty one would
  # re-encrypt the login keyring with it.
  security.pam.services.sddm.rules.auth = {
    unix-early = {
      order = 10000;
      control = "[success=ignore default=1]";
      modulePath = "${pamModules}/pam_unix.so";
      settings = {
        likeauth = true;
        nullok = true;
      };
    };
    gnome_keyring = {
      order = 10020;
      enable = config.services.gnome.gnome-keyring.enable;
      control = "optional";
      modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
    };
    unix = {
      order = 10040;
      control = "sufficient";
      modulePath = "${pamModules}/pam_unix.so";
      settings = {
        likeauth = true;
        try_first_pass = true;
        nodelay = true;
      };
    };
  };
}
