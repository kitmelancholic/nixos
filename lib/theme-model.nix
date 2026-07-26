{ lib, settings }:

let
  registry = import ../themes;
  ids = builtins.sort builtins.lessThan (builtins.attrNames registry.profiles);
  inherit (registry) default;
  profilePrefix = "${settings.username}-";
in
assert builtins.elem default ids;
{
  inherit registry ids default;

  moduleFor =
    themeId:
    assert builtins.elem themeId ids;
    registry.profiles.${themeId};

  profileName =
    themeId:
    assert builtins.elem themeId ids;
    if lib.hasPrefix profilePrefix themeId then themeId else "${profilePrefix}${themeId}";
}
