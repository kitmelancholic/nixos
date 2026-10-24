# dangonix's transaction cases that break activation on purpose, in a VM
# (`nix build .#dangonix-vm`, `dangonix check --vm`; docs/design.md, 5).
# The node is a small NixOS with `kit` and dangonix; dangonix switches it
# between configurations of the fixture flake (./fixture), a tiny host and
# home on the same nixpkgs. The VM is offline: it builds the fixture from
# its own store, so the node carries its build dependencies, like
# nixpkgs' nixos-rebuild-* tests.
{
  pkgs,
  nixpkgs,
  home-manager,
}:

let
  inherit (pkgs) lib;
  inputs = { inherit nixpkgs home-manager; };

  # A stand-in for the one Foundry release ZIP the fixture's state.json
  # names: dangonix's preflight wants it in the store at the path
  # `requireFile` gives it.
  releaseText = "not a Foundry release";
  releaseHash = builtins.convertHash {
    hash = builtins.hashString "sha256" releaseText;
    hashAlgo = "sha256";
    toHashFormat = "sri";
  };
  release =
    pkgs.runCommand "FoundryVTT-13.1.zip"
      {
        outputHashMode = "flat";
        outputHashAlgo = "sha256";
        outputHash = releaseHash;
      }
      ''
        printf '%s' ${lib.escapeShellArg releaseText} > $out
      '';

  dangonix =
    (import ../../lib/dangonix {
      inherit lib pkgs;
      settings = {
        system = "x86_64-linux";
        hostname = "machine";
        username = "kit";
        foundry.service = "foundryvtt.service";
      };
      foundryTable."13.1".hash = releaseHash;
      themes = [
        "alpha"
        "beta"
      ];
      repo = "/home/kit/nixos";
    }).package;

  # What fixture/variant.json says in each part of the test.
  base = lib.importJSON ./fixture/variant.json;
  variants = lib.mapAttrs (_: changes: base // changes) {
    base = { };
    hostEtc.hostEtc = "1";
    hostFail = {
      hostEtc = "1";
      hostFail = true;
    };
    homeFail = {
      hostEtc = "2";
      homeFile = true;
      homeFail = true;
    };
    slowBuild = {
      hostEtc = "1";
      slowBuild = true;
    };
    stopVictim = {
      hostEtc = "1";
      stopVictim = true;
    };
  };
  variantFiles = pkgs.linkFarm "dangonix-vm-variants" (
    lib.mapAttrsToList (name: variant: {
      name = "${name}.json";
      path = pkgs.writeText "${name}.json" (builtins.toJSON variant);
    }) variants
  );
