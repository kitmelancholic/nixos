{
  description = "kitOS v0.15";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

    graphify = {
      url = "github:Graphify-Labs/graphify";
      flake = false;
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
      pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.${settings.system};
      hyprlandPkg = inputs.hyprland.packages.${settings.system}.hyprland;
      repoApps = import ./lib/repo-apps.nix {
        inherit
          lib
          settings
          pkgs
          homeManagerPackage
          themeModel
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
      themeModel = import ./lib/theme-model.nix { inherit lib settings; };
      inherit (themeModel) default ids;
      themeIds = ids;
      defaultTheme = default;
      inherit (themeModel) profileName;
      mkHomeConfiguration = import ./lib/mk-home.nix {
        inherit
          home-manager
          homePkgs
          inputs
          settings
          pkgsUnstable
          homeManagerPackage
          hyprlandPkg
          themeModel
          ;
        themeFlakeSource = self.outPath;
      };
      themeHomes = lib.listToAttrs (
        map (themeId: lib.nameValuePair (profileName themeId) (mkHomeConfiguration themeId)) themeIds
      );
      homeConfigurations = themeHomes // {
        ${settings.username} = themeHomes.${profileName defaultTheme};
      };
      themeOverrideCanary = themeHomes.${profileName defaultTheme}.extendModules {
        modules = [
          {
            kit.apps.launcher.command = "fuzzel";
            wayland.windowManager.hyprland.settings.config.general.layout = "master";
          }
        ];
      };
      themeOverrideCheck =
        assert themeOverrideCanary.config.kit.apps.launcher.command == "fuzzel";
        assert
          themeOverrideCanary.config.wayland.windowManager.hyprland.settings.config.general.layout
          == "master";
        pkgs.runCommand "theme-override-check" { } "touch $out";
      themeCheck =
        assert builtins.elem defaultTheme themeIds;
        assert builtins.all (themeId: builtins.pathExists (themeModel.moduleFor themeId)) themeIds;
        assert lib.length (lib.unique (map profileName themeIds)) == lib.length themeIds;
        assert builtins.all (
          themeId: themeHomes.${profileName themeId}.config.kit.theme.id == themeId
        ) themeIds;
        pkgs.runCommand "theme-check" { } "touch $out";
      hyprlandCheck =
        themeId:
        let
          hyprlandLua = (mkHomeConfiguration themeId).config.xdg.configFile."hypr/hyprland.lua".text;
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
    in
    {
      nixosConfigurations.${settings.hostname} = nixosConfiguration;
      inherit homeConfigurations;

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
        theme = themeCheck;
        theme-override = themeOverrideCheck;
        hyprland = hyprlandCheck defaultTheme;
        home = homeConfigurations.${settings.username}.activationPackage;
      }
      // lib.mergeAttrsList (
        map (themeId: {
          "home-${themeId}" = themeHomes."${profileName themeId}".activationPackage;
          "hyprland-${themeId}" = hyprlandCheck themeId;
        }) themeIds
      );

      apps.${settings.system} = repoApps.apps;
    };
}
