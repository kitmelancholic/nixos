{
  inputs,
  pkgs,
  ...
}:

let
  graphifyVersion =
    (builtins.fromTOML (builtins.readFile (inputs.graphify + "/pyproject.toml"))).project.version;

  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = inputs.graphify;
  };

  lockOverlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  treeSitterNix = pkgs.python3Packages.buildPythonPackage {
    pname = "tree-sitter-nix";
    version = "0.1.0";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "tree_sitter_nix";
      version = "0.1.0";
      hash = "sha256-tVH9APu6yS8wD6lB88QbZh8pDBQVWd4PaQ1VCdmsPLA=";
    };

    build-system = [ pkgs.python3Packages.setuptools ];
    dependencies = [ pkgs.python3Packages.tree-sitter ];
  };

  nixParserOverlay = _: _: {
    tree-sitter-nix =
      pkgs.runCommand "tree-sitter-nix-0.1.0"
        {
          passthru = {
            dependencies = { };
            optional-dependencies = { };
          };
        }
        ''
          cp -a ${treeSitterNix} "$out"
        '';
  };

  projectVersionOverlay = _: prev: {
    graphifyy = prev.graphifyy.overrideAttrs (old: {
      version = graphifyVersion;
      __intentionallyOverridingVersion = true;
      patches = [ ../patches/graphify-nix-support.patch ];
      postPatch = (old.postPatch or "") + ''
        cp ${../graphify-nix/nix.py} graphify/extractors/nix.py
      '';
    });
  };

  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages {
      python = pkgs.python3;
    }).overrideScope
      (
        pkgs.lib.composeManyExtensions [
          inputs.pyproject-build-systems.overlays.wheel
          lockOverlay
          nixParserOverlay
          projectVersionOverlay
        ]
      );

  graphify = pythonSet.mkVirtualEnv "graphify-${graphifyVersion}" (
    workspace.deps.default // { tree-sitter-nix = [ ]; }
  );
  graphifySkill = pkgs.runCommand "graphify-codex-skill" { } ''
    mkdir -p "$out/references"
    cp "${inputs.graphify}/graphify/skill-codex.md" "$out/SKILL.md"
    cp -r "${inputs.graphify}/graphify/skills/codex/references/." "$out/references/"
  '';
in

{
  home = {
    packages = [ graphify ];

    file = {
      ".codex/AGENTS.md".source = ../graphify-nix/AGENTS.global.md;
      ".codex/hooks.json".source = ../.codex/hooks.json;
      ".codex/skills/graphify".source = graphifySkill;
    };
  };
}