in
pkgs.testers.runNixOSTest {
  name = "dangonix-vm";

  nodes.machine =
    { ... }:
    {
      imports = [ (import ./fixture/common.nix { inherit inputs; }) ];

      system.includeBuildDependencies = true;
      environment = {
        systemPackages = [ dangonix ];
        etc = {
          "dangonix-vm/fixture".source = ./fixture;
          "dangonix-vm/variants".source = variantFiles;
        };
      };
      # The ZIP the fixture's preflight looks for.
      system.extraDependencies = [ release ];

      virtualisation = {
        cores = 2;
        memorySize = 4096;
        diskSize = 8192;
      };
    };

  testScript = ''
    import json
    import shlex

    dx = "${dangonix}/bin/dangonix"
    home = "/home/kit"
    checkout = f"{home}/nixos"
    state_dir = f"{home}/.local/state"
    env = (
        "export HOME=/home/kit XDG_RUNTIME_DIR=/run/user/1000 "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
        f"cd {checkout}; "
    )


    def kit(cmd):
        """Run a command as kit (stdout and stderr together)."""
        return machine.execute(f"runuser -u kit -- bash -c {shlex.quote(env + cmd)} 2>&1")


    def kit_ok(cmd):
        status, out = kit(cmd)
        assert status == 0, f"{cmd}: exit {status}\n{out}"
        return out.strip()


    def run(args):
        """dangonix --json <args>: (exit status, the envelope, the log)."""
        status, out = kit(f"{dx} --json {args} 2>/tmp/dangonix.err; echo EXIT=$?")
        body, _, code = out.rpartition("EXIT=")
        log = machine.succeed("cat /tmp/dangonix.err")
        return int(code), (json.loads(body) if body.strip() else None), log


    def succeeds(args):
        code, envelope, log = run(args)
        assert code == 0 and envelope["ok"], f"dangonix {args}: exit {code}\n{log}"
        return envelope


    def home_profile():
        xdg = f"{state_dir}/nix/profiles/home-manager"
        legacy = "/nix/var/nix/profiles/per-user/kit/home-manager"
        return xdg if machine.execute(f"test -e {xdg}")[0] == 0 else legacy


    def world():
        """Everything a recovered transaction must leave as it was."""
        def read(cmd):
            return machine.succeed(cmd).strip()
        return {
            "system": read("readlink -f /run/current-system"),
            "profile": read("readlink -f /nix/var/nix/profiles/system"),
            "boot": read("tail -n 1 /var/lib/dangonix-vm/boot.log"),
            "home": read(f"readlink -f {home_profile()}"),
            "state": read(f"sha256sum {checkout}/state.json"),
            "lock": read(f"sha256sum {checkout}/flake.lock"),
        }


    def variant(name):
        kit_ok(f"cp /home/kit/variants/{name}.json {checkout}/variant.json")


    def journal():
        lines = machine.succeed(f"cat {state_dir}/dangonix/journal.jsonl").splitlines()
        return [json.loads(line) for line in lines]


    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    with subtest("The fixture checkout"):
        machine.succeed("cp -rL /etc/dangonix-vm/fixture /home/kit/nixos")
        machine.succeed("cp -rL /etc/dangonix-vm/variants /home/kit/variants")
        machine.succeed("nixos-generate-config --show-hardware-config > /home/kit/nixos/machine-hardware.nix")
        machine.succeed("chown -R kit: /home/kit && chmod -R u+w /home/kit")
        # Inputs by store path: the VM has no registry to resolve names with.
        machine.succeed("sed -i -e 's|nixpkgs.url = .*|nixpkgs.url = \"path:${nixpkgs}\";|' -e 's|home-manager.url = .*|home-manager.url = \"path:${home-manager}\";|' /home/kit/nixos/flake.nix")
        kit_ok("nix flake lock")
        # The release the preflight looks for.
        machine.succeed("ls ${release}")

    with subtest("Install the fixture: host before home"):
        envelope = succeeds("switch")
        names = [step["name"] for step in envelope["steps"]]
        assert names.index("activate-host") < names.index("activate-home"), names
        machine.succeed("test -e /nix/var/nix/profiles/system-2-link || test -e /nix/var/nix/profiles/system-1-link")
        kit_ok("grep -q alpha ~/.config/dangonix-theme")
    installed = world()

    with subtest("1. A changed host is activated, host before home"):
        variant("hostEtc")
        envelope = succeeds("switch")
        names = [step["name"] for step in envelope["steps"]]
        assert names.index("activate-host") < names.index("activate-home"), names
        assert machine.succeed("cat /etc/dangonix-test") == "1"
        assert world()["system"] != installed["system"]
    before = world()

    with subtest("2. A failing host activation is recovered"):
        variant("hostFail")
        code, envelope, log = run("foundry remove main")
        assert code == 1, (code, log)
        assert envelope["failedStep"] == "activate-host", envelope
        assert envelope["recovered"] is True, envelope
        assert world() == before, (world(), before)
        assert machine.succeed("cat /etc/dangonix-test") == "1"
        last = journal()[-1]
        assert last["failedStep"] == "activate-host" and last["recovered"] is True, last

    with subtest("3. A failing home activation takes the host back too"):
        variant("homeFail")
        code, envelope, log = run("switch")
        assert code == 1, (code, log)
        assert envelope["failedStep"] == "activate-home", envelope
        assert envelope["recovered"] is True, envelope
        machine.fail(f"test -e {home}/.config/dangonix-test")
        assert machine.succeed("cat /etc/dangonix-test") == "1"
        assert world() == before, (world(), before)

    with subtest("4. A second mutation while one runs is refused"):
        variant("slowBuild")
        machine.succeed(
            "runuser -u kit -- setsid -f bash -c "
            + shlex.quote(env + f"{dx} --json theme beta >/tmp/first.json 2>/tmp/first.err; echo $? >/tmp/first.status")
            + " </dev/null >/dev/null 2>&1"
        )
        # The state edit comes right before the (slow) build.
        machine.wait_until_succeeds(f"grep -q beta {checkout}/state.json", timeout=300)
        for args in ["theme alpha", "foundry remove main"]:
            code, envelope, log = run(args)
            assert code == 4, (args, code, log)
            assert "another dangonix run holds" in envelope["data"]["error"], envelope
        machine.wait_until_succeeds("test -e /tmp/first.status", timeout=600)
        assert machine.succeed("cat /tmp/first.status").strip() == "0", machine.succeed("cat /tmp/first.err")
        assert json.loads(machine.succeed("cat /tmp/first.json"))["ok"] is True
        kit_ok("grep -q beta ~/.config/dangonix-theme")

    with subtest("5. A transaction outlives the unit it was started from"):
        variant("stopVictim")
        before_home = world()["home"]
        entries = len(journal())
        # The unit's main process is a shell, as a terminal in a session
        # unit would be: systemd kills a unit's main process wherever it is,
        # so only dangonix, its child, moves to the dangonix-<pid> scope.
        kit_ok(
            "systemd-run --user --unit=victim --collect bash -c "
            + shlex.quote(f"{dx} --json theme alpha >/tmp/victim.json 2>/tmp/victim.err; echo $? >/tmp/victim.status")
        )
        machine.wait_until_succeeds(
            f"test $(wc -l < {state_dir}/dangonix/journal.jsonl) -gt {entries}", timeout=600
        )
        # The shell went with the unit; dangonix finished in its scope.
        machine.fail("test -e /tmp/victim.status")
        last = journal()[-1]
        assert last["ok"] is True and last["command"] == "theme", last
        assert world()["home"] != before_home
        kit_ok("grep -q alpha ~/.config/dangonix-theme")
        kit_ok("test -e ~/victim-state")
        machine.wait_until_succeeds(
            "test -z \"$(runuser -u kit -- env XDG_RUNTIME_DIR=/run/user/1000 "
            "systemctl --user list-units --all --no-legend 'dangonix-*')\""
        )
  '';
}
