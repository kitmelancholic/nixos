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
      themeCheckScript = pkgs.writeShellApplication {
        name = "repo-theme-check";
        runtimeInputs = with pkgs; [
          jq
          nix
        ];
        text = ''
          # shellcheck disable=SC2016
          report="$(
            nix eval --impure --json --expr '
              let
                themeSet = import ./themes;
                requiredBase16Keys = [
                  "base00" "base01" "base02" "base03"
                  "base04" "base05" "base06" "base07"
                  "base08" "base09" "base0A" "base0B"
                  "base0C" "base0D" "base0E" "base0F"
                ];
                names = builtins.attrNames themeSet.themes;
              in
              {
                selected = themeSet.selected;
                validSelected = builtins.hasAttr themeSet.selected themeSet.themes;
                missingWallpapers = builtins.filter (
                  name: !(builtins.pathExists themeSet.themes.''${name}.wallpaper)
                ) names;
                missingBase16 = builtins.mapAttrs (
                  _: theme:
                  builtins.filter (
                    key: !(builtins.hasAttr key theme.base16Scheme)
                  ) requiredBase16Keys
                ) themeSet.themes;
              }
            '
          )"

          if ! printf '%s\n' "$report" | jq -e '
            .validSelected == true
            and (.missingWallpapers | length == 0)
            and ([.missingBase16[] | length] | all(. == 0))
          ' >/dev/null; then
            printf '%s\n' "$report" | jq .
            exit 1
          fi

          printf '%s\n' "themes ok"
        '';
      };
      hyprlandCheckScript = pkgs.writeShellApplication {
        name = "repo-hyprland-check";
        runtimeInputs = with pkgs; [
          coreutils
          jq
          lua5_4
          nix
          hyprlandPkg
        ];
        text = ''
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT
          config="$tmpdir/hyprland.lua"

          nix eval .#nixosConfigurations.${constants.hostname}.config.home-manager.users.${constants.username}.xdg.configFile --json --no-write-lock-file \
            | jq -r '."hypr/hyprland.lua".text' > "$config"

          luac -p "$config"
          Hyprland --verify-config --config "$config"
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
          ${themeCheckScript}/bin/repo-theme-check
          ${hyprlandCheckScript}/bin/repo-hyprland-check
        '';
      };
      switchScript = pkgs.writeShellApplication {
        name = "repo-switch";
        runtimeInputs = with pkgs; [
          nixos-rebuild
          sudo
        ];
        text = ''
          exec sudo nixos-rebuild switch --flake .#${constants.hostname} "$@"
        '';
      };
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
          meta.description = "Run repository static checks and Hyprland config validation";
        };
        fmt = {
          type = "app";
          program = "${fmtScript}/bin/repo-fmt";
          meta.description = "Format repository files";
        };
        hyprland-check = {
          type = "app";
          program = "${hyprlandCheckScript}/bin/repo-hyprland-check";
          meta.description = "Validate the generated Hyprland Lua config";
        };
        theme-check = {
          type = "app";
          program = "${themeCheckScript}/bin/repo-theme-check";
          meta.description = "Validate theme selection, wallpapers, and base16 schemes";
        };
        switch = {
          type = "app";
          program = "${switchScript}/bin/repo-switch";
          meta.description = "Rebuild and switch the NixOS host configuration";
        };
      };
    };
}
