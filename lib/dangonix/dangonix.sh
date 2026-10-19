# dangonix: the one CLI of dangoNix (docs/design.md, 5). default.nix prepends
# DANGONIX_CONFIG: a JSON file with the host, the user, the default checkout,
# the held inputs, the Foundry version table and the command table.
#
# Every command prints one result: text, or with --json one envelope
# {command, ok, exit, data, warnings} on stdout; mutations (every effect but
# read) add steps, failedStep, recovered, reversible. Logs go to stderr.
# Exit codes: 0 ok, 1 failed (state restored), 2 usage, 3 recovery failed,
# 4 refused before any change.
#
# Until c1q14 state and host commands only plan: with --dry they print the
# plan, without it they refuse with exit 4.

json=0
dry=0
yes=0
# shellcheck disable=SC2034  # parsed now, checked from campaign II (design, 8)
metered_ok=0
flake=""
bare=0

# The command being run (use), and the result of a mutation.
command_name=""
effect="read"
reversible=true
steps='[]'
failed_step=null
recovered=null
warnings=()

sudo=/run/wrappers/bin/sudo

cfg() { jq -r "$@" "$DANGONIX_CONFIG"; }
log() { printf '%s\n' "$*" >&2; }
warn() {
  warnings+=("$1")
  log "dangonix: warning: $1"
}
# say <line>: progress; on stderr with --json, so stdout stays one JSON.
say() { if ((json)); then log "$*"; else printf '%s\n' "$*"; fi; }

# use <id>: the command being run is row <id> of the command table.
use() {
  local row
  row=$(cfg -c --arg id "$1" '.commands[] | select(.id == $id)')
  command_name=$(jq -r .name <<<"$row")
  effect=$(jq -r .effect <<<"$row")
  reversible=$(jq -r .reversible <<<"$row")
}

# envelope <exit> <data>: the JSON result.
envelope() {
  local ws extra='{}'
  ws=$(jq -cn '$ARGS.positional' --args "${warnings[@]}")
  if [ "$effect" != read ]; then
    extra=$(jq -cn --argjson steps "$steps" --argjson failed "$failed_step" \
      --argjson recovered "$recovered" --argjson reversible "$reversible" \
      '{steps: $steps, failedStep: $failed, recovered: $recovered, reversible: $reversible}')
  fi
  jq -n --arg command "$command_name" --argjson exit "$1" --argjson data "$2" \
    --argjson warnings "$ws" --argjson extra "$extra" \
    '{command: $command, ok: ($exit == 0), exit: $exit, data: $data, warnings: $warnings} + $extra'
}

# finish <data> <jq filter>: print the result and exit 0. The filter renders
# the data as text; it also sees $steps.
finish() {
  if ((json)); then
    envelope 0 "$1"
  else
    jq -r --argjson steps "$steps" "$2" <<<"$1"
  fi
  exit 0
}

# fail <exit> <message>: print the error and exit. Never call it inside $(...).
fail() {
  log "dangonix: $2"
  if ((json)); then
    envelope "$1" "$(jq -cn --arg error "$2" '{error: $error}')"
  fi
  exit "$1"
}

usage() { fail 2 "$1 (see: dangonix help${command_name:+ $command_name})"; }

# no_args <args...>: the command takes none.
no_args() { [ "$#" -eq 0 ] || usage "$command_name takes no arguments"; }

# plan <name> <detail>: the next step of a mutation.
plan() {
  steps=$(jq -c --arg name "$1" --arg detail "$2" \
    '. + [{name: $name, detail: $detail, status: "planned"}]' <<<"$steps")
}

# planned <data>: planning is over. With --dry print the plan and exit; a
# state or host command refuses without it; a runtime command goes on.
planned() {
  if ((dry)); then
    finish "$1" '"dangonix --dry: would", ($steps | to_entries[] | "  \(.key + 1). \(.value.name): \(.value.detail)")'
  fi
  case $effect in
  state | host)
    steps='[]'
    fail 4 "$command_name is not available before c1q14; 'dangonix --dry $command_name ...' shows its plan"
    ;;
  esac
}

