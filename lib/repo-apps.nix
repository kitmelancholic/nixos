{ pkgs }:

let
  staticCheckCommand = ''
    treefmt --tree-root "$PWD" --ci --excludes hosts/nixos/hardware-configuration.nix .
    statix check --ignore hosts/nixos/hardware-configuration.nix
    deadnix --fail --exclude hosts/nixos/hardware-configuration.nix .
  '';

  fmtScript = pkgs.writeShellApplication {
    name = "repo-fmt";
    runtimeInputs = [ pkgs.nixfmt-tree ];
    # The exclude holds with arguments too: `nix fmt -- --no-cache` must not
    # reformat the generated hardware file.
    text = ''
      [ "$#" -gt 0 ] || set -- .
      exec treefmt --tree-root "$PWD" --excludes hosts/nixos/hardware-configuration.nix "$@"
    '';
  };

  # scripts/campaign-tui runs this: Python with Textual over the checkout's
  # scripts/campaign_tui.py, so editing the file needs no rebuild.
  campaignTuiScript = pkgs.writeShellApplication {
    name = "repo-campaign-tui";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: [
        p.textual
        p.pyfiglet
      ]))
      pkgs.git
      pkgs.jq
      pkgs.less
    ];
    text = ''
      top=$(git rev-parse --show-toplevel)
      export CAMPAIGN_TUI_ROOT=$top
      exec python3 "$top/scripts/campaign_tui.py" "$@"
    '';
  };

in

{
  inherit staticCheckCommand;
  scripts = {
    campaignTui = campaignTuiScript;
    fmt = fmtScript;
  };
}
