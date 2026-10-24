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
# A state or host command plans its steps; with --dry it prints the plan,
# without it runs the plan as a transaction (see "transactions" below).

# The original arguments, for the re-exec in execute.
orig_args=("$@")

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
# The command's arguments, for the journal.
cmd_args='[]'

# The transaction (see "transactions" below).
planned_done=0
tx_running=0 # holds the lock: a failure writes the journal line
tx_open=0    # a snapshot exists: a failure recovers from it
tx_edit='.'  # the jq filter step_state applies to state.json
tx_edit_args=()
tx_host=0 tx_home=0 tx_theme="" tx_overwrite=0
tx_update='[]' # the inputs step_update updates
snapshot_dir="" keep_snapshot=0
host_before="" home_before="" built_host="" built_home=""
host_activated=0 home_activated=0
step_status="" step_error=""
manual=()
zip_path="" zip_file="" zip_store=""

sudo=/run/wrappers/bin/sudo
nix_env=$(command -v nix-env)

cfg() { jq -r "$@" "$DANGONIX_CONFIG"; }
log() { printf '%s\n' "$*" >&2; }
warn() {
  warnings+=("$1")
  log "dangonix: warning: $1"
}
# json_list <word...>: a JSON array of the words (jq --args would read
# a word such as --fast as its own option).
json_list() {
  local word list='[]'
  for word; do list=$(jq -c --arg word "$word" '. + [$word]' <<<"$list"); done
  echo "$list"
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
# Inside a transaction it first recovers (exit 3 when that fails) and writes
# the journal line.
fail() {
  local code=$1 message=$2
  trap '' INT TERM
  if ((tx_open)); then
    tx_open=0
    recovered=true
    if ! recover; then
      code=3 recovered=false
      message+="; recovery failed, finish by hand: $(printf '%s; ' "${manual[@]}")"
    fi
  fi
  if ((tx_running)); then
    tx_running=0
    journal_write "$code" || warn "cannot write the journal $journal"
  fi
  [ -z "$log_file" ] || message+=" (log: $log_file)"
  log "dangonix: $message"
  if ((json)); then
    envelope "$code" "$(jq -cn --arg error "$message" '{error: $error, manual: $ARGS.positional}' \
      --args "${manual[@]}")"
  fi
  exit "$code"
}

usage() { fail 2 "$1 (see: dangonix help${command_name:+ $command_name})"; }

# no_args <args...>: the command takes none.
no_args() { [ "$#" -eq 0 ] || usage "$command_name takes no arguments"; }

# plan <name> <detail>: the next step of a mutation.
plan() {
  steps=$(jq -c --arg name "$1" --arg detail "$2" \
    '. + [{name: $name, detail: $detail, status: "planned"}]' <<<"$steps")
}

# planned <data>: planning is over. With --dry print the plan and exit;
# otherwise the command goes on to run it.
planned() {
  if ((dry)); then
    finish "$1" '"dangonix --dry: would", ($steps | to_entries[] | "  \(.key + 1). \(.value.name): \(.value.detail)")'
  fi
  planned_done=1
}

# run_step <name> <command...>: run a planned step; its output goes to stderr.
# The command may set step_status (e.g. skipped) and step_error (the message).
run_step() {
  local name=$1 status="done"
  shift
  ((planned_done)) || fail 2 "$command_name: step $name runs before the plan is made"
  step_status="" step_error=""
  "$@" >&2 || status=failed
  [ "$status" = failed ] || status=${step_status:-done}
  steps=$(jq -c --arg name "$name" --arg status "$status" \
    'map(if .name == $name then .status = $status else . end)' <<<"$steps")
  if [ "$status" = failed ]; then
    failed_step=$(jq -cn --arg name "$name" '$name')
    fail 1 "$command_name: ${step_error:-step $name failed}"
  fi
}

# steps_text: the jq filter that renders a finished mutation.
steps_text='$steps[] | "\(.status)\t\(.name): \(.detail)"'

# enter_scope: unless DANGONIX_SCOPE is set, re-run this command line in its
# own user scope (dangonix-<pid>), so the transaction leaves the caller's
# cgroup: when the terminal, or the user unit it lives in (caelestia.service),
# dies halfway, systemd does not take the transaction with it. A scope keeps
# the TTY. Called before anything asks the user, so a question is asked once.
enter_scope() {
  [ -z "${DANGONIX_SCOPE:-}" ] || return 0
  if systemd-run --user --scope --quiet --collect -- true 2>/dev/null; then
    DANGONIX_SCOPE=1 exec systemd-run --user --scope --quiet --collect \
      --unit="dangonix-$$" -- "$0" "${orig_args[@]}"
  fi
  DANGONIX_SCOPE=none
  warn "no systemd user manager: the transaction runs in the caller's cgroup"
}

# confirm_plan: an irreversible step asks y/N on a TTY and needs --yes without.
confirm_plan() {
  if ! ((yes)) && ! [ -t 0 ]; then
    warn "the import is irreversible: without a TTY it needs --yes"
  fi
}

# confirm <what>: before an irreversible step runs, y/N on a TTY, else --yes.
confirm() {
  local answer=""
  enter_scope
  if ((yes)); then return 0; fi
  [ -t 0 ] || fail 4 "$command_name: $1 is irreversible: without a TTY it needs --yes"
  read -r -p "dangonix: $1 is irreversible. Go on? [y/N] " answer || true
  case $answer in
  y | Y | yes | YES) ;;
  *) fail 4 "$command_name: cancelled" ;;
  esac
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

