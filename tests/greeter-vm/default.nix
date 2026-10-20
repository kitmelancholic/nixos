# The greeter with the host's SDDM module: a typed password logs in while
# an empty-password (fingerprint) login is pending. `unpatched` is the same
# machine with stock SDDM, where the password login is dropped.
{ pkgs }:

let
  inherit (pkgs) lib;
  password = "foobar";

  # Stands in for pam_fprintd: an empty token waits for a finger that never
  # comes, then fails; a typed one fails at once.
  fingerprint = pkgs.writeShellScript "fingerprint-stand-in" ''
    IFS= read -r -d "" token || true
    if [ -z "$token" ]; then
      : > /tmp/fingerprint-waiting
      ${pkgs.coreutils}/bin/sleep 60
    fi
    exit 1
  '';

  greeter =
    patched:
    { config, ... }:
    {
      imports = [ ../../hosts/nixos/sddm ];

      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };

      services = {
        xserver = {
          enable = true;
          windowManager.icewm.enable = true;
        };
        displayManager = {
          sddm = {
            enable = true;
            package = lib.mkIf (!patched) (lib.mkForce pkgs.kdePackages.sddm);
          };
          defaultSession = "none+icewm";
        };
        gnome.gnome-keyring.enable = true;
      };

      # Where pam_fprintd sits in the host's login stack.
      security.pam.services.login.rules.auth.fingerprint = {
        order = 11400;
        control = "sufficient";
        modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
        args = [
          "expose_authtok"
          "${fingerprint}"
        ];
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "greeter-vm";

  nodes = {
    patched = greeter true;
    unpatched = greeter false;
  };

  enableOCR = true;

  testScript = ''
    def password_during_fingerprint(machine):
        machine.wait_for_text("(?i)select your user")
        machine.send_key("ret")
        machine.wait_for_file("/tmp/fingerprint-waiting")
        machine.send_chars("${password}\n")

    start_all()

    with subtest("a typed password logs in while the fingerprint waits"):
        password_during_fingerprint(patched)
        patched.wait_until_succeeds("pgrep -u alice icewm", timeout=10)
        patched.succeed("journalctl -u display-manager --grep 'Cancelling the pending empty-password authentication'")

    with subtest("stock SDDM drops the password login"):
        password_during_fingerprint(unpatched)
        unpatched.sleep(10)
        unpatched.fail("pgrep -u alice icewm")
        unpatched.succeed("journalctl -u display-manager --grep 'Existing authentication ongoing'")
  '';
}
