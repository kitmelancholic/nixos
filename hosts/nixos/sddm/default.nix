{
  config,
  pkgs,
  ...
}:

let
  pamModules = "${config.security.pam.package}/lib/security";
in
{
  services.displayManager.sddm = {
    # A typed password replaces the theme's pending fingerprint login.
    package = pkgs.kdePackages.sddm.override {
      sddm-unwrapped = pkgs.kdePackages.sddm.unwrapped.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./cancel-fingerprint-auth.patch ];
      });
    };

    settings.Theme = {
      CursorTheme = "Bibata-Modern-Ice";
      CursorSize = 24;
    };
  };

  environment.systemPackages = [
    pkgs.bibata-cursors # Greeter pointer, the cursor every theme uses
  ];

  # A typed password succeeds at unix and unlocks the keyring; the theme's
  # empty one fails fast and waits for a finger in the login substack.
  security.pam.services.sddm.rules.auth = {
    unix-early = {
      order = 10000;
      control = "optional";
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