log_file=""
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}
journal=$state_dir/dangonix/journal.jsonl
host_profile=/nix/var/nix/profiles/system
# The profile Home Manager uses: the XDG one, else the legacy per-user one.
home_profile=$state_dir/nix/profiles/home-manager
legacy_profiles=/nix/var/nix/profiles/per-user/$(id -un)
if [ ! -d "${home_profile%/*}" ] && [ -d "$legacy_profiles" ]; then
  home_profile=$legacy_profiles/home-manager
fi

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
  zip_store=$(jq -r .path <<<"$entry")
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

step_import() {
  local stored
  stored=$(nix-store --add-fixed sha256 "$zip_path") || return 1
  if [ "$stored" != "$zip_store" ]; then
    step_error="nix-store put $zip_file at $stored, not at $zip_store"
    return 1
  fi
}

step_gc_root() {
  mkdir -p "$HOME/FoundryVTT/gcroots" &&
    nix-store --add-root "$HOME/FoundryVTT/gcroots/$zip_file" --realise "$zip_store" >/dev/null
}

plan_host_switch() {
  tx_host=1
  plan_preflight
  plan state "$1"
  plan build "nix build $(host_target)"
  plan diff "nvd diff /run/current-system and the new host"
  plan activate-host "nix-env --set the system profile, switch-to-configuration switch, if the host changed"
}

# --- transactions -----------------------------------------------------------
#
# A state or host command plans its steps (design 5, "Транзакції"); without
# --dry, execute runs them in order under one lock, step <name> being the
# function step_<name>. The snapshot step opens the transaction: from then on
# a failing step (fail) puts state.json and flake.lock back byte for byte,
# re-activates the host and home generations it replaced and writes the
# journal line; exit 3 when that recovery fails. A build failure activates
# nothing; theme never builds the host.

host_target() { echo "$flake#nixosConfigurations.$(cfg .hostname).config.system.build.toplevel"; }
home_target() { echo "$flake#homeConfigurations.$(cfg .username)-$tx_theme.activationPackage"; }

plan_snapshot() {
  plan snapshot "keep state.json and flake.lock (to put back byte for byte on failure) and the host and home generations"
}

# Planned wherever the host gets built (switch, update's check, foundry);
# theme builds only home, so a missing ZIP never blocks it.
plan_preflight() {
  plan preflight "the release ZIP of every Foundry instance in state.json is in the store"
}

# execute: take the lock and run the plan (in its own scope, see enter_scope).
execute() {
  local name names
  enter_scope
  tx_begin
  names=$(jq -r '.[].name' <<<"$steps")
  for name in $names; do
    run_step "$name" "step_${name//-/_}"
  done
  tx_end
}

# tx_begin: refuse (exit 4) unless the user is right and the lock is free.
# The lock is kit-profile's, so the two never activate home at once.
tx_begin() {
  local user lock
  user=$(id -un)
  [ "$user" = "$(cfg .username)" ] || fail 4 "$command_name runs as $(cfg .username), not as $user"
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    lock=$XDG_RUNTIME_DIR/kit-home-activation.lock
  else
    mkdir -p "$state_dir/kit"
    chmod 700 "$state_dir/kit"
    lock=$state_dir/kit/home-activation.lock
  fi
  exec 9>"$lock"
  flock -n 9 || fail 4 "another dangonix or kit-profile run holds $lock"
  tx_running=1
  # A closed terminal must neither stop the transaction (SIGHUP is inherited
  # by activate and switch-to-configuration) nor lose its log.
  trap '' HUP
  mkdir -p "$state_dir/dangonix"
  log_file=$state_dir/dangonix/last.log
  exec 2> >(tee --output-error=warn "$log_file" >&2)
}

