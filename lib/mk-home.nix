{
  home-manager,
  homePkgs,
  inputs,
  settings,
  pkgsUnstable,
  homeManagerPackage,
  hyprlandPkg,
  profileRegistry,
}:

profileId:
assert builtins.elem profileId (builtins.attrNames profileRegistry.themes);
home-manager.lib.homeManagerConfiguration {
  pkgs = homePkgs;
  modules = [
    ../home/kit.nix
    profileRegistry.themes.${profileId}.module
    {
      dangonix.theme.id = profileId;
    }
  ];
  extraSpecialArgs = {
    inherit
      inputs
      settings
      pkgsUnstable
      homeManagerPackage
      hyprlandPkg
      profileRegistry
      ;
  };
}
