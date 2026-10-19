{ pkgs, settings, ... }:

{
  virtualisation.docker.enable = true;

  users.users.${settings.username}.extraGroups = [ "docker" ];

  # Тримає ppd performance, поки активний gamemode; stop знімає hold.
  systemd.user.services.gamemode-performance = {
    description = "Hold ppd performance profile while GameMode is active";
    serviceConfig.ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl launch --profile performance --reason gamemode -- ${pkgs.coreutils}/bin/sleep infinity";
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      protontricks.enable = true;
    };

    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10; # пріоритет процесу гри
          # Профілем CPU керує ppd; gamemode не чіпає governor, щоб не битися з ним за EPP.
          desiredgov = "powersave";
          defaultgov = "powersave";
        };
        # Hold, а не set: ppd сам поверне попередній профіль (saver/balanced).
        custom = {
          start = "${pkgs.systemd}/bin/systemctl --user start gamemode-performance.service";
          end = "${pkgs.systemd}/bin/systemctl --user stop gamemode-performance.service";
        };
      };
    };
    gamescope = {
      enable = true;
      capSysNice = true;
    };

    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture # OBS per-app PipeWire audio capture
        obs-vaapi # VAAPI hardware encoding support
        obs-vkcapture # Vulkan game capture support
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    gamescope # Nested compositor for Steam/game launch options
    mangohud # Gaming performance overlay
    protonup-qt # Proton-GE manager
    discord
    vesktop # Wayland window sharing with application audio
  ];
}
