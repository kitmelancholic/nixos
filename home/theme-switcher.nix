{
  config,
  lib,
  pkgs,
  themeFlakeSource,
  homeManagerPackage,
  hyprlandPkg,
  themeModel,
  ...
}:

let
  inherit (themeModel) default ids profileName;
  themeIds = ids;
  profileFor = profileName;
  profileCases = lib.concatMapStringsSep "\n" (
    themeId: "    ${themeId}) profile=${profileFor themeId} ;;"
  ) themeIds;
  kitTheme = pkgs.writeShellApplication {
    name = "kit-theme";
    runtimeInputs = [
      homeManagerPackage
      hyprlandPkg
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
            usage() {
              echo "usage: kit-theme list | current | switch <theme>" >&2
            }

            config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
            identity_file="$config_home/kit/theme-id"
            theme_flake="''${KIT_THEME_FLAKE:-${themeFlakeSource}}"

            validate_theme() {
              case "$1" in
      ${lib.concatMapStringsSep "\n" (themeId: "          ${themeId}) return 0;;") themeIds}
                *)
                  echo "kit-theme: unknown theme '$1'" >&2
                  echo "available themes: ${lib.concatStringsSep ", " themeIds}" >&2
                  return 1
                  ;;
              esac
            }

            converge() {
              failures=""
              report_failure() {
                failures="''${failures} $1"
                echo "kit-theme: failed to converge $1" >&2
              }

              if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
                if hyprctl instances >/dev/null 2>&1; then
                  hyprctl reload >/dev/null 2>&1 || report_failure "Hyprland"
                fi

                systemctl --user reload-or-restart waybar.service >/dev/null 2>&1 || report_failure "Waybar"
                systemctl --user reload-or-restart dunst.service >/dev/null 2>&1 || report_failure "Dunst"

                if systemctl --user is-active --quiet swayosd.service; then
                  systemctl --user try-restart swayosd.service >/dev/null 2>&1 || report_failure "SwayOSD"
                fi

                wallpaper-apply >/dev/null 2>&1 || report_failure "wallpaper"
              fi

              if [ -n "$failures" ]; then
                return 1
              fi
            }

            if [ "$#" -eq 0 ]; then
              usage
              exit 2
            fi

            case "$1" in
              list)
                [ "$#" -eq 1 ] || { usage; exit 2; }
                printf '%s\n' ${lib.concatStringsSep " " themeIds}
                ;;
              current)
                [ "$#" -eq 1 ] || { usage; exit 2; }
                if [ ! -e "$identity_file" ]; then
                  echo "${default}"
                  exit 0
                fi
                current="$(<"$identity_file")"
                validate_theme "$current" || {
                  echo "kit-theme: invalid generated theme identity in $identity_file" >&2
                  exit 1
                }
                echo "$current"
                ;;
              switch)
              [ "$#" -eq 2 ] || { usage; exit 2; }
              id="$2"
              validate_theme "$id"

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
          echo "kit-theme: another managed Home Manager activation is already running" >&2
          exit 1
        fi

                case "$id" in
      ${profileCases}
                esac

                echo "Activating Home Manager theme: $id"
                if ! home-manager switch --flake "$theme_flake#$profile"; then
                  echo "kit-theme: Home Manager activation failed; generated identity unchanged" >&2
                  exit 1
                fi

                if converge; then
                  echo "Theme active: $id"
                else
                  echo "Theme active: $id (desktop convergence incomplete)" >&2
                  exit 1
                fi
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
  xdg.configFile."kit/theme-id".text = "${config.kit.theme.id}\n";
  home.packages = [ kitTheme ];
}
