{
  lib,
  pkgs,
  src,
  staticCheckCommand,
  hyprlandPkg,
  profileRegistry,
  profileHomes,
  host,
}:

let
  inherit (profileRegistry) profiles;
  profileIds = builtins.sort builtins.lessThan (builtins.attrNames profiles);

  duplicates = xs: lib.unique (lib.filter (x: lib.count (y: y == x) xs > 1) xs);

  registryProblems = lib.concatLists (
    [
      (lib.optional (
        !builtins.elem profileRegistry.default profileIds
      ) "state.json theme ${profileRegistry.default} is not in the registry")
      (map (name: "duplicate name ${name}") (duplicates (map (id: profiles.${id}.name) profileIds)))
      (map (module: "duplicate module ${module}") (
        duplicates (map (id: toString profiles.${id}.module) profileIds)
      ))
      (map (id: "duplicate kit.profile.id ${id}") (
        duplicates (map (id: profileHomes.${id}.config.kit.profile.id) profileIds)
      ))
    ]
    ++ map (
      id:
      let
        entry = profiles.${id};
        isText = value: builtins.isString value && value != "";
      in
      lib.optional (builtins.match "[a-z0-9][a-z0-9-]*" id == null) "${id}: invalid id"
      ++ lib.optional (
        builtins.attrNames entry != [
          "description"
          "module"
          "name"
        ]
      ) "${id}: manifest fields must be exactly name, description, module"
      ++ lib.optional (!isText (entry.name or null)) "${id}: name must be a non-empty string"
      ++ lib.optional (
        !isText (entry.description or null)
      ) "${id}: description must be a non-empty string"
      ++ lib.optional (
        !(entry ? module && builtins.pathExists entry.module)
      ) "${id}: module path does not exist"
      ++
        lib.optional (profileHomes.${id}.config.kit.profile.id != id)
          "${id}: kit.profile.id is ${profileHomes.${id}.config.kit.profile.id}"
    ) profileIds
  );

  registry =
    assert lib.assertMsg (
      registryProblems == [ ]
    ) "registry: ${lib.concatStringsSep "; " registryProblems}";
    pkgs.runCommand "registry-check" { } "touch $out";

  # A bind key is `mod .. " + X"` (Lua inline) or a plain string; the
  # resolved form puts modifiers in a fixed order joined by " + ".
  modifierOrder = [
    "SUPER"
    "CTRL"
    "ALT"
    "SHIFT"
  ];

  luaText =
    value:
    if builtins.isString value then
      value
    else if (value._type or null) == "lua-inline" then
      value.expr
    else
      throw "bind: unsupported value ${builtins.toJSON value}";

  resolveKey =
    arg:
    let
      matched = builtins.match ''mod \.\. "(.*)"'' (luaText arg);
      text = if builtins.isString arg then arg else "mod${builtins.head matched}";
      parts = lib.splitString " + " text;
      modifierRank =
        modifier:
        let
          name = if modifier == "mod" then "SUPER" else lib.toUpper modifier;
          rank = lib.lists.findFirstIndex (known: known == name) null modifierOrder;
        in
        if rank == null then
          throw "bind: unknown modifier ${modifier} in ${text}"
        else
          { inherit name rank; };
      modifiers = lib.sort (a: b: a.rank < b.rank) (map modifierRank (lib.init parts));
    in
    assert builtins.isString arg || matched != null;
    lib.concatStringsSep " + " (map (modifier: modifier.name) modifiers ++ [ (lib.last parts) ]);

  resolveBind =
    bind:
    let
      args = bind._args;
    in
    {
      key = resolveKey (builtins.elemAt args 0);
      action = luaText (builtins.elemAt args 1);
      flags = if builtins.length args > 2 then builtins.elemAt args 2 else { };
    };

  resolvedBinds = lib.genAttrs profileIds (
    id: map resolveBind (profileHomes.${id}.config.wayland.windowManager.hyprland.settings.bind or [ ])
  );

  bindsFixture =
    pkgs.runCommand "binds-fixture-check"
      {
        nativeBuildInputs = [
          pkgs.diffutils
          pkgs.jq
        ];
        # Readable with `nix eval --raw .#checks.<system>.binds-fixture.bindsJson`.
        bindsJson = builtins.toJSON resolvedBinds;
      }
      ''
        ${lib.concatMapStringsSep "\n" (id: ''
          jq -S . ${../tests/binds + "/${id}.json"} > fixture-${id}.json
          jq -S . ${
            pkgs.writeText "binds-${id}.json" (builtins.toJSON resolvedBinds.${id})
          } > resolved-${id}.json
          diff -u fixture-${id}.json resolved-${id}.json
        '') profileIds}
        touch $out
      '';

  hyprlandCheck =
    id:
    let
      hyprlandLua = profileHomes.${id}.config.xdg.configFile."hypr/hyprland.lua".text;
    in
    pkgs.runCommand "hyprland-check-${id}"
      {
        nativeBuildInputs = [
          pkgs.lua5_4
          hyprlandPkg
        ];
      }
      ''
        export XDG_RUNTIME_DIR="$TMPDIR/runtime"
        mkdir -p "$XDG_RUNTIME_DIR"
        config="$TMPDIR/hyprland.lua"
        cat ${pkgs.writeText "hyprland.lua" hyprlandLua} > "$config"
        luac -p "$config"
        Hyprland --verify-config --config "$config"
        touch "$out"
      '';
in
{
  static =
    pkgs.runCommand "static-checks"
      {
        nativeBuildInputs = with pkgs; [
          deadnix
          nixfmt-tree
          statix
        ];
      }
      ''
        cp -r --no-preserve=mode ${src} repo
        cd repo
        ${staticCheckCommand}
        touch $out
      '';
  inherit registry;
  binds-fixture = bindsFixture;
  host = host.config.system.build.toplevel;
}
// lib.mergeAttrsList (
  map (id: {
    "home-${id}" = profileHomes.${id}.activationPackage;
    "hyprland-${id}" = hyprlandCheck id;
  }) profileIds
)
