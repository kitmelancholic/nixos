{ constants, pkgs, ... }:

{
  virtualisation.docker.enable = true;

  users.users.${constants.username}.extraGroups = [ "docker" ];

  environment.systemPackages = with pkgs; [
    docker-compose # Compose CLI for Docker projects
    gh # GitHub CLI for development workflow
    git
    just # Preferred repo task runner
  ];
}
