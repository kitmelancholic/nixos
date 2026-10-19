{ pkgs, ... }:

let
  # PreToolUse(Bash) hook shared by Claude Code and Codex (see AGENTS.md):
  # blocks any shell command whose text mentions hardware-configuration.nix.
  # Fail closed: any internal error exits 2, which blocks the command.
  bashGuard = pkgs.writeShellApplication {
    name = "bash-guard";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
    ];
    text = ''
      trap 'exit 2' EXIT
      input=$(cat)
      cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
      if grep -qF 'hardware-configuration.nix' <<<"$cmd"; then
        echo "bash-guard: hardware-configuration.nix is off limits" >&2
        exit 2
      fi
      trap - EXIT
    '';
  };
in
{
  # Outside any profile bin directory on purpose: not a command to run by hand.
  xdg.configFile."dangonix/hooks/bash-guard" = {
    source = "${bashGuard}/bin/bash-guard";
    executable = true;
  };
}
