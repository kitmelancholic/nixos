# dangonix (docs/design.md §5): one writeShellApplication over dangonix.sh.
# Nix injects the config (host, user, default checkout, held inputs, Foundry
# version table) and the command table as one JSON file.
{
  lib,
  pkgs,
  settings,
  foundryTable,
  # theme ids, for completions
  themes,
  # the checkout dangonix works on outside one (`dangonix.repo`)
  repo,
}:

let
  effects = [
    "read"
    "runtime"
    "state"
    "host"
  ];
  checkRow =
    row:
    assert lib.assertMsg (lib.elem row.effect effects)
      "dangonix: ${row.id}: unknown effect ${row.effect}";
    assert lib.assertMsg (
      row.agent == "ask" || row.effect == "read"
    ) "dangonix: ${row.id}: only read commands may be agent = allow";
    row;
  rows = import ./commands.nix;
  commands =
    assert lib.assertMsg (lib.allUnique (map (row: row.id) rows)) "dangonix: duplicate command ids";
    map checkRow rows;

  # The releases of nix-foundryvtt's version table (entries with a hash), with
  # the version string and ZIP name its package derives from each key
  # (`14.361` -> `14.0.0+361`), and the store path `nix-store --add-fixed`
  # gives the ZIP (the transaction preflight looks for it).
  foundryVersions = lib.mapAttrs (
    key: entry:
    let
      parts = lib.splitString "." key;
      platform = lib.optionalString (lib.versionAtLeast key "13.338") "-${entry.platform or "Linux"}";
      file = "FoundryVTT${platform}-${key}.zip";
    in
    {
      inherit (entry) hash;
      inherit file;
      version = "${lib.head parts}.0.0+${lib.last parts}";
      path =
        builtins.unsafeDiscardStringContext
          (pkgs.requireFile {
            name = file;
            inherit (entry) hash;
            message = "dangonix foundry import ${file}";
          }).outPath;
    }
  ) (lib.filterAttrs (_: entry: entry ? hash) foundryTable);

  config = pkgs.writeText "dangonix-config.json" (
    builtins.toJSON {
      inherit repo commands;
      inherit (settings) system hostname username;
      # `update` skips these unless named (design §6).
      held = [
        "hyprland"
        "noctalia"
        "caelestia"
      ];
      foundry = {
        # One service until several instances arrive in campaign II.
        inherit (settings.foundry) service;
        versions = foundryVersions;
      };
    }
  );

  package = pkgs.writeShellApplication {
    name = "dangonix";
    runtimeInputs = with pkgs; [
      coreutils
      dconf
      fwupd
      git
      gnugrep
      jq
      nix
      nvd
      procps
      systemd
      util-linux
      xdg-utils
    ];
    # `$` in single quotes is jq code.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      DANGONIX_CONFIG=${config}
    ''
    + builtins.readFile ./dangonix.sh;
  };

  completions = pkgs.writeTextFile {
    name = "dangonix.fish";
    text = import ./completions.nix {
      inherit
        lib
        commands
        themes
        repo
        ;
      jq = lib.getExe pkgs.jq;
    };
    checkPhase = "${lib.getExe pkgs.fish} --no-execute $target";
  };
in
{
  inherit package completions commands;
}
