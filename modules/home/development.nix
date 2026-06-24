{ pkgs, ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    csharp-ls # C# language server
    fd # Fast file finder for editor/tasks
    gh # GitHub CLI for development workflow
    jq # JSON CLI used by scripts and APIs
    just # Repo task runner
    netcoredbg # .NET debugger
    omnisharp-roslyn # C# language tooling fallback
    ripgrep # Fast text search for editor/tasks
    unzip # Archive extraction for downloaded tooling
  ];
}
