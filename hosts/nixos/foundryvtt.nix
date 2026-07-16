{
  settings,
  inputs,
  pkgs,
  ...
}:

let
  inherit (settings) foundry;
in

{
  imports = [ inputs.foundryvtt.nixosModules.foundryvtt ];

  services.foundryvtt = {
    enable = true;
    minifyStaticFiles = true;
    package =
      inputs.foundryvtt.packages.${pkgs.stdenv.hostPlatform.system}.foundryvtt_13.overrideAttrs
        (_: {
          inherit (foundry) version;
        });
    upnp = false;
  };

  networking.firewall.allowedTCPPorts = [ foundry.port ];

  security.sudo.extraRules = [
    {
      users = [ settings.username ];
      commands =
        let
          systemctl = "${pkgs.systemd}/bin/systemctl";
        in
        [
          {
            command = "${systemctl} start ${foundry.service}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${systemctl} stop ${foundry.service}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${systemctl} restart ${foundry.service}";
            options = [ "NOPASSWD" ];
          }
        ];
    }
  ];
}
