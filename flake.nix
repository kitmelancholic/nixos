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
      checks = import ./lib/checks.nix {
        inherit
          lib
          pkgs
          hyprlandPkg
          profileRegistry
          profileHomes
          ;
        src = self;
        inherit (repoApps) staticCheckCommand;
        host = nixosConfiguration;
      };
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

      checks.${settings.system} = checks;

      apps.${settings.system} = repoApps.apps;
    };
}
