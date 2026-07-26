{
  home-manager,
  homePkgs,
  inputs,
  settings,
  pkgsUnstable,
  homeManagerPackage,
  hyprlandPkg,
  themeFlakeSource,
  themeModel,
}:

themeId:
assert builtins.elem themeId themeModel.ids;
home-manager.lib.homeManagerConfiguration {
  pkgs = homePkgs;
  modules = [
    inputs.stylix.homeModules.stylix
    ../home/kit.nix
    (themeModel.moduleFor themeId)
    {
      kit.theme.id = themeId;
    }
  ];
  extraSpecialArgs = {
    inherit
      inputs
      settings
      pkgsUnstable
      homeManagerPackage
      hyprlandPkg
      themeModel
      ;
    inherit themeFlakeSource;
  };
}
