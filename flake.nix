{
  description = "dangoNix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Needs electron_44, which nixos-26.05 does not ship yet.
    claude-desktop-extra = {
      url = "github:patrickjaja/claude-desktop-extra";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Home Manager module (home/hermes.nix). Keeps its own nixpkgs: with
    # nixpkgs-unstable, npm segfaults while building hermes-tui.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.home-manager.follows = "home-manager"; # only its checks use it
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

    thyx = {
      url = "github:rccyx/thyx";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      state = lib.importJSON ./state.json;
      settings = import ./lib/settings.nix { inherit system username state; };
      foundryTable = lib.importJSON "${inputs.foundryvtt}/pkgs/foundryvtt/versions.json";
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
      repoApps = import ./lib/repo-apps.nix { inherit pkgs; };
      dangonix = import ./lib/dangonix {
        inherit
          lib
          pkgs
          settings
          foundryTable
          ;
        themes = profileIds;
        repo = "${settings.homeDirectory}/nixos";
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
      profileRegistry = import ./themes // {
        default = state.theme;
      };
      profileIds = builtins.sort builtins.lessThan (builtins.attrNames profileRegistry.themes);
      defaultProfile = profileRegistry.default;
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
      # `dangonix` builds `<username>-<theme>`; the bare name is the default.
      homeConfigurations = {
        ${settings.username} = profileHomes.${defaultProfile};
      }
      // lib.mapAttrs' (
        profileId: home: lib.nameValuePair "${settings.username}-${profileId}" home
      ) profileHomes;
      checks = import ./lib/checks.nix {
        inherit
          lib
          pkgs
          hyprlandPkg
          profileRegistry
          profileHomes
          homeConfigurations
          ;
        inherit (settings) username;
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
          nil
          nixd
          nixfmt
          python3
          statix
        ];
      };

      checks.${settings.system} = checks;

      packages.${settings.system} = {
        dangonix = dangonix.package;
        campaign-tui = repoApps.scripts.campaignTui;
        # Not in checks: boots two VMs (`nix build .#greeter-vm`).
        greeter-vm = import ./tests/greeter-vm { inherit pkgs; };
        # Not in checks: boots a VM and builds a host and a home in it
        # (`dangonix check --vm`).
        dangonix-vm = import ./tests/dangonix-vm {
          inherit pkgs;
          inherit (inputs) nixpkgs home-manager;
        };
      };

      apps.${settings.system} = {
        default = {
          type = "app";
          program = "${dangonix.package}/bin/dangonix";
          meta.description = "dangonix, the one CLI of dangoNix";
        };
      };
    };
}
