{
  system,
  username,
}:

(import ./host.nix { inherit system username; })
// {
  apps = import ./apps.nix;
  foundry = import ./foundry.nix;
}
