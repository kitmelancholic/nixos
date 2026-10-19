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
    themes = builtins.attrNames profileRegistry.profiles;
    inherit (config.kit) repo;
  };
in
{
  home.packages = [ dangonix.package ];
  xdg.configFile."fish/completions/dangonix.fish".source = dangonix.completions;
}