# run_step <name> <command...>: run a planned step; its output goes to stderr.
run_step() {
  local name=$1 status="done"
  shift
  "$@" >&2 || status=failed
  steps=$(jq -c --arg name "$name" --arg status "$status" \
    'map(if .name == $name then .status = $status else . end)' <<<"$steps")
  if [ "$status" = failed ]; then
    failed_step=$(jq -cn --arg name "$name" '$name')
    fail 1 "$command_name: step $name failed"
  fi
}

# confirm_plan: an irreversible step asks y/N on a TTY and needs --yes without.
confirm_plan() {
  if ! ((yes)) && ! [ -t 0 ]; then
    warn "the import is irreversible: without a TTY it needs --yes"
  fi
}

# need_flake: the checkout to work on: --flake, else the dangoNix checkout
# around the working directory, else kit.repo.
need_flake() {
  local top
  if [ -z "$flake" ]; then
    if top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -f "$top/lib/dangonix/commands.nix" ]; then
      flake=$top
    else
      flake=$(cfg .repo)
    fi
  fi
  [ -f "$flake/flake.nix" ] || fail 4 "no dangoNix checkout at $flake (pass --flake <path>)"
  flake=$(realpath "$flake")
  state_file=$flake/state.json
  lock_file=$flake/flake.lock
}

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}
journal=$state_dir/dangonix/journal.jsonl
host_profile=/nix/var/nix/profiles/system
home_profile=$state_dir/nix/profiles/home-manager

active_theme() { cat "${XDG_CONFIG_HOME:-$HOME/.config}/kit/profile-id" 2>/dev/null || true; }

# generations <profile>: its generations, oldest first, and which is current.
generations() {
  local link rows=""
  for link in "$1"-*-link; do
    [ -L "$link" ] || continue
    rows+="${link##*/} $(stat -c %Y "$link")"$'\n'
  done
  jq -Rcn --arg current "$(readlink "$1" 2>/dev/null || true)" --arg prefix "${1##*/}-" '
    [inputs | select(. != "") | split(" ")
      | {generation: (.[0] | ltrimstr($prefix) | rtrimstr("-link") | tonumber),
         date: (.[1] | tonumber | todate), current: (.[0] == $current)}]
    | sort_by(.generation)' <<<"$rows"
}

