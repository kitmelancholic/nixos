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

  # Design check 7: the command table of dangonix, and the agents' rules for
  # it fixed by its grammar (every command takes --dry; read rows ignore it).
  commandRows = import ./dangonix/commands.nix;
  scriptLines = lib.splitString "\n" (builtins.readFile ./dangonix/dangonix.sh);

  # The lines of `<name>() {` .. `}` in dangonix.sh, or null.
  functionBody =
    name:
    let
      start = lib.lists.findFirstIndex (line: line == "${name}() {") null scriptLines;
      rest = lib.drop (start + 1) scriptLines;
    in
    if start == null then
      null
    else
      lib.take (lib.lists.findFirstIndex (line: line == "}") (builtins.length rest) rest) rest;
  rowFunction = row: "cmd_${lib.replaceStrings [ "-" ] [ "_" ] row.id}";
  callsPlanned = lib.any (line: builtins.match "[[:space:]]*planned( .*)?" line != null);
  # A non-read command implements --dry: its function, or a cmd_ function it
  # calls, stops at `planned` (which prints the plan under --dry).
  implementsDry =
    body:
    callsPlanned body
    ||
      lib.any
        (
          callee:
          let
            calleeBody = functionBody callee;
          in
          calleeBody != null && callsPlanned calleeBody
        )
        (
          lib.concatMap (
            line: lib.flatten (builtins.filter builtins.isList (builtins.split "(cmd_[a-z_]+)" line))
          ) body
        );

  claudePermissions = (lib.importJSON "${src}/.claude/settings.json").permissions or { };
  claudeDangonix =
    lib.concatMap
      (
        kind:
        map (rule: "${kind} ${rule}") (
          lib.filter (lib.hasPrefix "Bash(dangonix") (claudePermissions.${kind} or [ ])
        )
      )
      (
        lib.filter (kind: builtins.isList claudePermissions.${kind}) (builtins.attrNames claudePermissions)
      );
  # Every prefix_rule(..) of the Codex rules without comments, whitespace or
  # quote style, so a rule split over lines reads as one on a line.
  codexRules =
    let
      code = lib.concatMapStrings (line: lib.head (lib.splitString "#" line)) (
        lib.splitString "\n" (builtins.readFile "${src}/.codex/rules/dangonix.rules")
      );
    in
    map (rule: "prefix_rule(${rule}") (
      lib.tail (
        lib.splitString "prefix_rule(" (lib.replaceStrings [ " " "\t" "\r" "'" ] [ "" "" "" "\"" ] code)
      )
    );
  codexDangonix = lib.filter (
    rule: builtins.match ''.*pattern=\["dangonix".*'' rule != null
  ) codexRules;
  sorted = builtins.sort builtins.lessThan;
  # Every command an agent must not run for real: the settings ask for each.
  askNames = lib.unique (map (row: row.name) (lib.filter (row: row.agent == "ask") commandRows));

  commandProblems =
    lib.concatMap (
      row:
      let
        body = functionBody (rowFunction row);
      in
      lib.optional (!(row ? effect && row ? agent)) "${row.id}: needs effect and agent"
      ++ lib.optional (
        row ? agent
        && !(lib.elem row.agent [
          "allow"
          "ask"
        ])
      ) "${row.id}: agent is allow or ask"
      ++ lib.optional (
        (row.agent or null) == "allow" && (row.effect or null) != "read"
      ) "${row.id}: agent = allow only for read commands"
      ++ lib.optional (body == null) "${row.id}: dangonix.sh has no ${rowFunction row}"
      ++ lib.optional (
        body != null && (row.effect or null) != "read" && !implementsDry body
      ) "${row.id}: ${rowFunction row} does not implement --dry (it never calls planned)"
    ) commandRows
    ++
      lib.optional
        (
          sorted claudeDangonix != sorted (
            [
              "allow Bash(dangonix --dry *)"
              "allow Bash(dangonix check *)"
              "allow Bash(dangonix check)"
            ]
            ++ map (name: "ask Bash(dangonix ${name}*)") askNames
          )
        )
        ".claude/settings.json: the dangonix rules must be exactly the allow rules for `dangonix --dry *` and `dangonix check [*]` and an ask rule `dangonix <name>*` for each command with agent = ask, found: ${builtins.toJSON claudeDangonix}"
    ++
      lib.optional
        (
          sorted codexDangonix != sorted (
            [
              ''prefix_rule(pattern=["dangonix","--dry"],decision="allow")''
              ''prefix_rule(pattern=["dangonix","check"],decision="allow")''
            ]
            ++ map (
              name:
              ''prefix_rule(pattern=${
                builtins.toJSON ([ "dangonix" ] ++ lib.splitString " " name)
              },decision="prompt")''
            ) askNames
          )
        )
        ".codex/rules/dangonix.rules: the dangonix rules must be exactly the allow rules for `dangonix --dry` and `dangonix check` and a prompt rule for each command with agent = ask, found: ${builtins.toJSON codexDangonix}";

  commands =
    assert lib.assertMsg (
      commandProblems == [ ]
    ) "commands: ${lib.concatStringsSep "; " commandProblems}";
    pkgs.runCommand "commands-check" { } "touch $out";

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
  # scripts/trace on recorded Claude Code and Codex logs gives the expected lines.
  trace = pkgs.runCommand "trace-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
    for f in claude codex; do
      jq -rs --arg mode trace -f ${src}/scripts/trace.jq ${src}/tests/trace/$f.jsonl > $f.out
      diff -u ${src}/tests/trace/$f.expected $f.out
    done
    touch $out
  '';
  inherit registry commands;
  binds-fixture = bindsFixture;
  host = host.config.system.build.toplevel;
}
// lib.mergeAttrsList (
  map (id: {
    "home-${id}" = profileHomes.${id}.activationPackage;
    "hyprland-${id}" = hyprlandCheck id;
  }) profileIds
)
