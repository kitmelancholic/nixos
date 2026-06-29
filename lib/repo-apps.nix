{
  constants,
  hyprlandPkg,
  pkgs,
}:

let
  inherit (constants) foundry;

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

  foundryCheckScript = pkgs.writeShellApplication {
    name = "repo-foundry-check";
    runtimeInputs = with pkgs; [
      coreutils
      nix
    ];
    text = ''
            expected_version='${foundry.version}'
            expected_file='${foundry.filename}'
            expected_hash='${foundry.hash}'

            actual_version="$(
              nix eval .#nixosConfigurations.${constants.hostname}.config.services.foundryvtt.package.version --raw --no-write-lock-file
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
    runtimeInputs = with pkgs; [
      deadnix
      nix
      nixfmt-tree
      statix
    ];
    text = ''
      ${staticCheckCommand}
      nix flake show --no-write-lock-file
      ${themeCheckScript}/bin/repo-theme-check
      ${hyprlandCheckScript}/bin/repo-hyprland-check
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "repo-switch";
    text = ''
      exec /run/wrappers/bin/sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#${constants.hostname} "$@"
    '';
  };

  scripts = {
    check = checkScript;
    fmt = fmtScript;
    foundryCheck = foundryCheckScript;
    hyprlandCheck = hyprlandCheckScript;
    switch = switchScript;
    themeCheck = themeCheckScript;
  };
in

{
  inherit scripts staticCheckCommand;

  apps = {
    check = mkApp "Run repository static checks and Hyprland config validation" "${checkScript}/bin/repo-check";
    fmt = mkApp "Format repository files" "${fmtScript}/bin/repo-fmt";
    foundry-check = mkApp "Validate the configured FoundryVTT payload" "${foundryCheckScript}/bin/repo-foundry-check";
    hyprland-check = mkApp "Validate the generated Hyprland Lua config" "${hyprlandCheckScript}/bin/repo-hyprland-check";
    theme-check = mkApp "Validate theme selection, wallpapers, and base16 schemes" "${themeCheckScript}/bin/repo-theme-check";
    switch = mkApp "Rebuild and switch the NixOS host configuration" "${switchScript}/bin/repo-switch";
  };
}