# current_generation <profile>: the number of its current generation, or null.
current_generation() {
  local link
  link=$(readlink "$1" 2>/dev/null) || {
    echo null
    return
  }
  link=${link%-link}
  link=${link##*-}
  if [[ $link =~ ^[0-9]+$ ]]; then echo "$link"; else echo null; fi
}

# --- Foundry ----------------------------------------------------------------

# foundry_instances: the instances of state.json with their service state and
# what the running host deployed: the version from the package in ExecStart,
# the port from the options.json the pre-start script installs. One service
# serves the one instance until campaign II.
foundry_instances() {
  local service active deployed pre_start options port=""
  service=$(cfg .foundry.service)
  active=$(systemctl is-active "$service" 2>/dev/null || true)
  deployed=$(systemctl show -p ExecStart --value "$service" 2>/dev/null |
    grep -o 'foundryvtt-[0-9][^/ ]*' | head -n 1 || true)
  pre_start=$(systemctl show -p ExecStartPre --value "$service" 2>/dev/null |
    grep -o '/nix/store/[^ ;]*' | head -n 1 || true)
  if [ -f "$pre_start" ]; then
    options=$(grep -o '/nix/store/[^ "]*-options.json' "$pre_start" | head -n 1 || true)
    [ ! -f "$options" ] || port=$(jq -r '.port // empty' "$options" 2>/dev/null || true)
  fi
  jq -c --arg service "$service" --arg active "${active:-unknown}" \
    --arg version "${deployed#foundryvtt-}" --arg port "$port" '
    .foundry.instances | to_entries | map({
      name: .key, version: .value.version, port: .value.port,
      url: "http://127.0.0.1:\(.value.port)", service: $service, state: $active,
      deployed: (if $version == "" then null else
        {version: $version, port: (if $port == "" then null else ($port | tonumber) end)} end)})' \
    "$state_file"
}

# instance [<name>]: set $inst to the named instance, or to the only one.
instance() {
  local names
  mapfile -t names < <(jq -r '.foundry.instances | keys[]' "$state_file")
  if [ -n "${1:-}" ]; then
    jq -e --arg name "$1" '.foundry.instances | has($name)' "$state_file" >/dev/null ||
      usage "no Foundry instance '$1' in state.json (instances: ${names[*]:-none})"
    inst=$1
  elif [ "${#names[@]}" -eq 1 ]; then
    inst=${names[0]}
  elif [ "${#names[@]}" -eq 0 ]; then
    fail 4 "no Foundry instance in state.json (dangonix foundry add <name> <zip>)"
  else
    usage "name the Foundry instance: ${names[*]}"
  fi
}

# zip_info <zip>: check a release ZIP against nix-foundryvtt's version table
# by its name and hash; set zip_path, zip_file, zip_version.
zip_info() {
  local entry hash actual
  [ -f "$1" ] || usage "no such file: $1"
  # Not resolved: nix-store --add-fixed names the store path after the file.
  zip_path=$(realpath --no-symlinks "$1")
  zip_file=${zip_path##*/}
  entry=$(cfg -c --arg file "$zip_file" \
    '[.foundry.versions[] | select(.file == $file)] | first // empty')
  [ -n "$entry" ] ||
    usage "$zip_file is not a release in nix-foundryvtt's version table (FoundryVTT-Linux-<major>.<build>.zip)"
  zip_version=$(jq -r .version <<<"$entry")
  hash=$(jq -r .hash <<<"$entry")
  actual=$(nix hash file --type sha256 --sri "$zip_path") || fail 1 "cannot hash $zip_path"
  [ "$actual" = "$hash" ] || usage "$zip_file has hash $actual, the version table says $hash"
}

# plan_import: the irreversible steps that put the ZIP in the store.
plan_import() {
  confirm_plan
  plan import "nix-store --add-fixed sha256 $zip_path (irreversible)"
  plan gc-root "nix-store --add-root ~/FoundryVTT/gcroots/$zip_file"
}

plan_host_switch() {
  plan build "nix build $flake#nixosConfigurations.$(cfg .hostname).config.system.build.toplevel"
  plan activate-host "switch-to-configuration switch, if the host changed"
}

# --- commands ---------------------------------------------------------------

cmd_status() {
  no_args "$@"
  need_flake
  local data text
  data=$(jq -cn --arg selected "$(jq -r .theme "$state_file")" --arg active "$(active_theme)" \
    --argjson foundry "$(foundry_instances)" '{
      theme: {selected: $selected, active: (if $active == "" then null else $active end)},
      foundry: $foundry,
      built: ($selected == $active
        and ($foundry | all(.deployed == {version: .version, port: .port})))}')
  text='
    "theme     \(.theme.selected) (active: \(.theme.active // "none"))",
    (if .foundry == [] then "foundry   none" else
      (.foundry[] | "foundry   \(.name) \(.version) on :\(.port), \(.state)"
        + (if .deployed == {version: .version, port: .port} then ""
           elif .deployed == null then " (not deployed)"
           else " (running \(.deployed.version) on :\(.deployed.port // "?"))" end)) end),
    (if .built then "state     the system is built from state.json"
     else "state     the system is not built from state.json: dangonix switch" end)'
  if ((bare)); then
    text+=', "", "dangonix help: every command"'
  fi
  finish "$data" "$text"
}

# rows_text: the jq filter that lists command rows as text.
rows_text='
  def pad(n): . + ([range(0; n - length)] | map(" ") | add // "");
  .[] | ("dangonix \(.name) \(.args)" | pad(54)) + " \(.effect | pad(8)) \(.summary)"'

cmd_help() {
  local words data
  words=$(jq -cn '$ARGS.positional' --args "$@")
  # A row matches when the words begin with its name or its name with them.
  data=$(cfg -c --argjson w "$words" '[.commands[]
    | (.name | split(" ")) as $n
    | select($n[0:($w | length)] == $w or $w[0:($n | length)] == $n)]')
  if [ "$data" = '[]' ]; then
    usage "unknown command: $*"
  fi
  if [ "$#" -gt 0 ]; then
    finish "$data" '.[] | "dangonix \(.name) \(.args)", "  \(.summary)",
      "  effect \(.effect), agent \(.agent)\(if .reversible then "" else ", irreversible" end)"'
  fi
  finish "$data" '
    "usage: dangonix [--json] [--dry] [--yes] [--metered-ok] [--flake <path>] <command> [<args>]",
    "  dangonix alone shows the status; every command takes --help.",
    "", '"$rows_text"
}

cmd_commands() {
  no_args "$@"
  finish "$(cfg -c .commands)" "$rows_text"' + " (agent \(.agent))"'
}

cmd_version() {
  no_args "$@"
  need_flake
  local describe commit dirty=false nixpkgs data
  describe=$(git -C "$flake" describe --tags --always --dirty 2>/dev/null || echo unknown)
  commit=$(git -C "$flake" rev-parse HEAD)
  [ -z "$(git -C "$flake" status --porcelain)" ] || dirty=true
  nixpkgs=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified' "$lock_file")
  data=$(jq -cn --arg version "$describe" --arg commit "$commit" --argjson dirty "$dirty" \
    --argjson host "$(current_generation "$host_profile")" \
    --argjson home "$(current_generation "$home_profile")" \
    --arg nixpkgs "$(date -u -d "@$nixpkgs" +%F)" \
    '{version: $version, commit: $commit, dirty: $dirty,
      generations: {host: $host, home: $home}, nixpkgs: $nixpkgs}')
  finish "$data" '"dangoNix \(.version)\(if .dirty then " (dirty tree)" else "" end)",
    "commit    \(.commit)",
    "host      generation \(.generations.host // "none")",
    "home      generation \(.generations.home // "none")",
    "nixpkgs   \(.nixpkgs)"'
}

cmd_history() {
  no_args "$@"
  local entries='[]' data
  [ ! -f "$journal" ] || entries=$(jq -cs . "$journal")
  data=$(jq -cn --argjson entries "$entries" \
    --argjson host "$(generations "$host_profile")" \
    --argjson home "$(generations "$home_profile")" \
    '{journal: $entries, generations: {host: $host, home: $home}}')
  finish "$data" '
    (if .journal == [] then "no transactions yet" else
      (.journal[] | "\(.time)  \(.command)  \(if .ok then "ok" else "failed at \(.failedStep)" end)") end),
    "", "host generations: \([.generations.host[] | .generation] | map(tostring) | join(" "))",
    "home generations: \([.generations.home[] | .generation] | map(tostring) | join(" "))"'
}

cmd_check() {
  local mode=--full check_log passed=()
  [ "$#" -le 1 ] || usage "check takes one mode"
  [ "$#" -eq 0 ] || mode=$1
  case $mode in
  --docs | --fast | --full) ;;
  --vm) fail 4 "check --vm is not available before c1q15" ;;
  *) usage "unknown mode $mode" ;;
  esac
  need_flake
  cd "$flake"
  check_log=$(mktemp)
  # shellcheck disable=SC2064  # expand now: check_log is local
  trap "rm -f '$check_log'" EXIT

  # check_step <name> <command...>: logs to a temp file, its tail on failure.
  check_step() {
    local name=$1
    shift
    say "== $name"
    if ! "$@" >"$check_log" 2>&1; then
      tail -n 40 "$check_log" >&2
      fail 1 "check: $name failed"
    fi
    passed+=("$name")
  }

  # Lint every bash script under scripts/.
  # shellcheck disable=SC2329  # called through check_step
  shellcheck_scripts() {
    local file files=() sc=(shellcheck)
    while IFS= read -r file; do
      if [ "$(head -n 1 "$file")" = '#!/usr/bin/env bash' ]; then
        files+=("$file")
      fi
    done < <(git ls-files scripts)
    command -v shellcheck >/dev/null || sc=(nix run nixpkgs#shellcheck --)
    "${sc[@]}" "${files[@]}"
  }

  check_step docs scripts/lint-docs
  if git rev-parse -q --verify origin/main >/dev/null; then
    check_step commits scripts/lint-commits origin/main..HEAD
  fi
  check_step shellcheck shellcheck_scripts
  case $mode in
  --fast)
    # Evaluated, not built: `nix flake check --no-build` cannot, since
    # Hyprland's flake reads ${src}/VERSION (import-from-derivation).
    check_step eval nix eval --no-write-lock-file --json ".#checks.$(cfg .system)" \
      --apply 'builtins.mapAttrs (_: c: c.drvPath)'
    check_step host nix eval --no-write-lock-file --json .#nixosConfigurations \
      --apply 'builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath)'
    ;;
  --full)
    check_step flake nix flake check --no-write-lock-file
    ;;
  esac
  finish "$(jq -cn --arg mode "$mode" '{mode: $mode, steps: $ARGS.positional}' --args "${passed[@]}")" \
    '"check: ok (\(.mode))"'
}

