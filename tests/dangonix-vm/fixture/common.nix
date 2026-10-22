# What the test node and the fixture host share. dangonix switches the VM
# from one to the other, and the test driver (the backdoor, the shared
# directories) must survive that, so both are the same machine as far as the
# VM goes: the node gets this module from the test, the fixture host from
# the fixture flake.
{ inputs }:
{ lib, pkgs, ... }:
{
  networking.hostName = "machine";

  # The test framework leaves switch-to-configuration out of a plain node.
  system.switch.enable = true;
  documentation.enable = false;

  users.users.kit = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    # A user manager without a login: dangonix runs its transaction in a
    # user scope.
    linger = true;
  };
  security.sudo.wheelNeedsPassword = false;

  # Offline: the fixture's inputs are the registry's store paths.
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = lib.mkForce [ ];
      hashed-mirrors = null;
      connect-timeout = 1;
      # No global registry to download: the entries below are all there is.
      flake-registry = "";
    };
    registry = {
      nixpkgs.flake = inputs.nixpkgs;
      home-manager.flake = inputs.home-manager;
    };
  };

  # Stands in for the boot loader: records which system it was told to boot,
  # last line = the default entry.
  boot.loader = {
    grub.enable = lib.mkForce false;
    external = {
      enable = true;
      installHook = pkgs.writeShellScript "dangonix-vm-boot" ''
        mkdir -p /var/lib/dangonix-vm
        echo "$1" >> /var/lib/dangonix-vm/boot.log
      '';
    };
  };
}
