{
  description = "kitOS v0.1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";

    foundryvtt = {
      url = "github:nix-foundryvtt/nix-foundryvtt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
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
      constants = import ./lib/constants.nix { inherit system username; };
      pkgs = import nixpkgs { inherit system; };
      pkgsUnstable = import inputs.nixpkgs-unstable { inherit system; };
      hyprlandPkg = inputs.hyprland.packages.${system}.hyprland;
      repoApps = import ./lib/repo-apps.nix { inherit constants hyprlandPkg pkgs; };
    in
    {
      nixosConfigurations.${constants.hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            inputs
            self
            constants
            pkgsUnstable
            ;
        };

        modules = [
          ./hosts/nixos/configuration.nix

          home-manager.nixosModules.default
          inputs.thyx.nixosModules.default

          {
            home-manager = {
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = {
                inherit
                  inputs
                  self
                  constants
                  pkgsUnstable
                  ;
              };

              users.${constants.username} = import ./home/kit.nix;
              sharedModules = [ inputs.stylix.homeModules.stylix ];
            };
          }
        ];
      };

      formatter.${system} = repoApps.scripts.fmt;

      devShells.${system}.default = pkgs.mkShell {
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

      checks.${system}.static =
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

      apps.${system} = repoApps.apps;
    };
}