# tx_end: the transaction is done: journal line, then the diff it leaves.
tx_end() {
  if ! journal_write 0; then
    failed_step='"journal"'
    fail 1 "$command_name: cannot write the journal $journal"
  fi
  tx_open=0
  tx_running=0
  flock -u 9
  git -C "$flake" --no-pager diff --stat -- state.json flake.lock >&2 || true
  git -C "$flake" --no-pager diff -- state.json >&2 || true
}

# journal_write <exit>: one line in the journal (history and rollback read it).
journal_write() {
  local host_now="" home_now=""
  host_now=$(readlink -f /run/current-system || true)
  [ ! -e "$home_profile" ] || home_now=$(readlink -f "$home_profile" || true)
  mkdir -p "${journal%/*}" || return 1
  jq -cn --arg time "$(date -u +%FT%TZ)" --arg command "$command_name" --argjson args "$cmd_args" \
    --argjson exit "$1" --argjson failed "$failed_step" --argjson recovered "$recovered" \
    --arg flake "$flake" --arg host_before "$host_before" --arg host_now "$host_now" \
    --arg home_before "$home_before" --arg home_now "$home_now" \
    --argjson host_gen "$(current_generation "$host_profile")" \
    --argjson home_gen "$(current_generation "$home_profile")" '
    def path: if . == "" then null else . end;
    {time: $time, command: $command, args: $args, ok: ($exit == 0), exit: $exit,
     failedStep: $failed, recovered: $recovered, flake: $flake,
     host: {before: ($host_before | path), after: ($host_now | path), generation: $host_gen},
     home: {before: ($home_before | path), after: ($home_now | path), generation: $home_gen}}' \
    >>"$journal"
}

# same_file <a> <b>: byte for byte equal.
same_file() { [ "$(sha256sum <"$1")" = "$(sha256sum <"$2")" ]; }

