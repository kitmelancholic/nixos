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
        inherit settings pkgs homeManagerPackage;
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
      homeConfiguration = home-manager.lib.homeManagerConfiguration {
        pkgs = homePkgs;
        modules = [
          inputs.stylix.homeModules.stylix
          ./home/kit.nix
        ];
        extraSpecialArgs = {
          inherit
            inputs
            settings
            pkgsUnstable
            ;
        };
      };
      theme = import ./themes;
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
        assert builtins.pathExists theme.wallpaper;
        assert builtins.all (key: builtins.hasAttr key theme.base16Scheme) requiredBase16Keys;
        pkgs.runCommand "theme-check" { } "touch $out";
      hyprlandLua = homeConfiguration.config.xdg.configFile."hypr/hyprland.lua".text;
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
      homeConfigurations.${settings.username} = homeConfiguration;

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
        home = homeConfiguration.activationPackage;
      };

      apps.${settings.system} = repoApps.apps;
    };
}
