{
  lib,
  settings,
  pkgs,
  foundryTable,
  homeManagerPackage,
  profileRegistry,
}:

let
  inherit (settings) foundry;

  # The table key is the short version (`14.0.0+361` -> `14.361`); the payload
  # name is built the way nix-foundryvtt builds it.
  foundryKey = "${lib.head (lib.splitString "." foundry.version)}.${lib.last (lib.splitString "+" foundry.version)}";
  foundryEntry =
    foundryTable.${foundryKey}
      or (throw "Foundry version ${foundry.version} (table key ${foundryKey}) is not in nix-foundryvtt's version table");
  foundryFilename = "FoundryVTT-${foundryEntry.platform or "Linux"}-${foundryKey}.zip";

  staticCheckCommand = ''
    treefmt --tree-root "$PWD" --ci --excludes hosts/nixos/hardware-configuration.nix .
    statix check --ignore hosts/nixos/hardware-configuration.nix
    deadnix --fail --exclude hosts/nixos/hardware-configuration.nix .
  '';

  mkApp = description: program: {
    type = "app";
    inherit program;
    meta.description = description;
  };

  fmtScript = pkgs.writeShellApplication {
    name = "repo-fmt";
    runtimeInputs = [ pkgs.nixfmt-tree ];
    # The exclude holds with arguments too: `nix fmt -- --no-cache` must not
    # reformat the generated hardware file.
    text = ''
      [ "$#" -gt 0 ] || set -- .
      exec treefmt --tree-root "$PWD" --excludes hosts/nixos/hardware-configuration.nix "$@"
    '';
  };

  themeCheckScript = pkgs.writeShellApplication {
    name = "repo-theme-check";
    runtimeInputs = with pkgs; [
      nix
    ];
    text = ''
      exec nix build .#checks.${settings.system}.registry --no-link --no-write-lock-file
    '';
  };

  hyprlandCheckScript = pkgs.writeShellApplication {
    name = "repo-hyprland-check";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      exec nix build ${
        lib.concatMapStringsSep " " (profileId: ".#checks.${settings.system}.hyprland-${profileId}") (
          builtins.attrNames profileRegistry.profiles
        )
      } --no-link --no-write-lock-file
    '';
  };

  foundryCheckScript =
    if !foundry.enable then
      pkgs.writeShellApplication {
        name = "repo-foundry-check";
        text = "echo 'foundry disabled'";
      }
    else
      pkgs.writeShellApplication {
        name = "repo-foundry-check";
        runtimeInputs = with pkgs; [
          coreutils
          nix
        ];
        text = ''
                expected_version='${foundry.version}'
                expected_file='${foundryFilename}'
                expected_hash='${foundryEntry.hash}'

                actual_version="$(
                  nix eval .#nixosConfigurations.${settings.hostname}.config.services.foundryvtt.package.version --raw --no-write-lock-file
                )"

                if [ "$actual_version" != "$expected_version" ]; then
                  printf 'FoundryVTT version mismatch: expected %s, got %s\n' "$expected_version" "$actual_version" >&2
                  exit 1
                fi

                shopt -s nullglob
                matches=(/nix/store/*-"$expected_file")
                store_path=""

                for candidate in "''${matches[@]}"; do
                  if [ "$(nix hash file --type sha256 --sri "$candidate")" = "$expected_hash" ]; then
                    store_path="$candidate"
                    break
                  fi
                done

                if [ -z "$store_path" ]; then
                  cat >&2 <<EOF
          FoundryVTT payload is missing from /nix/store.

          Expected file: $expected_file
          Expected hash: $expected_hash

          Add it with:
            cd ~/FoundryVTT
            nix-store --add-fixed sha256 $expected_file
          EOF
                  exit 1
                fi

                roots="$(nix-store --query --roots "$store_path" || true)"
                if [ -z "$roots" ]; then
                  cat >&2 <<EOF
          FoundryVTT payload is in /nix/store but has no GC root:
            $store_path

          Protect it from garbage collection with:
            mkdir -p ~/FoundryVTT/gcroots
            nix-store --add-root ~/FoundryVTT/gcroots/$expected_file -r $store_path
          EOF
                  exit 1
                fi

                printf 'foundry ok: %s\n' "$actual_version"
                printf '%s\n' "$store_path"
        '';
      };

  checkScript = pkgs.writeShellApplication {
    name = "repo-check";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      exec nix flake check --no-write-lock-file
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "repo-switch";
    text = ''
      exec /run/wrappers/bin/sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#${settings.hostname} "$@"
    '';
  };

  homeSwitchScript = pkgs.writeShellApplication {
    name = "repo-home-switch";
    runtimeInputs = [
      homeManagerPackage
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
            identity_file="''${XDG_CONFIG_HOME:-$HOME/.config}/kit/profile-id"
            profile="${settings.username}"

            if [ -e "$identity_file" ]; then
              profile_id="$(<"$identity_file")"
              case "$profile_id" in
      ${
        lib.concatMapStringsSep "\n" (
          profileId: "          ${profileId}) profile=${settings.username}-${profileId} ;;\n"
        ) (builtins.attrNames profileRegistry.profiles)
      }          *)
                  echo "home-switch: invalid generated profile identity in $identity_file" >&2
                  exit 1
                  ;;
              esac
            fi

      if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
        lock_file="$XDG_RUNTIME_DIR/kit-home-activation.lock"
      else
        activation_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/kit"
        umask 077
        mkdir -p "$activation_state_dir"
        chmod 700 "$activation_state_dir"
        lock_file="$activation_state_dir/home-activation.lock"
      fi

      exec 9>"$lock_file"
      if ! flock -n 9; then
        echo "home-switch: another managed Home Manager activation is already running" >&2
        exit 1
      fi
      exec home-manager switch --flake ".#$profile" "$@"
    '';
  };

  scripts = {
    check = checkScript;
    fmt = fmtScript;
    foundryCheck = foundryCheckScript;
    hyprlandCheck = hyprlandCheckScript;
    switch = switchScript;
    themeCheck = themeCheckScript;
    homeSwitch = homeSwitchScript;
  };
in

{
  inherit scripts staticCheckCommand;

  apps = {
    check = mkApp "Run repository static checks and Hyprland config validation" "${checkScript}/bin/repo-check";
    fmt = mkApp "Format repository files" "${fmtScript}/bin/repo-fmt";
    foundry-check = mkApp "Validate the configured FoundryVTT payload" "${foundryCheckScript}/bin/repo-foundry-check";
    hyprland-check = mkApp "Validate the generated Hyprland Lua config" "${hyprlandCheckScript}/bin/repo-hyprland-check";
    theme-check = mkApp "Validate the theme profile registry" "${themeCheckScript}/bin/repo-theme-check";
    switch = mkApp "Rebuild and switch the NixOS host configuration" "${switchScript}/bin/repo-switch";
    home-switch = mkApp "Activate the standalone Home Manager configuration" "${homeSwitchScript}/bin/repo-home-switch";
  };
}
