{
  description = "kitOS v0.1";

  nixConfig = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";

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
      constants = {
        inherit system username;
        hostname = "nixos";
        homeDirectory = "/home/${username}";

        apps = {
          browser = {
            command = "vivaldi";
            desktop = "vivaldi-stable.desktop";
          };
          terminal.command = "ghostty";
          explorer.command = "ghostty -e nnn -Q";
          launcher.command = "wofi --show drun";
          fileManager.desktop = "org.gnome.Nautilus.desktop";
          imageViewer.desktop = "org.gnome.Loupe.desktop";
          mediaPlayer.desktop = "mpv.desktop";
          pdfViewer.desktop = "org.gnome.Evince.desktop";
          textEditor.desktop = "dev.zed.Zed.desktop";
          archiveManager.desktop = "org.gnome.FileRoller.desktop";
        };
      };
      pkgs = import nixpkgs { inherit system; };
      fmtScript = pkgs.writeShellApplication {
        name = "repo-fmt";
        runtimeInputs = [ pkgs.nixfmt-tree ];
        text = ''
          if [ "$#" -eq 0 ]; then
            exec treefmt --tree-root "$PWD" --excludes hosts/nixos/hardware-configuration.nix .
          fi
          exec treefmt --tree-root "$PWD" "$@"
        '';
      };
      checkScript = pkgs.writeShellApplication {
        name = "repo-check";
        runtimeInputs = with pkgs; [
          deadnix
          statix
          nix
          nixfmt-tree
        ];
        text = ''
          treefmt --tree-root "$PWD" --ci --excludes hosts/nixos/hardware-configuration.nix .
          statix check --ignore hosts/nixos/hardware-configuration.nix
          deadnix --fail --exclude hosts/nixos/hardware-configuration.nix .
          nix flake show --no-write-lock-file
        '';
      };
    in
    {
      nixosConfigurations.${constants.hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs self constants; };

        modules = [
          ./hosts/nixos/configuration.nix

          home-manager.nixosModules.default
          inputs.thyx.nixosModules.default

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = { inherit inputs self constants; };

              users.${constants.username} = import ./home/kit.nix;
              sharedModules = [ inputs.stylix.homeModules.stylix ];
            };
          }
        ];
      };

      formatter.${system} = fmtScript;

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
            treefmt --tree-root "$PWD" --ci --excludes hosts/nixos/hardware-configuration.nix .
            statix check --ignore hosts/nixos/hardware-configuration.nix
            deadnix --fail --exclude hosts/nixos/hardware-configuration.nix .
            touch $out
          '';

      apps.${system} = {
        check = {
          type = "app";
          program = "${checkScript}/bin/repo-check";
        };
        fmt = {
          type = "app";
          program = "${fmtScript}/bin/repo-fmt";
        };
      };
    };
}
