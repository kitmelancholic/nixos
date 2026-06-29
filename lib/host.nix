{
  system,
  username,
}:

{
  inherit system username;
  hostname = "nixos";
  homeDirectory = "/home/${username}";
}
