# The greeter with the host's SDDM module: a typed password logs in while
# an empty-password (fingerprint) login is pending. `unpatched` is the same
# machine with stock SDDM, where the password login is dropped. `wayland`
# runs the greeter in the host's patched weston and gets a cursor;
# `stockWeston` shows the serial-0 enter after which Qt sets none.
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

  # Greeter in weston as on the host; WAYLAND_DEBUG logs its requests,
  # set_cursor among them. Weston adds ydotoold's pointer to the seat on
  # its first motion, which the test sends after the greeter's keyboard
  # enter (kiosk-shell focuses the greeter when it maps).
  waylandGreeter =
    patchedWeston:
    { options, ... }:
    {
      imports = [ ../../hosts/nixos/sddm ];

      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };

      services.displayManager.sddm = {
        enable = true;
        wayland = {
          enable = true;
          compositorCommand = lib.mkIf (!patchedWeston) (
            lib.mkForce options.services.displayManager.sddm.wayland.compositorCommand.default
          );
        };
        settings.General.GreeterEnvironment = "WAYLAND_DEBUG=1";
      };

      programs.ydotool.enable = true;
    };
in
pkgs.testers.runNixOSTest {
  name = "greeter-vm";

  nodes = {
    patched = greeter true;
    unpatched = greeter false;
    wayland = waylandGreeter true;
    stockWeston = waylandGreeter false;
  };

  enableOCR = true;

  testScript = ''
    def password_during_fingerprint(machine):
        machine.wait_for_text("(?i)select your user")
        machine.send_key("ret")
        machine.wait_for_file("/tmp/fingerprint-waiting")
        machine.send_chars("${password}\n")

    def greeter_log(pattern):
        return f"journalctl -b -o cat | grep -a -q '{pattern}'"

    # A visible cursor: set_cursor with a surface (nil hides it) that gets a
    # buffer.
    cursor_shown = (
        "log=$(journalctl -b -o cat); "
        "for s in $(grep -aoE 'wl_pointer#[0-9]+[.]set_cursor[(][1-9][0-9]*, wl_surface#[0-9]+' <<<\"$log\" "
        "| grep -oE 'wl_surface#[0-9]+$'); do "
        "grep -aqF \"$s.attach(wl_buffer#\" <<<\"$log\" && exit 0; done; exit 1"
    )

    # The first motion adds the pointer and focuses the greeter's mapped
    # surface in one weston dispatch, before the greeter's get_pointer.
    def pointer_enters(machine):
        machine.wait_until_succeeds(greeter_log("wl_keyboard#[0-9]*\\.enter("), timeout=120)
        machine.fail(greeter_log("wl_pointer#[0-9]*\\.enter("))
        machine.wait_until_succeeds(
            "ydotool mousemove -a -x 400 -y 300 && " + greeter_log("wl_pointer#[0-9]*\\.enter("),
            timeout=60,
        )

    start_all()

    with subtest("a typed password logs in while the fingerprint waits"):
        password_during_fingerprint(patched)
        patched.wait_until_succeeds("pgrep -u alice icewm", timeout=10)
        patched.succeed("journalctl -u display-manager --grep 'Cancelling the pending empty-password authentication'")
        # The keyring got the typed password, not the pending empty one.
        patched.succeed("journalctl -b -o cat | grep -a 'gkr-pam: .*keyring'")

    with subtest("stock SDDM drops the password login"):
        password_during_fingerprint(unpatched)
        unpatched.sleep(10)
        unpatched.fail("pgrep -u alice icewm")
        unpatched.succeed("journalctl -u display-manager --grep 'Existing authentication ongoing'")

    with subtest("the Wayland greeter sets a pointer cursor"):
        pointer_enters(wayland)
        wayland.fail(greeter_log("wl_pointer#[0-9]*\\.enter(0,"))
        wayland.wait_until_succeeds(cursor_shown, timeout=10)

    with subtest("stock weston enters with serial 0 and the greeter sets no cursor"):
        pointer_enters(stockWeston)
        stockWeston.succeed(greeter_log("wl_pointer#[0-9]*\\.enter(0,"))
        stockWeston.sleep(10)
        stockWeston.fail(cursor_shown)
  '';
}
