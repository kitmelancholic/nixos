{
  home-manager,
  homePkgs,
  inputs,
  settings,
  pkgsUnstable,
  homeManagerPackage,
  hyprlandPkg,
  profileFlakeSource,
  profileRegistry,
}:

profileId:
assert builtins.elem profileId (builtins.attrNames profileRegistry.profiles);
home-manager.lib.homeManagerConfiguration {
  pkgs = homePkgs;
  modules = [
    inputs.stylix.homeModules.stylix
    ../home/kit.nix
    profileRegistry.profiles.${profileId}.module
    {
      kit.profile.id = profileId;
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
    inherit profileFlakeSource;
  };
}
