{ constants, pkgs, ... }:

{
  programs.fish.enable = true;

  users.users.${constants.username} = {
    isNormalUser = true;
    description = constants.username;
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
    ];
    packages = [ ];
  };
}
