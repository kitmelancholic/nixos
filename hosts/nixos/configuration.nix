{
  settings,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware.nix
    ./desktop.nix
    ./workloads.nix
    ./foundryvtt.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    kernelPackages = pkgs.linuxPackages_latest;
  };

  time.timeZone = "Europe/Kyiv";

  i18n = {
    defaultLocale = "uk_UA.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "uk_UA.UTF-8";
      LC_IDENTIFICATION = "uk_UA.UTF-8";
      LC_MEASUREMENT = "uk_UA.UTF-8";
      LC_MONETARY = "uk_UA.UTF-8";
      LC_NAME = "uk_UA.UTF-8";
      LC_NUMERIC = "uk_UA.UTF-8";
      LC_PAPER = "uk_UA.UTF-8";
      LC_TELEPHONE = "uk_UA.UTF-8";
      LC_TIME = "uk_UA.UTF-8";
    };
  };

  console.keyMap = "ua-utf";

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      extra-substituters = [ "https://hyprland.cachix.org" ];
      extra-trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
        libgcc
      ];
    };

    fish.enable = true;
  };

  users.users.${settings.username} = {
    isNormalUser = true;
    description = settings.username;
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
    ];
    packages = [ ];
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    neovim
    wget
  ];

  networking = {
    hostName = settings.hostname;
    networkmanager.enable = true;
  };

  services.xserver.xkb = {
    layout = "us,ua";
    options = "grp:alt_shift_toggle";
  };

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "26.05";
}
