{
  config,
  lib,
  pkgs,
  settings,
  profileFlakeSource,
  homeManagerPackage,
  profileRegistry,
  ...
}:

let
  inherit (profileRegistry) default profiles;
  profileIds = builtins.sort builtins.lessThan (builtins.attrNames profiles);
  profileOutputs = lib.concatMapStringsSep "\n" (
    profileId: "          ${profileId}) profile=${settings.username}-${profileId} ;;"
  ) profileIds;
  profileCases = lib.concatMapStringsSep "\n" (
    profileId: "          ${profileId}) return 0;;"
  ) profileIds;
  profileMetadata = lib.concatMapStringsSep "\n" (
    profileId:
    ''${profileId}) name="${profiles.${profileId}.name}"; description="${
      profiles.${profileId}.description
    }"; default=${if profileId == default then "true" else "false"} ;;''
  ) profileIds;
  kitProfile = pkgs.writeShellApplication {
    name = "kit-profile";
    runtimeInputs = [
      homeManagerPackage
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
            usage() {
              echo "usage: kit-profile list [--json] | current | switch <id>" >&2
            }

            config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
            identity_file="$config_home/kit/profile-id"
            profile_flake="''${KIT_PROFILE_FLAKE:-''${KIT_THEME_FLAKE:-${profileFlakeSource}}}"
            current_id="$(cat "$identity_file" 2>/dev/null || true)"

            validate_profile() {
              case "$1" in
      ${profileCases}
                *)
                  echo "kit-profile: unknown profile '$1'" >&2
                  echo "available profiles: ${lib.concatStringsSep ", " profileIds}" >&2
                  return 1
                  ;;
              esac
            }

            if [ "$#" -eq 0 ]; then
              usage
              exit 2
            fi

            case "$1" in
              list)
                if [ "''${2:-}" = "--json" ] && [ "$#" -eq 2 ]; then
                  first=true
                  printf '['
                  for profile_id in ${lib.concatStringsSep " " profileIds}; do
                    case "$profile_id" in
      ${profileMetadata}
                    esac
                    active=false
                    [ "$current_id" = "$profile_id" ] && active=true
                    if [ "$first" = true ]; then first=false; else printf ','; fi
                    printf '{"id":"%s","name":"%s","description":"%s","default":%s,"active":%s}' \
                      "$profile_id" "$name" "$description" "$default" "$active"
                  done
                  printf ']\n'
                elif [ "$#" -eq 1 ]; then
                  printf '%s\n' ${lib.concatStringsSep " " profileIds}
                else
                  usage; exit 2
                fi
                ;;
              current)
                [ "$#" -eq 1 ] || { usage; exit 2; }
                if [ ! -e "$identity_file" ]; then
                  echo "${default}"
                  exit 0
                fi
                current="$(<"$identity_file")"
                validate_profile "$current" || {
                  echo "kit-profile: invalid generated profile identity in $identity_file" >&2
                  exit 1
                }
                echo "$current"
                ;;
              switch)
              [ "$#" -eq 2 ] || { usage; exit 2; }
              id="$2"
              validate_profile "$id"

        if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
          lock_file="$XDG_RUNTIME_DIR/kit-home-activation.lock"
        else
          activation_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/kit"
          umask 077
          mkdir -p "$activation_state_dir"
          chmod 700 "$activation_state_dir"
          lock_file="$activation_state_dir/home-activation.lock"
        fi

        exec 9>"$lock_file"
        if ! flock -n 9; then
          echo "kit-profile: another managed Home Manager activation is already running" >&2
          exit 1
        fi

                case "$id" in
      ${profileOutputs}
                esac

                echo "Activating Home Manager profile: $id"
                if ! home-manager switch --flake "$profile_flake#$profile"; then
                  echo "kit-profile: Home Manager activation failed; generated identity unchanged" >&2
                  exit 1
                fi
                echo "Profile active: $id"
                ;;
              *)
                usage
                exit 2
                ;;
            esac
    '';
  };
in
{
  xdg.configFile."kit/profile-id".text = "${config.kit.profile.id}\n";
  xdg.configFile."kit/theme-id".text = "${config.kit.profile.id}\n";
  home.packages = [ kitProfile ];
  home.file.".local/bin/kit-theme" = {
    executable = true;
    text = ''exec kit-profile "$@"'';
  };
}
