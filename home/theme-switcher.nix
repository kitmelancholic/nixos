{
  lib,
  pkgs,
  settings,
  themeFlakeSource,
  homeManagerPackage,
  hyprlandPkg,
  ...
}:

let
  themeSet = import ../themes;
  themeIds = builtins.sort builtins.lessThan (builtins.attrNames themeSet.themes);
  profileFor = themeId: if themeId == "kit-dark" then themeId else "${settings.username}-${themeId}";
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

            state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
            state_dir="$state_home/kit-theme"
            state_file="$state_dir/current"
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
                if [ ! -e "$state_file" ]; then
                  echo "${themeSet.default}"
                  exit 0
                fi
                current="$(<"$state_file")"
                validate_theme "$current" || {
                  echo "kit-theme: invalid recorded theme in $state_file" >&2
                  exit 1
                }
                echo "$current"
                ;;
              switch)
                [ "$#" -eq 2 ] || { usage; exit 2; }
                id="$2"
                validate_theme "$id"

                if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
                  lock_file="$XDG_RUNTIME_DIR/kit-theme-switch.lock"
                else
                  umask 077
                  mkdir -p "$state_dir"
                  chmod 700 "$state_dir"
                  lock_file="$state_dir/switch.lock"
                fi

                exec 9>"$lock_file"
                if ! flock -n 9; then
                  echo "kit-theme: another theme switch is already running" >&2
                  exit 1
                fi

                case "$id" in
      ${profileCases}
                esac

                echo "Activating Home Manager theme: $id"
                if ! home-manager switch --flake "$theme_flake#$profile"; then
                  echo "kit-theme: Home Manager activation failed; state unchanged" >&2
                  exit 1
                fi

                umask 077
                mkdir -p "$state_dir"
                chmod 700 "$state_dir"
                temporary="$state_file.tmp.$$"
                printf '%s\n' "$id" > "$temporary"
                chmod 600 "$temporary"
                mv -f "$temporary" "$state_file"

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
  home.packages = [ kitTheme ];
}
