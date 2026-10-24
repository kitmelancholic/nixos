{
  config,
  lib,
  pkgs,
  settings,
  inputs,
  profileRegistry,
  ...
}:

let
  dangonix = import ../lib/dangonix {
    inherit lib pkgs settings;
    foundryTable = lib.importJSON "${inputs.foundryvtt}/pkgs/foundryvtt/versions.json";
    themes = builtins.attrNames profileRegistry.themes;
    inherit (config.dangonix) repo;
  };
in
{
  imports = [ ../themes/contract.nix ];

  home.packages = [ dangonix.package ];
  xdg.configFile = {
    "fish/completions/dangonix.fish".source = dangonix.completions;
    # What `dangonix doctor` checks the running session against.
    "dangonix/roles.json".text = builtins.toJSON {
      theme = config.dangonix.theme.id;
      inherit (profileRegistry.themes.${config.dangonix.theme.id}) status;
      appearance = config.dangonix.look.appearance;
      missing = config.dangonix.rolesMissing;
      roles = lib.filterAttrsRecursive (_: value: value != null) config.dangonix.roles;
    };
  };
}
