{
  config,
  pkgs,
  settings,
  homeManagerPackage,
  ...
}:

let
  kitProfile = pkgs.writeShellApplication {
    name = "kit-profile";
    runtimeInputs = [
      homeManagerPackage
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
          usage() {
            echo "usage: kit-profile list [--json] | current | switch <id>" >&2
          }

          config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
          identity_file="$config_home/kit/profile-id"
          profile_flake="''${KIT_PROFILE_FLAKE:-''${KIT_THEME_FLAKE:-$HOME/nixos}}"
          if [ ! -d "$profile_flake" ] || [ ! -f "$profile_flake/flake.nix" ]; then
            echo "kit-profile: checkout not found at $profile_flake; set KIT_PROFILE_FLAKE to your checkout" >&2
            exit 1
          fi
          profile_flake="$(realpath "$profile_flake")"
          registry="$(nix eval "$profile_flake#lib.themes" --json)"
          current_id="$(cat "$identity_file" 2>/dev/null || true)"

          validate_profile() {
            if ! jq -e --arg id "$1" '.profiles | has($id)' <<< "$registry" >/dev/null; then
              echo "kit-profile: unknown profile '$1'" >&2
              echo "available profiles: $(jq -r '.profiles | keys | join(", ")' <<< "$registry")" >&2
              return 1
            fi
          }

          if [ "$#" -eq 0 ]; then
            usage
            exit 2
          fi

          case "$1" in
            list)
              if [ "''${2:-}" = "--json" ] && [ "$#" -eq 2 ]; then
                jq --arg current "$current_id" '
                  .default as $default | .profiles | to_entries | sort_by(.key) |
                  map({id: .key, name: .value.name, description: .value.description,
                       default: (.key == $default), active: (.key == $current)})
                ' <<< "$registry"
              elif [ "$#" -eq 1 ]; then
                jq -r '.profiles | keys[]' <<< "$registry"
              else
                usage; exit 2
              fi
              ;;
            current)
              [ "$#" -eq 1 ] || { usage; exit 2; }
              if [ ! -e "$identity_file" ]; then
                jq -r .default <<< "$registry"
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

              profile="${settings.username}-$id"

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
