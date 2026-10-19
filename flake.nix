{
  description = "kitOS v0.16.3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Needs electron_44, which nixos-26.05 does not ship yet.
    claude-desktop-extra = {
      url = "github:patrickjaja/claude-desktop-extra";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    hyprland.url = "github:hyprwm/Hyprland";

    foundryvtt = {
      url = "github:nix-foundryvtt/nix-foundryvtt";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    thyx.url = "github:rccyx/thyx";

    noctalia.url = "github:noctalia-dev/noctalia";
    caelestia.url = "github:caelestia-dots/shell";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      username = "kit";
      settings = import ./lib/settings.nix { inherit system username; };
      pkgs = nixpkgs.legacyPackages.${settings.system};
      homePkgs = import nixpkgs {
        inherit (settings) system;
        config.allowUnfree = true;
      };
      homeManagerPackage = home-manager.packages.${settings.system}.default;
      pkgsUnstable = import inputs.nixpkgs-unstable {
        inherit (settings) system;
        config.allowUnfree = true;
      };
      hyprlandPkg = inputs.hyprland.packages.${settings.system}.hyprland;
      repoApps = import ./lib/repo-apps.nix {
        inherit
          lib
          settings
          pkgs
          homeManagerPackage
          profileRegistry
          ;
      };
      nixosConfiguration = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            inputs
            settings
            ;
        };

        modules = [
          ./hosts/nixos/configuration.nix
          inputs.thyx.nixosModules.default
        ];
      };
      profileRegistry = import ./profiles;
      profileIds = builtins.sort builtins.lessThan (builtins.attrNames profileRegistry.profiles);
      defaultProfile = profileRegistry.default;
      profileName = profileId: "${settings.username}-${profileId}";
      mkHomeConfiguration = import ./lib/mk-home.nix {
        inherit
          home-manager
          homePkgs
          inputs
          settings
          pkgsUnstable
          homeManagerPackage
          hyprlandPkg
          profileRegistry
          ;
      };
      profileHomes = lib.genAttrs profileIds mkHomeConfiguration;
      homeConfigurations = {
        ${settings.username} = profileHomes.${defaultProfile};
      }
      // lib.mapAttrs' (profileId: home: lib.nameValuePair (profileName profileId) home) profileHomes;
      homeChecks = lib.genAttrs profileIds (profileId: profileHomes.${profileId}.activationPackage);
      hyprlandCheck =
        themeId: home:
        let
          hyprlandLua = home.config.xdg.configFile."hypr/hyprland.lua".text;
        in
        pkgs.runCommand "hyprland-check-${themeId}"
          {
            nativeBuildInputs = [
              pkgs.lua5_4
              hyprlandPkg
            ];
          }
          ''
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            mkdir -p "$XDG_RUNTIME_DIR"
            config="$TMPDIR/hyprland.lua"
              cat ${pkgs.writeText "hyprland.lua" hyprlandLua} > "$config"
              luac -p "$config"
              Hyprland --verify-config --config "$config"
              touch "$out"
          '';
      hyprlandChecks = lib.genAttrs profileIds (
        profileId: hyprlandCheck profileId profileHomes.${profileId}
      );
      profileCheck =
        assert builtins.elem defaultProfile profileIds;
        assert builtins.all (
          profileId: builtins.pathExists profileRegistry.profiles.${profileId}.module
        ) profileIds;
        assert lib.length (lib.unique (map profileName profileIds)) == lib.length profileIds;
        assert builtins.all (
          profileId: profileHomes.${profileId}.config.kit.profile.id == profileId
        ) profileIds;
        pkgs.runCommand "profile-check" {
          buildInputs = (builtins.attrValues homeChecks) ++ (builtins.attrValues hyprlandChecks);
        } "touch $out";
      selectorSource = builtins.readFile ./home/theme-switcher.nix;
      selectorArchitectureCheck =
        assert builtins.all (needle: !(lib.hasInfix needle selectorSource)) [
          "waybar.service"
          "dunst.service"
          "swayosd.service"
          "wallpaper-apply"
          "noctalia.service"
          "caelestia.service"
        ];
        assert !(lib.hasInfix "hyprland.start" (builtins.readFile ./home/hyprland/settings.nix));
        pkgs.runCommand "profile-selector-check" { } "touch $out";
      profileOwnershipCheck =
        assert profileHomes.catppuccin.config.programs.waybar.enable;
        assert profileHomes.catppuccin.config.services.dunst.enable;
        assert profileHomes.noctalia.config.programs.noctalia.enable;
        assert profileHomes.noctalia.config.programs.noctalia.systemd.enable;
        assert
          profileHomes.noctalia.config.programs.noctalia.settings.shell.launch_apps_as_systemd_services;
        assert profileHomes.caelestia.config.programs.caelestia.enable;
        assert profileHomes.caelestia.config.programs.caelestia.systemd.enable;
        assert profileHomes.caelestia.config.programs.caelestia.cli.enable;
        pkgs.runCommand "profile-ownership-check" { } "touch $out";
    in
    {
      nixosConfigurations.${settings.hostname} = nixosConfiguration;
      inherit homeConfigurations;
      lib.themes = profileRegistry;

      formatter.${settings.system} = repoApps.scripts.fmt;

      devShells.${settings.system}.default = pkgs.mkShell {
        packages = with pkgs; [
          deadnix
          git
          just
          nil
          nixd
          nixfmt
          python3
          statix
        ];
      };

      checks.${settings.system} = {
        static =
          pkgs.runCommand "static-checks"
            {
              nativeBuildInputs = with pkgs; [
                deadnix
                nixfmt-tree
                statix
              ];
            }
            ''
              cp -r --no-preserve=mode ${self} repo
              cd repo
              ${repoApps.staticCheckCommand}
              touch $out
            '';
        profile = profileCheck;
        profile-selector = selectorArchitectureCheck;
        profile-ownership = profileOwnershipCheck;
        theme = profileCheck;
        hyprland = hyprlandChecks.${defaultProfile};
        home = homeConfigurations.${settings.username}.activationPackage;
      }
      // lib.mergeAttrsList (
        map (profileId: {
          "home-${profileId}" = homeChecks.${profileId};
          "hyprland-${profileId}" = hyprlandChecks.${profileId};
        }) profileIds
      );

      apps.${settings.system} = repoApps.apps;
    };
}
