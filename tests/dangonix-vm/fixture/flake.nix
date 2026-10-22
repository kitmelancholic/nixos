# The fixture of the dangonix VM test (tests/dangonix-vm): a tiny host and
# home on the same nixpkgs, with the outputs dangonix looks at in the real
# flake (nixosConfigurations.<host>, homeConfigurations.kit-<theme>,
# lib.themes). variant.json says what this checkout breaks on purpose; the
# test rewrites it between commands. machine-hardware.nix is generated in the
# VM.
{
  description = "dangonix VM test fixture";

  inputs = {
    nixpkgs.url = "nixpkgs";
    home-manager.url = "home-manager";
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      variant = lib.importJSON ./variant.json;

      themes = {
        alpha = "the first fixture theme";
        beta = "the second fixture theme";
      };

      host = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
          "${nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
          ./machine-hardware.nix
          (import ./common.nix { inherit inputs; })
          {
            environment.etc = lib.mkIf (variant.hostEtc != null) {
              "dangonix-test".text = variant.hostEtc;
            };
            system.activationScripts = lib.mkIf variant.hostFail {
              dangonixFail = "exit 1";
            };
          }
        ];
      };

      home =
        theme:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            (
              { lib, ... }:
              {
                home = {
                  username = "kit";
                  homeDirectory = "/home/kit";
                  stateVersion = "26.05";
                };
                # The manual's sources are not in the offline image.
                manual = {
                  manpages.enable = false;
                  html.enable = false;
                  json.enable = false;
                };
                # sd-switch is built from sources the offline image lacks.
                systemd.user.startServices = false;
                xdg.configFile = {
                  "dangonix-theme".text = theme;
                }
                // lib.optionalAttrs variant.homeFile { "dangonix-test".text = "1"; }
                // lib.optionalAttrs variant.slowBuild {
                  "dangonix-slow".source = pkgs.runCommand "dangonix-slow" { } ''
                    sleep 40
                    echo slow > $out
                  '';
                };
                home.activation = {
                  # After linkGeneration the new files are in place.
                  dangonixFail = lib.mkIf variant.homeFail (lib.hm.dag.entryAfter [ "linkGeneration" ] "exit 1");
                  # What stops a unit the transaction was started from.
                  stopVictim = lib.mkIf variant.stopVictim (
                    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
                      ${pkgs.systemd}/bin/systemctl --user is-active victim.service > $HOME/victim-state || true
                      ${pkgs.systemd}/bin/systemctl --user stop victim.service || true
                    ''
                  );
                };
              }
            )
          ];
        };
    in
    {
      nixosConfigurations.machine = host;
      homeConfigurations = lib.mapAttrs' (theme: _: lib.nameValuePair "kit-${theme}" (home theme)) themes;
      lib.themes.profiles = lib.mapAttrs (theme: description: {
        name = theme;
        inherit description;
      }) themes;
    };
}
