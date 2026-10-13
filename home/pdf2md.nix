{ inputs, pkgs, ... }:

let
  # PDF -> Markdown converter built on pymupdf4llm; see pdf2md/pdf2md.py.
  # nixpkgs only has pymupdf4llm 0.3.4 and no pymupdf-layout, which give much
  # worse headings/tables/code detection, so the newer wheels come from uv.lock.
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = ./pdf2md;
  };

  # pymupdf-layout's extensions link against libmupdf shipped inside the pymupdf wheel.
  layoutLibsOverlay = final: prev: {
    pymupdf-layout = prev.pymupdf-layout.overrideAttrs (old: {
      preFixup = (old.preFixup or "") + ''
        addAutoPatchelfSearchPath ${final.pymupdf}/${final.python.sitePackages}/pymupdf
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
          (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
          layoutLibsOverlay
        ]
      );

  # Only expose bin/pdf2md so the venv's python3 does not collide with graphify's.
  pdf2md = pkgs.runCommand "pdf2md" { } ''
    mkdir -p "$out/bin"
    ln -s ${pythonSet.mkVirtualEnv "pdf2md-env" workspace.deps.default}/bin/pdf2md "$out/bin/pdf2md"
  '';
in
{
  home.packages = [ pdf2md ];
}
