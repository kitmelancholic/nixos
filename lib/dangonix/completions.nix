# Fish completions for dangonix, generated from the command table.
{
  lib,
  commands,
  themes,
  repo,
  jq,
}:

let
  quote = s: "'${lib.replaceStrings [ "\\" "'" ] [ "\\\\" "\\'" ] s}'";
  words = row: lib.splitString " " row.name;
  nouns = lib.unique (map (row: lib.head (words row)) commands);
  verbsOf =
    noun:
    lib.unique (
      lib.concatMap (
        row:
        let
          w = words row;
        in
        lib.optional (lib.head w == noun && lib.length w > 1) (lib.elemAt w 1)
      ) commands
    );
  rowOf = name: lib.findFirst (row: row.name == name) null commands;

  complete = condition: rest: "complete -c dangonix -n ${quote condition} ${rest}";
  # True once every word of the row has been typed.
  seen = row: lib.concatMapStringsSep "; and " (w: "__fish_seen_subcommand_from ${w}") (words row);

  globals = [
    {
      flag = "json";
      summary = "one JSON result on stdout, logs on stderr";
    }
    {
      flag = "dry";
      summary = "say what a non-read command would do, change nothing";
    }
    {
      flag = "yes";
      summary = "confirm an irreversible step without a TTY";
    }
    {
      flag = "metered-ok";
      summary = "allow downloads on a metered connection";
    }
  ];

  values = {
    themes = "-a ${quote (lib.concatStringsSep " " themes)}";
    instances = "-a ${quote "(${jq} -r '.foundry.instances | keys[]' ${repo}/state.json 2>/dev/null)"}";
    inputs = "-a ${quote "(${jq} -r '.nodes.root.inputs | keys[]' ${repo}/flake.lock 2>/dev/null)"}";
    excludes = "-a ${quote "(${jq} -r '.nodes.root.inputs | keys[] | \"-\" + .' ${repo}/flake.lock 2>/dev/null)"}";
    commands = "-a ${quote (lib.concatStringsSep " " nouns)}";
    files = "-F";
  };

  flagOption =
    flag:
    if lib.hasPrefix "--" flag then
      "-l ${lib.removePrefix "--" flag}"
    else
      "-s ${lib.removePrefix "-" flag}";

  nounLine =
    noun:
    let
      verbs = verbsOf noun;
      summary = if verbs == [ ] then (rowOf noun).summary else lib.concatStringsSep ", " verbs;
    in
    complete "__fish_use_subcommand" "-a ${noun} -d ${quote summary}";

  verbLines =
    noun:
    let
      verbs = verbsOf noun;
      condition = "__fish_seen_subcommand_from ${noun}; and not __fish_seen_subcommand_from ${lib.concatStringsSep " " verbs}";
    in
    map (verb: complete condition "-a ${verb} -d ${quote (rowOf "${noun} ${verb}").summary}") verbs;

  rowLines =
    row:
    map (flag: complete (seen row) (flagOption flag)) row.flags
    ++ map (kind: complete (seen row) values.${kind}) row.complete;
in
lib.concatStringsSep "\n" (
  [
    "# Generated from lib/dangonix/commands.nix."
    "complete -c dangonix -f"
    "complete -c dangonix -s h -l help -d ${quote "help for the command"}"
  ]
  ++ map (g: complete "__fish_use_subcommand" "-l ${g.flag} -d ${quote g.summary}") globals
  ++ [
    (complete "__fish_use_subcommand" "-l flake -r -F -d ${quote "checkout to work on"}")
  ]
  ++ map nounLine nouns
  ++ lib.concatMap verbLines nouns
  ++ lib.concatMap rowLines commands
)
+ "\n"