cmd_switch() {
  local home=1 host=1 overwrite=false theme
  for arg; do
    case $arg in
    --home) host=0 ;;
    --host) home=0 ;;
    --overwrite) overwrite=true ;;
    *) usage "unknown argument $arg" ;;
    esac
  done
  ((home || host)) || usage "--home and --host exclude each other"
  need_flake
  theme=$(jq -r .theme "$state_file")
  local targets=()
  ((host)) && targets+=("$flake#nixosConfigurations.$(cfg .hostname).config.system.build.toplevel")
  ((home)) && targets+=("$flake#homeConfigurations.$(cfg .username)-$theme.activationPackage")
  plan build "nix build ${targets[*]}"
  plan diff "nvd diff of what changes"
  ((host)) && plan activate-host "switch-to-configuration switch, if the host differs from /run/current-system"
  if ((home)); then
    plan activate-home "activate home $(cfg .username)-$theme$([ "$overwrite" = false ] || echo ', moving clashing files aside')"
  fi
  planned "$(jq -cn --argjson host "$host" --argjson home "$home" --arg theme "$theme" \
    --argjson overwrite "$overwrite" \
    '{host: ($host == 1), home: ($home == 1), theme: $theme, overwrite: $overwrite}')"
}

cmd_update() {
  need_flake
  local inputs named held update
  inputs=$(jq -c '.nodes.root.inputs | keys' "$lock_file")
  named=$(jq -cn '$ARGS.positional' --args "$@")
  local unknown
  unknown=$(jq -rn --argjson inputs "$inputs" --argjson named "$named" '$named - $inputs | join(" ")')
  [ -z "$unknown" ] || usage "unknown inputs: $unknown"
  if [ "$#" -gt 0 ]; then
    update=$named held='[]'
  else
    held=$(cfg -c --argjson inputs "$inputs" '[.held[] | select(IN($inputs[]))]')
    update=$(jq -cn --argjson inputs "$inputs" --argjson held "$held" '$inputs - $held')
  fi
  [ "$held" = '[]' ] || warn "held, name them to update: $(jq -r 'join(" ")' <<<"$held")"
  plan snapshot "keep flake.lock to restore it byte for byte"
  plan update "nix flake update $(jq -r 'join(" ")' <<<"$update")"
  plan check "dangonix check"
  plan restore "on failure, put flake.lock back"
  planned "$(jq -cn --argjson update "$update" --argjson held "$held" '{update: $update, held: $held}')"
}

