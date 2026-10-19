# The command table of dangonix (docs/design.md §5): help, fish completions
# and `dangonix commands` are generated from it.
#   id         unique key; dangonix.sh dispatches to it
#   name       the command words; args  the rest of the usage line
#   effect     read | runtime | state | host
#   agent      allow (read only) | ask
#   wraps      raw commands the row stands for; only data until campaign II,
#              then agents get a deny for each (design §11 "Агенти")
#   flags      command flags, for completions
#   complete   what the positional arguments complete to: themes, instances,
#              inputs, commands, files
#   reversible false for irreversible operations (design "Транзакції")
let
  row =
    r:
    {
      args = "";
      wraps = [ ];
      flags = [ ];
      complete = [ ];
      reversible = true;
      agent = if r.effect == "read" then "allow" else "ask";
    }
    // r;
in
map row [
  {
    id = "status";
    name = "status";
    effect = "read";
    summary = "theme, Foundry, and whether the system is built from state.json";
  }
  {
    id = "help";
    name = "help";
    args = "[<command>]";
    effect = "read";
    complete = [ "commands" ];
    summary = "help from the command table";
  }
  {
    id = "commands";
    name = "commands";
    effect = "read";
    summary = "every command with effect and agent (--json: the API for agents and shells)";
  }
  {
    id = "version";
    name = "version";
    effect = "read";
    summary = "dangoNix version, commit, dirty tree, host and home generations, nixpkgs date";
  }
  {
    id = "history";
    name = "history";
    effect = "read";
    summary = "transaction journal with host and home generations";
  }
  {
    id = "check";
    name = "check";
    args = "[--fast|--vm]";
    effect = "read";
    flags = [
      "--docs"
      "--fast"
      "--full"
      "--vm"
    ];
    summary = "lint docs, commits and scripts, then nix flake check; --fast: evaluate only; --vm: VM tests";
  }
  {
    id = "switch";
    name = "switch";
    args = "[--home|--host] [--overwrite]";
    effect = "host";
    flags = [
      "--home"
      "--host"
      "--overwrite"
    ];
    wraps = [
      "nixos-rebuild"
      "home-manager switch"
      "switch-to-configuration"
      "nix-env --set"
    ];
    summary = "build host and home, activate the host if it changed, then home";
  }
  {
    id = "update";
    name = "update";
    args = "[<input>...]";
    effect = "state";
    complete = [ "inputs" ];
    wraps = [ "nix flake update" ];
    summary = "update every input but the held ones, then check; never switches or commits";
  }
  {
    id = "theme";
    name = "theme";
    effect = "read";
    summary = "themes: selected (state.json) and active";
  }
  {
    id = "theme-set";
    name = "theme";
    args = "<id>";
    effect = "state";
    complete = [ "themes" ];
    wraps = [ "home-manager switch" ];
    summary = "write the theme to state.json, build and activate home";
  }
  {
    id = "foundry-list";
    name = "foundry list";
    effect = "read";
    summary = "Foundry instances: version, port, state, URL";
  }
  {
    id = "foundry-status";
    name = "foundry status";
    args = "[<name>]";
    effect = "read";
    complete = [ "instances" ];
    summary = "report on an instance, without a name on every instance";
  }
  {
    id = "foundry-logs";
    name = "foundry logs";
    args = "[<name>] [-f]";
    effect = "read";
    flags = [ "-f" ];
    complete = [ "instances" ];
    summary = "journal of an instance";
  }
  {
    id = "foundry-start";
    name = "foundry start";
    args = "[<name>]";
    effect = "runtime";
    complete = [ "instances" ];
    wraps = [ "systemctl start foundryvtt*" ];
    summary = "start the instance service";
  }
  {
    id = "foundry-stop";
    name = "foundry stop";
    args = "[<name>]";
    effect = "runtime";
    complete = [ "instances" ];
    wraps = [ "systemctl stop foundryvtt*" ];
    summary = "stop the instance service (ends a running game)";
  }
  {
    id = "foundry-restart";
    name = "foundry restart";
    args = "[<name>]";
    effect = "runtime";
    complete = [ "instances" ];
    wraps = [ "systemctl restart foundryvtt*" ];
    summary = "restart the instance service (ends a running game)";
  }
  {
    id = "foundry-open";
    name = "foundry open";
    args = "[<name>]";
    effect = "runtime";
    complete = [ "instances" ];
    summary = "start the instance if needed and open it in the browser";
  }
  {
    id = "foundry-import";
    name = "foundry import";
    args = "<zip>";
    effect = "state";
    complete = [ "files" ];
    reversible = false;
    wraps = [ "nix-store --add-fixed" ];
    summary = "import a release ZIP (store and GC root) for a version state.json has";
  }
  {
    id = "foundry-upgrade";
    name = "foundry upgrade";
    args = "[<name>] <zip> [--backed-up]";
    effect = "host";
    flags = [ "--backed-up" ];
    complete = [
      "instances"
      "files"
    ];
    summary = "import a ZIP, set the instance version, switch host; across majors only --backed-up";
  }
  {
    id = "foundry-add";
    name = "foundry add";
    args = "<name> <zip> [--port <N>]";
    effect = "host";
    flags = [ "--port" ];
    complete = [ "files" ];
    summary = "import a ZIP, add the instance to state.json, switch host";
  }
  {
    id = "foundry-remove";
    name = "foundry remove";
    args = "<name>";
    effect = "host";
    complete = [ "instances" ];
    summary = "drop the instance from state.json, switch host; its data stays on disk";
  }
]