# restore_files: state.json and flake.lock as the snapshot has them.
restore_files() {
  local file kept
  for file in "$state_file" "$lock_file"; do
    kept=$snapshot_dir/${file##*/}
    same_file "$kept" "$file" 2>/dev/null && continue
    log "dangonix: putting back ${file##*/}"
    if ! { cp "$kept" "$file" && same_file "$kept" "$file"; }; then
      keep_snapshot=1
      manual+=("cp $kept $file")
      return 1
    fi
  done
}

# recover: undo a failed transaction: the files, then (best effort) the host
# and home generations it replaced. Fails when something is left to do by
# hand, listed in manual.
recover() {
  local ok=0
  restore_files || ok=1
  if ((host_activated)); then
    log "dangonix: re-activating the host $host_before"
    if ! { "$sudo" "$nix_env" -p "$host_profile" --set "$host_before" &&
      "$sudo" "$host_before/bin/switch-to-configuration" switch; } >&2; then
      ok=1
      manual+=("sudo nix-env -p $host_profile --set $host_before"
        "sudo $host_before/bin/switch-to-configuration switch")
    fi
  fi
  if ((home_activated)); then
    if [ -z "$home_before" ]; then
      # Nothing to go back to: drop the profile generation this created.
      local generation
      if generation=$(readlink "$home_profile" 2>/dev/null); then
        rm -f "$home_profile" "${home_profile%/*}/$generation"
      fi
      ok=1
      manual+=("there was no home generation to go back to: fix the error, then dangonix switch --home")
    else
      log "dangonix: re-activating home $home_before"
      # Home Manager removes the files of the generation it replaces, which it
      # reads from this root; the failed activation left it on home_before, so
      # without this the new generation's links outlive the recovery.
      if [ -n "$built_home" ] && [ "$built_home" != "$home_before" ]; then
        nix-store --realise "$built_home" \
          --add-root "${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots/current-home" >/dev/null 2>&1 || true
      fi
      if ! { "$nix_env" --profile "$home_profile" --set "$home_before" &&
        "$home_before/activate" --driver-version 1; } >&2; then
        ok=1
        manual+=("nix-env --profile $home_profile --set $home_before"
          "$home_before/activate --driver-version 1")
      fi
    fi
  fi
  return "$ok"
}

# on_exit: an exit fail did not see (set -e) still puts the files back.
on_exit() {
  if ((tx_open)); then
    restore_files || log "dangonix: restore by hand: ${manual[*]}"
  fi
  if [ -n "$snapshot_dir" ] && ! ((keep_snapshot)); then
    rm -rf "$snapshot_dir"
  fi
}

step_snapshot() {
  snapshot_dir=$(mktemp -d) &&
    cp "$state_file" "$lock_file" "$snapshot_dir/" || return 1
  host_before=$(readlink -f /run/current-system || true)
  [ ! -e "$home_profile" ] || home_before=$(readlink -f "$home_profile")
  tx_open=1
  echo "snapshot: state.json $(sha256sum <"$state_file" | cut -d ' ' -f 1)," \
    "flake.lock $(sha256sum <"$lock_file" | cut -d ' ' -f 1)"
}

# step_preflight: the release ZIP of every instance in state.json, as this
# transaction leaves it, is in the store.
step_preflight() {
  local rows name version file path
  rows=$(jq -r --slurpfile cfg "$DANGONIX_CONFIG" "${tx_edit_args[@]}" "($tx_edit)"'
    | .foundry.instances | to_entries[] | .value.version as $v
    | ([$cfg[0].foundry.versions[] | select(.version == $v)] | first) as $e
    | [.key, $v, ($e.file // "-"), ($e.path // "-")] | join(" ")' "$state_file") || return 1
  while read -r name version file path; do
    [ -n "$name" ] || continue
    if [ "$file" = - ]; then
      step_error="foundry $name: version $version is not in nix-foundryvtt's version table"
      return 1
    fi
    if [ ! -e "$path" ]; then
      step_error="foundry $name: the release ZIP of $version is not in the store: dangonix foundry import $file"
      return 1
    fi
  done <<<"$rows"
}

# step_state: apply tx_edit to state.json (temp file and atomic rename).
step_state() {
  local tmp
  tmp=$(mktemp "$state_file.XXXXXX") || return 1
  if jq "${tx_edit_args[@]}" "$tx_edit" "$state_file" >"$tmp" &&
    chmod --reference="$state_file" "$tmp" && mv "$tmp" "$state_file"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# step_build: every side the transaction touches, in one nix build.
step_build() {
  local targets=() out
  if ((tx_host)); then targets+=("$(host_target)"); fi
  if ((tx_home)); then targets+=("$(home_target)"); fi
  out=$(nix build --no-link --no-write-lock-file --json "${targets[@]}") || return 1
  if ((tx_host)); then built_host=$(jq -r '.[0].outputs.out' <<<"$out"); fi
  if ((tx_home)); then built_home=$(jq -r '.[-1].outputs.out' <<<"$out"); fi
}

# step_diff: what changes (nvd diff); informational, it never fails the
# transaction.
step_diff() {
  if ((tx_host)) && [ -n "$host_before" ]; then
    echo "host:"
    nvd diff "$host_before" "$built_host" || true
  fi
  if ((tx_home)) && [ -n "$home_before" ]; then
    echo "home:"
    nvd diff "$home_before" "$built_home" || true
  fi
  return 0
}

step_activate_host() {
  if [ "$built_host" = "$host_before" ]; then
    echo "the host is unchanged"
    step_status=skipped
    return 0
  fi
  host_activated=1
  "$sudo" "$nix_env" -p "$host_profile" --set "$built_host" &&
    "$sudo" "$built_host/bin/switch-to-configuration" switch
}

# step_activate_home: dangonix sets the profile, so the driver version is 1.
step_activate_home() {
  home_activated=1
  mkdir -p "${home_profile%/*}" || return 1
  if [ "$built_home" != "$home_before" ]; then
    "$nix_env" --profile "$home_profile" --set "$built_home" || return 1
  fi
  if ((tx_overwrite)); then
    HOME_MANAGER_BACKUP_EXT=dangonix-backup "$built_home/activate" --driver-version 1
  else
    "$built_home/activate" --driver-version 1
  fi
}

step_update() {
  local inputs=()
  mapfile -t inputs < <(jq -r '.[]' <<<"$tx_update")
  nix flake update --flake "$flake" "${inputs[@]}"
}

step_check() { "$0" --flake "$flake" check; }

step_firmware_update() {
  if ((yes)); then
    fwupdmgr update --assume-yes
  else
    fwupdmgr update
  fi
}

# --- commands ---------------------------------------------------------------

cmd_status() {
  no_args "$@"
  need_flake
  local data text look_file="${XDG_CONFIG_HOME:-$HOME/.config}/dangonix/look.json" look_json=null mode=null scheme
  if [ -f "$look_file" ]; then
    look_json=$(jq -c . "$look_file" 2>/dev/null || echo null)
  fi
  if scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null); then
    case $scheme in
    "'prefer-dark'") mode='"dark"' ;;
    *) mode='"light"' ;;
    esac
  fi
  data=$(jq -cn --arg selected "$(jq -r .theme "$state_file")" --arg active "$(active_theme)" \
    --argjson foundry "$(foundry_instances)" \
    --argjson lookfile "$look_json" --argjson mode "$mode" '{
      theme: {selected: $selected, active: (if $active == "" then null else $active end)},
      foundry: $foundry,
      look: {appearance: $lookfile.appearance, theme: $lookfile.theme, mode: $mode},
      built: ($selected == $active
        and ($foundry | all(.deployed == {version: .version, port: .port})))}')
  text='
    "theme     \(.theme.selected) (active: \(.theme.active // "none"))",
    (if .look.appearance == null then "look      unknown"
     else "look      \(.look.mode // "unknown") (\(if .look.appearance == "shell" then "set" else "fixed" end) by \(.look.theme))" end),
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
      (.journal[] | "\(.time)  \(([.command] + (.args // [])) | join(" "))  \(if .ok then "ok"
        else "failed at \(.failedStep)\(if .recovered == false then ", not recovered" else "" end)" end)") end),
    "", "host generations: \([.generations.host[] | .generation] | map(tostring) | join(" "))",
    "home generations: \([.generations.home[] | .generation] | map(tostring) | join(" "))"'
}

cmd_check() {
  local mode=--full check_log passed=()
  [ "$#" -le 1 ] || usage "check takes one mode"
  [ "$#" -eq 0 ] || mode=$1
  case $mode in
  --docs | --fast | --full | --vm) ;;
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
  --vm)
    # Not in `nix flake check`: it boots a VM (tests/dangonix-vm).
    check_step vm nix build --no-link --no-write-lock-file ".#dangonix-vm"
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
  tx_host=$host tx_home=$home tx_theme=$theme
  [ "$overwrite" = false ] || tx_overwrite=1
  local targets=()
  ((host)) && targets+=("$(host_target)")
  ((home)) && targets+=("$(home_target)")
  # A dry run evaluates what would be built and says whether it changes.
  local change='{}' side out current changed
  if ((dry)); then
    for side in host home; do
      if [ "$side" = host ]; then
        ((host)) || continue
        current=/run/current-system
      else
        ((home)) || continue
        current=$home_profile
      fi
      out=$(nix eval --no-write-lock-file --raw "$("${side}_target").outPath") ||
        fail 1 "cannot evaluate the $side"
      changed=true
      [ "$out" != "$(readlink -f "$current" 2>/dev/null || true)" ] || changed=false
      change=$(jq -c --arg side "$side" --argjson changed "$changed" '. + {($side): $changed}' <<<"$change")
    done
  fi
  plan_snapshot
  ((host)) && plan_preflight
  plan build "nix build ${targets[*]}"
  plan diff "$(jq -r 'if . == {} then "nvd diff of what changes"
    else to_entries | map("\(.key): \(if .value then "changes" else "no change" end)") | join(", ") end' <<<"$change")"
  ((host)) && plan activate-host "nix-env --set the system profile, switch-to-configuration switch, if the host differs from /run/current-system"
  if ((home)); then
    plan activate-home "nix-env --set the home profile, activate $(cfg .username)-$theme$([ "$overwrite" = false ] || echo ', moving clashing files aside')"
  fi
  local data
  data=$(jq -cn --argjson host "$host" --argjson home "$home" --arg theme "$theme" \
    --argjson overwrite "$overwrite" --argjson change "$change" \
    '{host: ($host == 1), home: ($home == 1), theme: $theme, overwrite: $overwrite}
      + (if $change == {} then {} else {change: $change} end)')
  planned "$data"
  execute
  finish "$data" "$steps_text"
}

cmd_update() {
  need_flake
  local inputs named excluded held update arg
  local -a names=() skips=()
  inputs=$(jq -c '.nodes.root.inputs | keys' "$lock_file")
  for arg; do
    case $arg in
    -?*) skips+=("${arg#-}") ;;
    *) names+=("$arg") ;;
    esac
  done
  [ "${#names[@]}" -eq 0 ] || [ "${#skips[@]}" -eq 0 ] ||
    usage "name inputs to update or -<input> to skip them, not both"
  named=$(json_list "${names[@]}")
  excluded=$(json_list "${skips[@]}")
  local unknown
  unknown=$(jq -rn --argjson inputs "$inputs" --argjson named "$named" --argjson excluded "$excluded" \
    '($named + $excluded) - $inputs | join(" ")')
  [ -z "$unknown" ] || usage "unknown inputs: $unknown"
  if [ "${#names[@]}" -gt 0 ]; then
    update=$named held='[]'
  else
    held=$(cfg -c --argjson inputs "$inputs" --argjson excluded "$excluded" \
      '[.held[] | select(IN($inputs[])) | select(IN($excluded[]) | not)]')
    update=$(jq -cn --argjson inputs "$inputs" --argjson held "$held" --argjson excluded "$excluded" \
      '$inputs - $held - $excluded')
  fi
  [ "$update" != '[]' ] || usage "nothing left to update"
  [ "$held" = '[]' ] || warn "held, name them to update: $(jq -r 'join(" ")' <<<"$held")"
  tx_update=$update
  plan_snapshot
  plan_preflight
  plan update "nix flake update $(jq -r 'join(" ")' <<<"$update")"
  plan check "dangonix check; on failure flake.lock goes back byte for byte"
  planned "$(jq -cn --argjson update "$update" --argjson held "$held" --argjson excluded "$excluded" '{update: $update, held: $held, excluded: $excluded}')"
  execute
  # The inputs whose lock changed.
  local changed
  changed=$(jq -cn --slurpfile old "$snapshot_dir/flake.lock" --slurpfile new "$lock_file" '
    ($old[0].nodes) as $o | ($new[0].nodes) as $n
    | [$n.root.inputs | keys[] | select($o[$o.root.inputs[.]].locked != $n[$n.root.inputs[.]].locked)]')
  finish "$(jq -cn --argjson update "$update" --argjson held "$held" --argjson excluded "$excluded" --argjson changed "$changed" \
    '{update: $update, held: $held, excluded: $excluded, changed: $changed}')" \
    '"updated: \(.changed | join(" ") | if . == "" then "nothing changed" else . end)",
     (if .held == [] then empty else "held: \(.held | join(" "))" end),
     (if .excluded == [] then empty else "excluded: \(.excluded | join(" "))" end)'
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
  tx_edit='.theme = $id' tx_edit_args=(--arg id "$1") tx_home=1 tx_theme=$1
  plan_snapshot
  plan state "state.json: theme $from -> $1"
  plan build "nix build $(home_target)"
  plan diff "nvd diff of the home profile and the new home"
  plan activate-home "nix-env --set the home profile, activate $(cfg .username)-$1; the host stays as it is"
  local data
  data=$(jq -cn --arg from "$from" --arg to "$1" '{from: $from, to: $to}')
  planned "$data"
  execute
  finish "$data" "$steps_text"
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

cmd_foundry_start() {
  cmd_foundry_runtime start "$@"
}

cmd_foundry_stop() {
  cmd_foundry_runtime stop "$@"
}

cmd_foundry_restart() {
  cmd_foundry_runtime restart "$@"
}

cmd_foundry_open() {
  cmd_foundry_runtime open "$@"
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
  local data
  data=$(jq -cn --arg zip "$zip_path" --arg version "$zip_version" --argjson instances "$users" \
    --arg path "$zip_store" '{zip: $zip, version: $version, instances: $instances, path: $path}')
  planned "$data"
  confirm "importing $zip_file"
  execute
  finish "$data" "$steps_text"
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
  tx_edit='.foundry.instances[$name].version = $version'
  tx_edit_args=(--arg name "$inst" --arg version "$zip_version")
  plan_snapshot
  plan_import
  plan_host_switch "state.json: foundry $inst version $from -> $zip_version"
  local data
  data=$(jq -cn --arg name "$inst" --arg from "$from" --arg to "$zip_version" --arg zip "$zip_path" \
    '{name: $name, from: $from, to: $to, zip: $zip}')
  planned "$data"
  confirm "importing $zip_file"
  execute
  finish "$data" "$steps_text"
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
  tx_edit='.foundry.instances[$name] = {version: $version, port: $port}'
  tx_edit_args=(--arg name "${args[0]}" --arg version "$zip_version" --argjson port "$port")
  plan_snapshot
  plan_import
  plan_host_switch "state.json: foundry instance ${args[0]}, version $zip_version, port $port"
  local data
  data=$(jq -cn --arg name "${args[0]}" --arg version "$zip_version" --argjson port "$port" \
    --arg zip "$zip_path" '{name: $name, version: $version, port: $port, zip: $zip}')
  planned "$data"
  confirm "importing $zip_file"
  execute
  finish "$data" "$steps_text"
}

cmd_foundry_remove() {
  [ "$#" -eq 1 ] || usage "foundry remove takes one name"
  need_flake
  instance "$1"
  tx_edit='del(.foundry.instances[$name])' tx_edit_args=(--arg name "$inst")
  plan_snapshot
  plan_host_switch "state.json: drop foundry instance $inst"
  local data
  data=$(jq -cn --arg name "$inst" '{name: $name, data: "stays on disk"}')
  planned "$data"
  execute
  finish "$data" "$steps_text"
}

# cmd_firmware [--refresh]: devices and updates; the metadata is refreshed
# only when its stamp is older than 24 h (nothing runs in the background).
cmd_firmware() {
  local refresh=0 refreshed=false stamp devices updates
  for arg; do
    case $arg in
    --refresh) refresh=1 ;;
    *) usage "firmware takes only --refresh" ;;
    esac
  done
  stamp=$state_dir/dangonix/firmware-refresh
  if ((refresh)) || [ -z "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
    # fwupdmgr exits 2 when the metadata is already current.
    fwupdmgr refresh --force >&2 || [ "$?" -eq 2 ] || warn "fwupdmgr refresh failed"
    mkdir -p "${stamp%/*}" && touch "$stamp"
    refreshed=true
  fi
  devices=$(fwupdmgr get-devices --json 2>/dev/null || echo '{}')
  # fwupdmgr exits 2 when there is nothing to update.
  updates=$(fwupdmgr get-updates --json 2>/dev/null || echo '{}')
  finish "$(jq -cn --argjson refreshed "$refreshed" --argjson devices "$devices" --argjson updates "$updates" \
    '{refreshed: $refreshed, devices: ($devices.Devices // []), updates: ($updates.Devices // [])}')" '
    "metadata \(if .refreshed then "refreshed" else "fresh (under 24 h)" end)",
    "devices:",
    (.devices[] | "  \(.Name // "?")  \(.Version // "?")"),
    (if .updates == [] then "no updates" else
      "updates:", (.updates[] | "  \(.Name // "?")  \(.Version // "?") -> \(.Releases[0].Version // "?")") end)'
}

# cmd_firmware_update: fwupdmgr update; a firmware flash cannot be undone.
cmd_firmware_update() {
  no_args "$@"
  need_flake
  plan firmware-update "fwupdmgr update"
  local data='{}'
  planned "$data"
  confirm "firmware update"
  execute
  finish "$data" "$steps_text"
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

trap on_exit EXIT
trap 'fail 1 "${command_name:-dangonix}: interrupted"' INT TERM

noun=${1:-}
[ "$#" -eq 0 ] || shift
cmd_args=$(json_list "$@")
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
firmware)
  if [ "${1:-}" = update ]; then
    shift
    use firmware-update
    cmd_args=$(json_list "$@")
    cmd_firmware_update "$@"
  else
    use firmware
    cmd_firmware "$@"
  fi
  ;;
foundry)
  verb=${1:-list}
  [ "$#" -eq 0 ] || shift
  case $verb in
  list | status | logs | import | upgrade | add | remove | start | stop | restart | open)
    use "foundry-$verb"
    cmd_args=$(json_list "$@")
    "cmd_foundry_$verb" "$@"
    ;;
  *)
    command_name=foundry
    usage "unknown foundry command '$verb'"
    ;;
  esac
  ;;
*) usage "unknown command '$noun'" ;;
esac
