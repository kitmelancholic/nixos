{
  system,
  username,
}:

let
  foundryPort = 30000;
in
{
  inherit system username;
  hostname = "nixos";
  homeDirectory = "/home/${username}";

  foundry = {
    version = "14.0.0+361";
    shortVersion = "14.361";
    filename = "FoundryVTT-Linux-14.361.zip";
    hash = "sha256-zafI0qgSyToAIt0qs4zRkhUspFSFoNaS0B+uAcVrERc=";
    port = foundryPort;
    service = "foundryvtt.service";
    url = "http://127.0.0.1:${toString foundryPort}";
  };
}
