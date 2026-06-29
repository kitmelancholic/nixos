{ lib }:

let
  lua = lib.generators.mkLuaInline;
  mkArgs = args: { _args = args; };
in
rec {
  inherit lua;

  mkEnv =
    name: value:
    mkArgs [
      name
      value
    ];

  mkBind =
    key: action:
    mkArgs [
      key
      (lua action)
    ];

  mkBindWithFlags =
    key: action: flags:
    mkArgs [
      key
      (lua action)
      flags
    ];

  mkModBind = key: action: mkBind (lua ''mod .. " + ${key}"'') action;
  mkShiftModBind = key: action: mkBind (lua ''mod .. " + SHIFT + ${key}"'') action;
}
