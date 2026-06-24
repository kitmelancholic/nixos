{ inputs, pkgs, ... }:

{
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
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

  services = {
    fprintd.enable = true;
    gnome.gnome-keyring.enable = true;
    udisks2.enable = true;
    gvfs.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;
    blueman.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  environment.systemPackages = with pkgs; [
    bluez # Bluetooth CLI tools including bluetoothctl
    blueman # Bluetooth GUI manager
    brightnessctl # Laptop backlight control
    hyprpolkitagent # Wayland polkit authentication agent
    networkmanager # Wi-Fi/network CLI tools including nmcli and nmtui
    networkmanagerapplet # NetworkManager tray integration
    power-profiles-daemon # Laptop power profile CLI/service package
    usbutils # Fingerprint device ID inspection
  ];
}
