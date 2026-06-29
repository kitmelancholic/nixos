let
  selected = import ./selected.nix;
  themes = import ./themes.nix;
in
{
  inherit selected;
  inherit themes;
  active =
    if builtins.hasAttr selected themes then
      themes.${selected}
    else
      throw "Unknown theme '${selected}' in themes/selected.nix";
}
