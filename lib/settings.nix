{
  system,
  username,
  state,
}:

let
  instances = state.foundry.instances;
  names = builtins.attrNames instances;
  enable = names != [ ];
  instance = instances.${builtins.head names};
in
assert
  builtins.length names <= 1 || throw "state.json: several Foundry instances arrive in campaign II";
{
  inherit system username;
  hostname = "nixos";
  homeDirectory = "/home/${username}";

  foundry = {
    inherit enable;
    service = "foundryvtt.service";
  }
  // (
    if enable then
      {
        inherit (instance) version port;
        url = "http://127.0.0.1:${toString instance.port}";
      }
    else
      { }
  );
}
