{
  description = "kitOS v0.14";

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
      system = "x86_64-linux";
      username = "kit";
      settings = import ./lib/settings.nix { inherit system username; };
      pkgs = nixpkgs.legacyPackages.${settings.system};
      pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.${settings.system};
      hyprlandPkg = inputs.hyprland.packages.${settings.system}.hyprland;
      repoApps = import ./lib/repo-apps.nix { inherit settings pkgs; };
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

          home-manager.nixosModules.default
          inputs.thyx.nixosModules.default

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = {
                inherit
                  inputs
                  settings
                  pkgsUnstable
                  ;
              };

              users.${settings.username} = import ./home/kit.nix;
              sharedModules = [ inputs.stylix.homeModules.stylix ];
            };
          }
        ];
      };
      themeSet = import ./themes;
      requiredBase16Keys = [
        "base00"
        "base01"
        "base02"
        "base03"
        "base04"
        "base05"
        "base06"
        "base07"
        "base08"
        "base09"
        "base0A"
        "base0B"
        "base0C"
        "base0D"
        "base0E"
        "base0F"
      ];
      themeCheck =
        assert builtins.hasAttr themeSet.selected themeSet.themes;
        assert builtins.all (name: builtins.pathExists themeSet.themes.${name}.wallpaper) (
          builtins.attrNames themeSet.themes
        );
        assert builtins.all (
          name:
          builtins.all (key: builtins.hasAttr key themeSet.themes.${name}.base16Scheme) requiredBase16Keys
        ) (builtins.attrNames themeSet.themes);
        pkgs.runCommand "theme-check" { } "touch $out";
      hyprlandLua =
        nixosConfiguration.config.home-manager.users.${settings.username}.xdg.configFile."hypr/hyprland.lua".text;
      hyprlandCheck =
        pkgs.runCommand "hyprland-check"
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
              cp -r ${self} repo
              cd repo
              ${repoApps.staticCheckCommand}
              touch $out
            '';
        theme = themeCheck;
        hyprland = hyprlandCheck;
      };

      apps.${settings.system} = repoApps.apps;
    };
}
