{
  constants,
  inputs,
  pkgs,
  ...
}:

let
  inherit (constants) foundry;
in

{
  imports = [ inputs.foundryvtt.nixosModules.foundryvtt ];

  services.foundryvtt = {
    enable = true;
    minifyStaticFiles = true;
    package =
      inputs.foundryvtt.packages.${pkgs.stdenv.hostPlatform.system}.foundryvtt_14.overrideAttrs
        (_: {
          inherit (foundry) version;
        });
    upnp = false;
  };

  networking.firewall.allowedTCPPorts = [ foundry.port ];
}
