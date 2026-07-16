{ inputs, pkgs, ... }:

let
  hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  services = {
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      jack.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
      extraConfig.pipewire."60-stream-mix" = {
        "context.objects" = [
          {
            factory = "adapter";
            args = {
              "factory.name" = "support.null-audio-sink";
              "node.name" = "stream_mix";
              "node.description" = "Stream Mix";
              "media.class" = "Audio/Sink";
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
          }
        ];
      };
    };

    displayManager = {
      sddm = {
        enable = true;
        thyx.enable = true;
        wayland.enable = true;
      };

      defaultSession = "hyprland-uwsm";
    };

    fprintd.enable = true;
    gnome.gnome-keyring.enable = true;
    udisks2.enable = true;
    gvfs.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;
    blueman.enable = true;
  };

  programs = {
    dconf.enable = true;

    hyprland = {
      enable = true;
      package = hyprlandPackages.hyprland;
      portalPackage = hyprlandPackages.xdg-desktop-portal-hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };

    hyprlock.enable = true;
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk # GTK file picker portal backend
    ];
  };

  security = {
    polkit.enable = true;
    pam.services = {
      sudo.fprintAuth = true;
      login.fprintAuth = true;
      sddm.fprintAuth = true;
    };
    rtkit.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      jetbrains-mono
      nerd-fonts.jetbrains-mono
    ];
  };

  environment.systemPackages = with pkgs; [
    bluetuith # Terminal Bluetooth manager
    brightnessctl # Laptop backlight control
    hyprpolkitagent # Wayland polkit authentication agent
    networkmanagerapplet # NetworkManager tray integration
    usbutils # Fingerprint device ID inspection
  ];
}
