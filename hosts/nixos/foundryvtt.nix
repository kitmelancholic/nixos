{
  settings,
  inputs,
  lib,
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
      inputs.foundryvtt.packages.${pkgs.stdenv.hostPlatform.system}.foundryvtt_14.overrideAttrs
        (_: {
          inherit (foundry) version;
        });
    upnp = false;
  };

  # Let the desktop user manage Foundry's data without sudo.  The upstream
  # module defaults to 0750/0027, so make both existing and newly-created data
  # group-writable for members of the foundryvtt group.
  users.users.${settings.username}.extraGroups = [ "foundryvtt" ];

  systemd.services.foundryvtt-permissions = {
    description = "Prepare group-writable Foundry VTT data";
    before = [ "foundryvtt.service" ];
    requiredBy = [ "foundryvtt.service" ];
    path = [ pkgs.acl ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.Type = "oneshot";
    script = ''
      chown -R foundryvtt:foundryvtt /var/lib/foundryvtt
      find /var/lib/foundryvtt -type d -exec chmod g+rwx,g-s {} +
      find /var/lib/foundryvtt -type f -exec chmod g+rw {} +
      find /var/lib/foundryvtt -type d -exec setfacl --modify \
        default:user::rwx,default:group::rwx,default:group:foundryvtt:rwx,default:mask::rwx,default:other::--- {} +
    '';
  };

  systemd.services.foundryvtt = {
    preStart = lib.mkAfter ''
      chmod g+rwx /var/lib/foundryvtt/Config
      chmod g+rw /var/lib/foundryvtt/Config/options.json
    '';
    serviceConfig = {
      StateDirectoryMode = lib.mkForce "0770";
      UMask = lib.mkForce "0007";
    };
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
