{ constants, ... }:

{
  virtualisation.docker.enable = true;

  users.users.${constants.username}.extraGroups = [ "docker" ];
}
