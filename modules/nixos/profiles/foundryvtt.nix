{ inputs, pkgs, ... }:

{
  imports = [ inputs.foundryvtt.nixosModules.foundryvtt ];

  services.foundryvtt = {
    enable = true;
    minifyStaticFiles = true;
    package = inputs.foundryvtt.packages.${pkgs.stdenv.hostPlatform.system}.foundryvtt_13;
    upnp = false;
  };

  networking.firewall.allowedTCPPorts = [ 30000 ];
}