themes_json() {
  nix eval --no-write-lock-file --json "$flake#lib.themes" --apply \
    'r: builtins.mapAttrs (_: p: { inherit (p) name description; }) r.profiles'
}

cmd_theme() {
  need_flake
  local themes selected data
  themes=$(themes_json) || fail 1 "cannot evaluate $flake#lib.themes"
  selected=$(jq -r .theme "$state_file")
  data=$(jq -c --arg selected "$selected" --arg active "$(active_theme)" '
    to_entries | sort_by(.key) | map({id: .key, name: .value.name, description: .value.description,
      selected: (.key == $selected), active: (.key == $active)})' <<<"$themes")
  finish "$data" '(.[] | "\(if .selected then "*" else " " end)\(if .active then ">" else " " end) \(.id)  \(.description)"),
    "(* selected in state.json, > active)"'
}

cmd_theme_set() {
  [ "$#" -eq 1 ] || usage "theme takes one id"
  need_flake
  local themes from
  themes=$(themes_json) || fail 1 "cannot evaluate $flake#lib.themes"
  jq -e --arg id "$1" 'has($id)' <<<"$themes" >/dev/null ||
    usage "unknown theme '$1' (themes: $(jq -r 'keys | join(" ")' <<<"$themes"))"
  from=$(jq -r .theme "$state_file")
  plan state "state.json: theme $from -> $1"
  plan build "nix build $flake#homeConfigurations.$(cfg .username)-$1.activationPackage"
  plan activate-home "activate home $(cfg .username)-$1; the host stays as it is"
  planned "$(jq -cn --arg from "$from" --arg to "$1" '{from: $from, to: $to}')"
}

cmd_foundry_list() {
  no_args "$@"
  need_flake
  finish "$(foundry_instances)" '
    if . == [] then "no Foundry instance" else
      .[] | "\(.name)  \(.version)  :\(.port)  \(.state)  \(.url)" end'
}

cmd_foundry_status() {
  [ "$#" -le 1 ] || usage "foundry status takes at most one name"
  need_flake
  local only='null' data payloads='{}' file matches
  if [ "$#" -eq 1 ]; then
    instance "$1"
    only=$(jq -cn --arg name "$inst" '[$name]')
  fi
  # Whether the release ZIP of each version in state.json is in the store.
  shopt -s nullglob
  while IFS= read -r file; do
    matches=(/nix/store/*-"$file")
    payloads=$(jq -c --arg file "$file" --arg path "${matches[0]:-}" \
      '. + {($file): (if $path == "" then null else $path end)}' <<<"$payloads")
  done < <(cfg --slurpfile state "$state_file" '.foundry.versions as $v
    | [$state[0].foundry.instances[].version] | unique[] as $version
    | [$v[] | select(.version == $version)] | first | .file // empty')
  shopt -u nullglob
  data=$(jq -c --argjson only "$only" --argjson payloads "$payloads" \
    --slurpfile cfg "$DANGONIX_CONFIG" '
    map(select($only == null or (.name | IN($only[]))))
    | map(. as $i | ($cfg[0].foundry.versions | map(select(.version == $i.version)) | first) as $entry
      | . + {payload: (if $entry == null then null else $payloads[$entry.file] end)})' \
    <<<"$(foundry_instances)")
  finish "$data" '
    if . == [] then "no Foundry instance" else .[] |
      "\(.name)",
      "  version   \(.version) on :\(.port)"
        + (if .deployed == null then " (not deployed)"
           else " (running \(.deployed.version) on :\(.deployed.port // "?"))" end),
      "  service   \(.service): \(.state)",
      "  url       \(.url)",
      "  payload   \(.payload // "missing from the store: dangonix foundry import <zip>")" end'
}

cmd_foundry_logs() {
  local follow=0 name="" service
  for arg; do
    case $arg in
    -f) follow=1 ;;
    -*) usage "unknown flag $arg" ;;
    *)
      [ -z "$name" ] || usage "foundry logs takes at most one name"
      name=$arg
      ;;
    esac
  done
  need_flake
  instance "$name"
  service=$(cfg .foundry.service)
  if ((follow)); then
    ((!json)) || usage "-f does not go with --json"
    exec journalctl --unit "$service" --follow --lines 50
  fi
  if ((json)); then
    finish "$(journalctl --unit "$service" --lines 200 --output json --no-pager |
      jq -cs --arg name "$inst" '{name: $name, lines: map({
        time: (.__REALTIME_TIMESTAMP | tonumber / 1000000 | floor | todate),
        message: (.MESSAGE | if type == "array" then implode else . end)})}')" .
  fi
  exec journalctl --unit "$service" --lines 200 --no-pager
}

# cmd_foundry_runtime <start|stop|restart|open> [<name>]
cmd_foundry_runtime() {
  local verb=$1 service url systemctl
  shift
  [ "$#" -le 1 ] || usage "foundry $verb takes at most one name"
  need_flake
  instance "${1:-}"
  service=$(cfg .foundry.service)
  url=$(jq -r --arg name "$inst" '"http://127.0.0.1:\(.foundry.instances[$name].port)"' "$state_file")
  systemctl=$(command -v systemctl)
  local active=0
  systemctl is-active --quiet "$service" && active=1
  case $verb in
  open)
    ((active)) || plan start "sudo systemctl start $service"
    plan open "xdg-open $url"
    ;;
  *) plan "$verb" "sudo systemctl $verb $service" ;;
  esac
  local data
  data=$(jq -cn --arg name "$inst" --arg service "$service" --arg url "$url" \
    '{name: $name, service: $service, url: $url}')
  planned "$data"
  case $verb in
  open)
    ((active)) || run_step start "$sudo" "$systemctl" start "$service"
    run_step open xdg-open "$url"
    ;;
  *) run_step "$verb" "$sudo" "$systemctl" "$verb" "$service" ;;
  esac
  finish "$data" '"foundry \(.name): \($steps | map(.name) | join(", ")) done"'
}

cmd_foundry_import() {
  [ "$#" -eq 1 ] || usage "foundry import takes one ZIP"
  need_flake
  zip_info "$1"
  local users
  users=$(jq -c --arg version "$zip_version" \
    '[.foundry.instances | to_entries[] | select(.value.version == $version) | .key]' "$state_file")
  [ "$users" != '[]' ] ||
    usage "no instance in state.json uses $zip_version (dangonix foundry add or upgrade)"
  plan_import
  planned "$(jq -cn --arg zip "$zip_path" --arg version "$zip_version" --argjson instances "$users" \
    '{zip: $zip, version: $version, instances: $instances}')"
}

cmd_foundry_upgrade() {
  local backed_up=0 args=()
  for arg; do
    case $arg in
    --backed-up) backed_up=1 ;;
    -*) usage "unknown flag $arg" ;;
    *) args+=("$arg") ;;
    esac
  done
  need_flake
  case ${#args[@]} in
  1) instance ;;
  2) instance "${args[0]}" ;;
  *) usage "foundry upgrade takes [<name>] <zip>" ;;
  esac
  zip_info "${args[-1]}"
  local from
  from=$(jq -r --arg name "$inst" '.foundry.instances[$name].version' "$state_file")
  [ "$from" != "$zip_version" ] || fail 4 "foundry $inst is already at $zip_version"
  if [ "${from%%.*}" != "${zip_version%%.*}" ] && ! ((backed_up)); then
    fail 4 "foundry $inst: $from -> $zip_version crosses a major version; back up its data, then add --backed-up"
  fi
  plan_import
  plan state "state.json: foundry $inst version $from -> $zip_version"
  plan_host_switch
  planned "$(jq -cn --arg name "$inst" --arg from "$from" --arg to "$zip_version" --arg zip "$zip_path" \
    '{name: $name, from: $from, to: $to, zip: $zip}')"
}

cmd_foundry_add() {
  local port=30000 args=()
  while [ "$#" -gt 0 ]; do
    case $1 in
    --port)
      [ "$#" -ge 2 ] || usage "--port needs a number"
      port=$2
      shift
      ;;
    -*) usage "unknown flag $1" ;;
    *) args+=("$1") ;;
    esac
    shift
  done
  [ "${#args[@]}" -eq 2 ] || usage "foundry add takes <name> <zip>"
  [[ ${args[0]} =~ ^[a-z0-9-]+$ ]] || usage "instance names are [a-z0-9-]+"
  if ! [[ $port =~ ^[0-9]+$ ]] || ((port == 0 || port > 65535)); then
    usage "--port takes a port number"
  fi
  need_flake
  local existing
  existing=$(jq -r '.foundry.instances | keys | join(" ")' "$state_file")
  [ -z "$existing" ] ||
    fail 4 "state.json already has Foundry instance $existing; several instances arrive in campaign II"
  zip_info "${args[1]}"
  plan_import
  plan state "state.json: foundry instance ${args[0]}, version $zip_version, port $port"
  plan_host_switch
  planned "$(jq -cn --arg name "${args[0]}" --arg version "$zip_version" --argjson port "$port" \
    --arg zip "$zip_path" '{name: $name, version: $version, port: $port, zip: $zip}')"
}

cmd_foundry_remove() {
  [ "$#" -eq 1 ] || usage "foundry remove takes one name"
  need_flake
  instance "$1"
  plan state "state.json: drop foundry instance $inst"
  plan_host_switch
  planned "$(jq -cn --arg name "$inst" '{name: $name, data: "stays on disk"}')"
}

# --- main -------------------------------------------------------------------

# shellcheck disable=SC2034  # metered_ok, as above
while [ "$#" -gt 0 ]; do
  case $1 in
  --json) json=1 ;;
  --dry) dry=1 ;;
  --yes) yes=1 ;;
  --metered-ok) metered_ok=1 ;;
  --flake)
    [ "$#" -ge 2 ] || usage "--flake needs a path"
    flake=$2
    shift
    ;;
  --flake=*) flake=${1#--flake=} ;;
  --help | -h)
    shift
    set -- help "$@"
    break
    ;;
  -*) usage "unknown global flag $1 (global flags go before the command)" ;;
  *) break ;;
  esac
  shift
done

# `<command> ... --help` is `help <command> ...`.
for arg; do
  if [ "$arg" = --help ] || [ "$arg" = -h ]; then
    words=()
    for word; do
      [ "$word" = "$arg" ] && break
      [[ $word == -* ]] || words+=("$word")
    done
    set -- help "${words[@]}"
    break
  fi
done

noun=${1:-}
[ "$#" -eq 0 ] || shift
case $noun in
"")
  bare=1
  use status
  cmd_status "$@"
  ;;
status | help | commands | version | history | check | switch | update)
  use "$noun"
  "cmd_$noun" "$@"
  ;;
theme)
  if [ "$#" -eq 0 ]; then
    use theme
    cmd_theme
  else
    use theme-set
    cmd_theme_set "$@"
  fi
  ;;
foundry)
  verb=${1:-list}
  [ "$#" -eq 0 ] || shift
  case $verb in
  list | status | logs | import | upgrade | add | remove)
    use "foundry-$verb"
    "cmd_foundry_$verb" "$@"
    ;;
  start | stop | restart | open)
    use "foundry-$verb"
    cmd_foundry_runtime "$verb" "$@"
    ;;
  *)
    command_name=foundry
    usage "unknown foundry command '$verb'"
    ;;
  esac
  ;;
*) usage "unknown command '$noun'" ;;
esac
