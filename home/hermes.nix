{ inputs, ... }:

{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  # CLI and the Electron app (with an XDG launcher); both run the one
  # Nix-built `hermes`. No `services.hermes-agent`: that would make
  # ~/.hermes managed and block `hermes setup` until secrets are declared.
  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };
}
