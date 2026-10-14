# dangoNix redesign plan

Status: proposal, revised 2026-10-14 after a second review. Nothing in this
document is implemented yet. The plan is a **rolling wave**: phase 1 (stages
0-20: baseline, tooling, dango, contract) is detailed; phase 2 (power,
clipboard, search, Caelestia, cleanups, Plymouth) has goals, decisions and
known risks only, and its stages are written after phase 1, from what phase 1
teaches. There are no further full-plan reviews; each stage gets its own
verification and your review of its diff.

Terminology: a **theme** is one complete desktop presentation (a family plus
variant, see §2). The code calls it a "profile" until stage 17 renames it;
code names such as `kit-profile`, `kit.profile.id` and `profiles/` below refer
to that code as it is at the time. The classic palette directory `themes/`
(deleted in stage 8), power profiles (ppd) and Nix profiles are unrelated.

Scope: a refactor of the workflow, the command surface, and the agent-facing
docs around the existing desktop (Noctalia on Hyprland). Wherever a stage's
expected diff is "none", the host toplevel and every theme's
activationPackage must have **identical out paths** before and after; the
oracle (§4) asserts it.

These are all the intended behavior changes. Every one was decided by you, and
none happens outside its stage:

| Stage | Intended behavior change |
|---|---|
| 0 | Your uncommitted work becomes the baseline: the `flake.lock` update (including the held inputs `hyprland`, `noctalia`, `caelestia`) and the Claude Code CLI from nixpkgs-unstable. It predates this plan; it is listed so its effects are never attributed to a later stage. |
| 2 | `kit-profile` switches from the checkout (`~/nixos`, or `KIT_PROFILE_FLAKE`) instead of a store copy of the repo, so theme switches now include uncommitted edits. |
| 4 | Graphify, the Codex hook and skill, and the HM-installed `~/.codex/AGENTS.md` are removed (the repo `AGENTS.md` deletion is already in the baseline). |
| 5 | Claude Code's self-updater is confirmed off (wrapped if needed) and any npm or native copy is removed; agent permission prompts; a Bash guard on `hardware-configuration.nix`. |
| 6 | The default theme (`.#kit`, fresh install) becomes `noctalia`. |
| 7 | The `dms` theme is removed. |
| 8 | The classic themes (catppuccin, tokyo-night, gruvbox, kit-dark) are removed. |
| 10 | Host `hyprlock` and the unused system `hyprpolkitagent` package are removed (only if the precondition allows). |
| 13 | `dango` is added. Activation order becomes host first, then home. Every dango mutation is one locked transaction; a failed activation restores `state.json` and re-activates the previous host and home generations. `dango switch` refuses to build while an enabled Foundry's payload is missing. |
| 14 | Noctalia telemetry is turned off by writing one named key into its `settings.toml`; every other runtime key, including the palette, is left alone. |
| 15 | fwupd is installed; firmware updates only through `dango firmware update`. |
| 16 | `just`, the flake apps, `kit-profile`, `kit-theme`, `foundry*` and the fish abbreviations `jc jf jp js nfu` are removed. The README's command sections become a short dango section. |
| 17 | State paths move from `~/.config/kit/` to `~/.config/dango/`; the lock becomes `$XDG_RUNTIME_DIR/dango.lock`. |
| P2.1 | New bind SUPER+F1 (cheatsheet). |
| P2.2 | New zoom and monitor-scale binds. |
| P2.3 | Caelestia gains the core and role binds. |
| P2.4 | Clipboard history moves to one core store. Noctalia's private store is disabled, so its existing history is lost, and its picker may be replaced by the core picker. |
| P2.5 | SUPER+R becomes search. A theme launcher that cannot read the core sources is replaced by the core default UI. |
| P2.6 | The power profile follows AC/battery automatically; animations and blur turn off on battery. |
| P2.7 | Foundry and Docker no longer start at boot. |
| P2.8 | The low-battery timer may be removed in a theme whose shell warns by itself. |
| P2.9 | Noctalia's wallpaper comes from a committed asset, written as a named key. |
| P2.10 | Git identity moves into Home Manager (`~/.gitconfig` goes away); store optimisation runs on a schedule; Proton-GE is available in Steam; Discord is removed and Vesktop moves to home packages; `spice-vdagent` runs only in a VM. |
| P2.13 | Plymouth splash, systemd initrd, quiet boot. |

## 0. Decisions from the interview

| # | Question | Decision | Consequence for the design |
|---|---|---|---|
| 1 | Themes in use | **Noctalia, plus Caelestia as an experimental second theme** | Retire `dms` and the classic family (catppuccin, tokyo-night, gruvbox, kit-dark), each in its own revertable commit. Caelestia stays as the second implementation the contract is tested against (P2.3). |
| 2 | Vocabulary | **"Theme"** (revised 2026-10-14) | One word for a whole desktop presentation: the command is `dango theme`, as in your draft, and the code moves from "profile" to "theme" in stage 17. A shell's palette is not a dango theme; it stays the shell's runtime state, even where the shell's own settings call it "theme" (Noctalia does). Noctalia is a temporary theme, so its palette is not declared. |
| 3 | `dango switch` | **One transaction: host first, then home** (revised twice) | One lock around the whole mutation: `state.json` edit, build, activation and recovery. Build both first. Activate the host (sudo) only when its closure differs from `/run/current-system`, then always activate home. On failure, restore `state.json` and re-activate the previous host and home generations; no step-by-step undo. `dango switch` refuses to run if `$USER` is not the configured user. |
| 4 | May dango edit the repo | **Yes, one tracked file; you commit** | Every choice a command can make lives in a tracked `state.json`: the selected theme, and Foundry `enable` + `version` only. The payload filename and hash come from nix-foundryvtt's own version table. dango edits the file, shows the diff, and never commits. A gitignored file was rejected: flakes only see git-tracked files, so it would need `--override-input` on every command, and a fresh install would lose the choices. `dango update` additionally rewrites `flake.lock`. |
| 5 | Battery | **Automatic, one user-level service** (revised) | Keep power-profiles-daemon (ppd). One user service tied to the graphical session applies power-saver on battery and balanced on AC, and turns animations and blur off on battery. The `dango power` override lives in `$XDG_RUNTIME_DIR`, so it resets on reboot (P2.6). |
| 6 | Updates | **flake.lock pins, `dango update` gates** (revised) | No `?rev=` pins in `flake.nix`. `flake.lock` pins everything. `dango update` skips a held list (`hyprland`, `noctalia`, `caelestia`) unless an input is named explicitly, and reports held inputs. The gate is `dango check`, which builds the **host toplevel** as well as every theme. It restores the old lock byte-for-byte if checks fail, and never switches. These promises are tested for real in a temporary worktree (stage 13). Possible exception: the `claude-md-management` plugin, if Claude Code cannot stop it from auto-updating (§6). |
| 7 | Agents | **Claude Code only** | Drop Graphify and every Codex-specific file. One short `CLAUDE.md` that describes only what exists. The Claude Code CLI comes from nixpkgs-unstable (already in the baseline) with its self-updater off. Guards are native permissions plus one fail-closed Bash hook (stage 5). |
| 8 | Rename | **Full** | `kit.*` options become `dango.*`, `~/.config/kit/` becomes `~/.config/dango/`, "profile" becomes "theme" (`profiles/` → `themes/`, `kit.profile.*` → `dango.theme.*`), and the lock, environment variables and CLI are renamed too. New things are named "theme" from the start (`lib.themes`, `state.json`'s `theme`, `dango theme`). The Unix user `kit` and the hostname `nixos` are not renamed. |
| 9 | Machines | **Single machine only** | One host, `hosts/nixos/`. No multi-host abstraction, no per-host option layer, no `hosts/<name>` discovery. |
| 10 | Boot and login | **One neutral, host-owned style for all themes** | The greeter stays SDDM with `thyx`, which is already shared by every theme; that is what "neutral" means. The Plymouth splash is added in the host as the very last goal (P2.13). A theme can never change either, so switching themes still never touches the host. |
| 11 | Keys | **Keep every existing bind** | No current bind moves, and no bind loses a flag or argument. The cheatsheet goes on SUPER+F1, because function keys behave the same under the UA and EN layouts. Search is an upgrade of the launcher on the existing SUPER+R; SUPER+Space stays "float toggle". |
| 12 | Core owns data, themes own UI | **Clipboard and search** | One clipboard history service and the search data sources live in the invariant layer and survive theme switches. A theme only provides the UI on top of them. A theme's private store is disabled; if its UI cannot read the core store, the core default UI is used instead. |
| 13 | Kernel | **Keep `linuxPackages_latest`** | Kernel updates arrive only through the gated `dango update`, and that gate builds the host, so a kernel that fails to build never lands. |
| 14 | Noctalia runtime state | **`settings.toml` wins; dango sets named keys only** (2026-10-14) | Noctalia applies `~/.local/state/noctalia/settings.toml` last, so declarations in `config.toml` cannot enforce runtime keys. A small activation step writes only a named list of keys into `settings.toml` (telemetry off in stage 14; the private clipboard store in P2.4; the wallpaper in P2.9) and leaves every other key, including the palette, untouched. Verification never deletes the sidecar. |
| 15 | Planning | **Rolling wave** (2026-10-14) | Phase 1 (stages 0-20) is detailed. Phase 2 is goals, decisions and risks; its stages are written after stage 20. No more full-plan reviews; each stage is verified and you review its diff. |

## 1. Current state

Line references are to the working tree that becomes the baseline (stage 0).

### What is good (keep it)

- **Host and home are split.** Home Manager is standalone (`flake.nix:128-145`), so switching a theme never rebuilds NixOS. This is the right design and the plan keeps it.
- **One explicit theme registry** (`profiles/default.nix`). There is no auto-discovery magic.
- **Real validation.** Every theme builds its activation package, and its generated `hyprland.lua` goes through `luac -p` and `Hyprland --verify-config` (`flake.nix:167-190`).
- **Safe activation.** There is a per-user activation lock, and the identity file only changes when activation succeeds (`home/theme-switcher.nix:101-125`).
- **Foundry is mostly well done.** There is one version pin (`lib/settings.nix:14-22`), a payload and GC-root check (`lib/repo-apps.nix:53-114`), and `sudo` is NOPASSWD only for three exact `systemctl` commands (`hosts/nixos/foundryvtt.nix:61-83`).
- **"Why" comments** where behavior is non-obvious, e.g. `hosts/nixos/desktop.nix:15-18` and `home/claude-desktop.nix:76-80`.
- **`writeShellApplication` everywhere**, so every script is shellchecked at build time.
- **Static checks** (treefmt, statix, deadnix) run inside `nix flake check`.

### Where the friction is

**Command surface (goal 5).** The same action has up to five entry points:

| Action | Entry points today |
|---|---|
| Apply home changes | `just home-switch` (`justfile:22`), `nix run .#home-switch` (`lib/repo-apps.nix:196`), `home-manager switch --flake .#kit` (`README.md:58,87,124`), `home-manager switch --flake .#kit-<id>` (`README.md:91-97`) |
| Switch theme | `kit-profile switch` (`home/theme-switcher.nix:27`), `kit-theme` (`home/theme-switcher.nix:140-143`), `home-manager switch --flake .#kit-<id>` |
| Apply host changes | `just switch`, `nix run .#switch`, `sudo nixos-rebuild switch --flake .#nixos` (`README.md:109-112`) |
| Check | `just check`, `just theme-check`, `just hyprland-check`, the `nix run .#…` versions of each, the fish abbreviation `jc` (`home/programs/terminal.nix:6`) |
| Foundry | `foundry`, `foundry-stop`, `foundry-restart`, `foundry-status` (`home/foundry.nix:7-43`), `just foundry-check` |

Two smaller problems:

- The README has already drifted: `.#kit-dark` (`README.md:94`) does not exist. The output is named `kit-kit-dark` (`flake.nix:145`).
- An order-sensitive bootstrap ritual (`README.md:115-121`) is documented instead of handled by a tool.

**Duplicated logic.**

- The activation lock and the profile-to-output case table are written twice: `lib/repo-apps.nix:139-171` and `home/theme-switcher.nix:15-20,101-119`.
- Hyprland input and misc settings are written twice: `home/hyprland/invariant-settings.nix:25-35` and `home/hyprland/settings.nix:17-23,44-47`.
- About 70 % of `profiles/noctalia/binds.nix` is a copy of `home/hyprland/binds.nix`. Only the launcher, session, OSD and screenshot actions differ.

**Two sources of truth for "the flake".**

- `kit-profile` switches from a copy of the repo embedded in the store (`home/theme-switcher.nix:42`, `flake.nix:139`).
- `just home-switch` switches from the checkout.

The result: switching a theme silently ignores your uncommitted edits. And because the repo copy sits inside the home closure, every commit, even a README typo, produces a new home generation. That also makes "nothing changed" impossible to prove by comparing out paths, which is why stage 2 removes it.

**Checks.**

- About 120 of the 285 lines in `flake.nix` are checks.
- Some are text greps over source files (`selectorArchitectureCheck`, `flake.nix:204-216`).
- Some hard-code theme names (`profileOwnershipCheck`, `flake.nix:217-231`).
- One is a canary that only applies to the classic family (`themeOverrideCanary`, `flake.nix:146-165`).
- Three are aliases that build the same derivations again under other names: `theme`, `hyprland` and `home` (`flake.nix:271-274`).
- None builds the host toplevel, so a host-only build failure (a kernel, say) passes every check.

**No theme contract.** `dms` and `caelestia` evaluate to **0 Hyprland keybinds**, with Stylix, GTK, hyprlock and hypridle all off. That leaves no SUPER+Return and no volume keys. Nothing caught it because nothing defines what a theme must provide.

**Stability (goal 1).**

- `hyprland` tracks git master (`flake.nix:26`), and `noctalia` and `caelestia` track their default branches (`flake.nix:74-75`). Any `nix flake update` bumps them.
- `nfu` (`home/programs/terminal.nix:13`) is an ungated `nix flake update`.

**Energy (goal 2).**

- Only ppd and thermald are enabled (`hosts/nixos/desktop.nix:60-61`, `hosts/nixos/hardware.nix:32`). Nothing reacts to unplugging.
- `foundryvtt.service` starts at boot (upstream `wantedBy = multi-user.target`) and runs Node all day. Docker also starts at boot (`hosts/nixos/workloads.nix:4`).
- `low-battery-notify` polls every 5 minutes (`home/desktop/laptop.nix:39-47`). This probably duplicates Noctalia's own battery warning.

**Agent tooling.**

- Graphify consists of:
  - a 1,287-line Nix extractor (`graphify-nix/nix.py`) plus tests;
  - a patch against upstream internals (`patches/graphify-nix-support.patch`);
  - a flake input and a 92-line module (`home/graphify.nix`);
  - a hook that runs on every Codex Bash call (`.codex/hooks.json`);
  - 34 MB of local output.
- All of that is for 3.3k lines of Nix. A query for "how are desktop themes selected" returned 245 nodes, mostly Zed syntax-colour options.
- `AGENTS.md` made Graphify mandatory; it is deleted in the working tree, and `CLAUDE.md` is empty.

**Naming drift.** The same things go by kitOS, `kit-profile`, `kit-theme`, `profile-id` plus `theme-id`, and `KIT_PROFILE_FLAKE` plus `KIT_THEME_FLAKE`. Checks are named after "theme" while the code says "profile".

**Fragile helper.** `scripts/list-packages.py` (180 lines) parses Nix with regular expressions.

### Manual steps on a fresh install (goal 4: each is a defect)

| # | Manual step today | Fix in this plan |
|---|---|---|
| 1 | Generate `hardware-configuration.nix` for the machine | Inherent. Document it as a pre-step. |
| 2 | Enable flakes on the installer system | Bootstrap command passes `--extra-experimental-features`. |
| 3 | Bootstrap ritual: home first, then host, `-b hm-backup` on collision (`README.md:115-121`) | Stage 13: `dango switch` builds both, activates host first, then home, and supports `--backup`. |
| 4 | Create the user `kit` in the installer | Inherent pre-step: `dango switch` refuses to run as any other user (decision 3), so home is never activated into the wrong `$HOME`. |
| 5 | Foundry payload: `nix-store --add-fixed` plus a manual GC root (`lib/repo-apps.nix:85-107`) | Stage 13: `dango foundry version <zip>` validates the ZIP against nix-foundryvtt's version table, adds it to the store with a GC root, and records the version. On a fresh install it runs **before** the first switch; `dango switch` stops with a message naming it if the payload is missing. Downloading the licensed ZIP stays manual (inherent). |
| 6 | Foundry licence key, admin password, worlds (`/var/lib/foundryvtt`) | Inherent data. Document backup and restore. |
| 7 | Noctalia GUI state in `~/.local/state/noctalia/settings.toml`: palette (Gruvbox, light), wallpaper (a screenshot under `~/Pictures`), `telemetry_enabled = true`, lockscreen widgets | `settings.toml` wins over declarations (decision 14). Stage 14 writes `telemetry_enabled = false` as a named key; P2.9 commits the wallpaper to `assets/` and writes it the same way. The palette stays runtime state by decision; accepted. |
| 8 | Noctalia plugins installed at runtime | Listed. Declare them if Noctalia supports it, otherwise accept. |
| 9 | Git identity lives in an unmanaged `~/.gitconfig` | P2.10: `programs.git` and `programs.gh`. |
| 10 | Proton-GE installed through `protonup-qt` | P2.10: `programs.steam.extraCompatPackages`. |
| 11 | Fingerprint enrolment, Wi-Fi, Bluetooth pairings, app logins (Claude, Zen, Telegram, Steam, Unity), SSH keys and `gh auth` | Inherent or secret. Accepted; there is no secret manager in scope (see "Considered, not planned"). |
| 12 | EasyEffects presets | Listed. Declarable later if you care. |
| 13 | Selected theme is local state (`~/.config/kit/profile-id`) | Stage 12: the selected theme lives in the tracked `state.json`. |
| 14 | Claude Code one-time login | Inherent (account). The CLI is in the baseline; mcp-nixos and the plugin are declared in stage 5. |

## 2. Target architecture

```
flake.nix               inputs + wiring only (target: under 120 lines); exposes lib.themes
state.json              choices made by dango: { theme, foundry { enable, version } }
lib/
  settings.nix          user, host name, system, held inputs (the Foundry pin moves to state.json)
  mk-home.nix           one home configuration per theme
  checks.nix            every flake check, generic over the registry, plus the host build
  dango/
    default.nix         builds the dango package (writeShellApplication)
    commands.nix        the command table (name, description, effect, agent, args), single source of truth
    dango.sh            the CLI source as a real file, not a Nix string
hosts/nixos/            the single host: unchanged layout, plus boot.nix (Plymouth, P2.13)
home/                   invariant user environment
  dango.nix             installs dango, writes ~/.config/dango/theme-id and roles.json (the active theme)
  dango-power.nix       the one power-follow user service (P2.6)
  hyprland/             invariant settings + core binds (with descriptions) generated from roles
  frontends/            core data/services + default UIs for frontend roles (phase 2):
                        keybindings, clipboard history (one store), search sources
themes/
  default.nix           registry = manifest (Nix attrset)
  contract.nix          dango.theme.* and dango.roles.* options + assertions
  common/               shared provider modules (polkit agent, low-battery notifier)
  noctalia/default.nix  family 1, stable; includes the settings.toml named-key step (stage 14)
  caelestia/default.nix family 2, experimental
tests/binds/<id>.json   frozen bind fixture (resolved key, action, arguments, flags), from stage 11
scripts/closure-diff    output oracle (--assert-same) + diagnostics
docs/themes.md          contract reference + new-theme interview
.mcp.json               project MCP servers (mcp-nixos)
.claude/settings.json   permissions (generated from the command table from stage 13), the Bash guard hook,
                        claude-md-management
CLAUDE.md               agent rules (short; describes only what exists; reminders, not enforcement)
README.md               user manual (dangoNix)
```

The principles behind this layout:

1. **The host owns capabilities, and themes own presentation.** This is unchanged. A theme may never require a host change. If a future theme needs a host capability, for example a PAM service, it is added to the host unconditionally, before the theme lands. Boot splash and greeter are host-owned and the same for every theme.
2. **The checkout is the one source of truth.** Nothing operates on a store copy of the repo; from stage 2 the home closure contains no copy of it. `kit-profile` and later `dango` read the flake *and the theme registry* from the checkout. For dango the path comes from `--flake`, then `$DANGO_FLAKE`, then the `kit.repo`/`dango.repo` option (default `~/nixos`); `kit-profile` uses `$KIT_PROFILE_FLAKE` until stage 16 removes it. As a result, docs-only and registry-only commits leave every out path unchanged.
3. **Build everything, then activate, host first.** A failed build never leaves the host and home half-switched. The host goes first because it creates the user, groups and Hyprland that home depends on.
4. **Every check is generic over the registry.** Adding or removing a theme never means editing `flake.nix` or `lib/checks.nix`.
5. **Choices are data, and changing them is one transaction.** Everything a command may change lives in `state.json`. It is plain JSON, so dango edits it safely with `jq` instead of rewriting Nix code, and Nix reads it with `builtins.fromJSON`. One lock covers the whole mutation; if anything fails, dango restores the file and re-activates the previous generations, so the repo never claims a state that was not applied (§3). The host receives only `state.foundry`, never `state.theme`, so a theme change cannot reach the host by construction.
6. **One machine.** No abstraction for hosts that do not exist. If a second machine ever appears, that is its own redesign.
7. **Core owns data, themes own UI.** Clipboard history and search sources are invariant services that survive theme switches. A theme can only put a UI on top of them, never keep a private copy.
8. **Machine-readable first, one command table.** Every dango command supports `--json`. The command table (`lib/dango/commands.nix`) gives each command two separate fields:
   - `effect` (`read`, `runtime`, `state` or `host`) says what the command does;
   - `agent` (`allow` or `ask`) says whether Claude Code may run it without asking.

   Generated from the table:
   - help, fish completions and `dango commands --json`;
   - which commands search shows (`effect` `read`/`runtime`);
   - which commands the `--json` verification runs for real (`effect` `read`) or with `--dry`;
   - which commands take the dango lock (`effect` `state`/`host`);
   - the Claude Code allow/ask rules (`agent`).

### Theme contract

The design idea: a theme is a desktop presentation that fills a fixed set of
**roles**. The invariant core (Hyprland window management, apps, input, and the
frontend services) calls roles, never providers. That turns "build a Windows XP
desktop" into "fill these roles and pass these checks", without touching the
core.

**Theme families.** A *family* is one shell implementation: a module
directory under `themes/<family>/`, owning its own services. A *theme* is a
family plus an optional `variant` attrset passed to the family module, such as
a palette or wallpaper. The classic family was exactly this, with four
variants. Today there are two families: `noctalia` (stable) and `caelestia`
(experimental, the contract's second implementation). A future `quickshell-xp`
would be a third.

**Manifest.** The manifest is the registry entry. It stays a Nix attrset; a
separate YAML or JSON format is not worth it. The flake exposes it as
`lib.themes` (stage 2), the stable interface for dango and the oracle.

```nix
# themes/default.nix (profiles/default.nix until stage 17)
{
  # the selected theme lives in state.json, not here
  themes.noctalia = {
    name = "Noctalia";
    description = "Noctalia v5 as the complete Wayland desktop shell.";
    family = "noctalia";          # directory under themes/
    status = "stable";            # stable | experimental (hidden from `dango theme` without --all)
    variant = { };                # family-specific knobs, passed as module arg
  };
  themes.caelestia = {
    name = "Caelestia";
    description = "Caelestia as the complete Hyprland desktop shell.";
    family = "caelestia";
    status = "experimental";
    variant = { };
  };
}
```

`status = "experimental"` only hides a theme from `dango theme` without
`--all`. It never relaxes a check. There is one temporary exception: from
stage 18 until P2.3, missing roles in an experimental theme are warnings,
not errors, so the contract can land before Caelestia is brought up to it.
P2.3 deletes that warning mode and adds a guard check. The check evaluates
a fixture experimental theme with `launcher` missing and reads its
`config.assertions` list. It requires exactly one failed assertion, with the
message `theme fixture: role launcher has no provider`. Any other evaluation
error fails the check too, so a fixture broken by a later rename cannot pass
by accident.

**Roles.** These are declared in `themes/contract.nix` as `dango.roles.<role>`.
There are four kinds:

- **command:** the theme provides the command, and core binds call it.
- **provider:** the theme names the provider and the **user unit that runs it** (a shell-internal provider names the shell's unit). Required exclusive providers must be **exactly one**, and that unit must be enabled in the theme's configuration.
- **declaration:** the theme states a fact that checks and docs read.
- **frontend with default:** core owns the data or service and the `dango` CLI. A theme *may* provide the UI, but only on top of the core data. If it does not, or if its UI cannot read the core data, core ships a default UI and uses that.

Required roles have no default, so a stable theme that forgets one fails
evaluation with the message `theme <id>: role <role> has no provider`.

| Role | Kind | Required | A theme provides | Consumed by |
|---|---|---|---|---|
| `launcher` | command | yes | command (P2.5 makes it the `search` frontend on the same key) | SUPER+R |
| `session` | command | yes | command (lock/suspend/logout/reboot/poweroff menu) | SUPER+Escape, SUPER+Shift+W |
| `osd` | command | yes | 8 commands: volume up/down/mute, mic mute, brightness up/down, keyboard backlight up/down | XF86 keys |
| `screenshot` | command | yes | `region`, `full`; optional `window` | Print, Shift+Print, SUPER+Print |
| `lock` | provider | yes, exactly one | provider that answers `loginctl lock-session` | idle, session, suspend |
| `idle` | provider | yes, exactly one | provider | check 3, `dango doctor` |
| `bar` | provider | yes, exactly one | provider | check 3 |
| `notifications` | provider | yes, exactly one | the owner of `org.freedesktop.Notifications` | check 3, `dango doctor` |
| `wallpaper` | provider | yes | provider | check 3 |
| `polkit` | provider | yes, exactly one | the polkit agent | check 3, `dango doctor` |
| `batteryWarning` | provider | yes (from P2.8) | the shell itself, or `themes/common/low-battery-notify.nix` | check 3 |
| `palette` | declaration | yes | `{ source = "stylix" \| "shell" \| "static"; }` | docs, future families |
| `toolkit` | declaration | yes | GTK/Qt/cursor theming: `"stylix" \| "shell" \| "none"`, declared explicitly | makes gaps like DMS's visible |
| `keybindings` | frontend with default | no (core default) | optional UI for the bind list | SUPER+F1 (P2.1) |
| `clipboard` | frontend with default | no (core default) | optional picker UI that reads the core store, plus a declaration of any private store the shell has (which must be disabled) | `dango clipboard`, picker key (P2.4) |
| `search` | frontend with default | no (core default) | optional search UI that reads the core sources; replaces `launcher` | SUPER+R (P2.5) |
| `windowSwitcher` | command | no | command | ALT+Tab |
| `controlCenter` | command | no | command | SUPER+S |
| `settings` | command | no | command | SUPER+comma |

Some things are core and never roles: terminal, explorer, browser, editor, the
Claude key, window focus/move/float/fullscreen/close, workspaces 1-5, mouse
drag/resize, zoom and scale (P2.2), input, monitors and default applications.

**Binds are data.** Every core and role bind is a record with a human
description, for example
`{ key = "SUPER+Return"; action = …; description = "Open terminal"; }`. A
bind's identity is the **full resolved entry**: the resolved key, the action,
every argument, and every flag the bind carries (for example
`{ mouse = true; }` on the drag binds). Keys are compared in a **resolved form**:

- the Lua variable `mod` is replaced by its value, so `mod .. " + R"` becomes `SUPER + R`;
- modifiers are uppercased and put in a fixed order (SUPER, CTRL, ALT, SHIFT);
- the parts are joined with ` + `.

The same resolved data generates `hyprland.lua`, the `dango keys` cheatsheet
(`keys.json`, P2.1), the duplicate-key check and the frozen bind fixture, so
none of them can drift from the others.

For Noctalia, every role maps onto what `profiles/noctalia/binds.nix` already
does: `launcher = "noctalia msg panel-toggle launcher"`,
`osd.volumeUp = "noctalia msg volume-up"`, and so on. Its current bind set has
no SUPER+Print, so `screenshot.window` is optional. Caelestia's mapping comes
from its own commands and is the work of P2.3.

**Contract checks.** These live in `lib/checks.nix` and run once per theme. They replace `themeOverrideCanary` and the checks in `flake.nix:191-231`.

1. **Registry (stage 11):**
   - ids are unique;
   - `themes/<family>` exists;
   - the manifest fields are present and well-typed;
   - each theme's `kit.profile.id` (`dango.theme.id` from stage 17) equals its id;
   - from stage 12, `state.json`'s `theme` exists in the registry.

   Family invariants that were hard-coded in `profileOwnershipCheck` become assertions inside each family module. For example, Noctalia asserts `launch_apps_as_systemd_services`, and Caelestia asserts `systemd.enable` and `cli.enable`.
2. **Roles (stage 18):** every required role is set. This is an evaluation-time assertion, so `dango check --fast` catches it. It is never relaxed by `status`, except for the temporary warning mode from stage 18 to P2.3.
3. **Providers (stage 20; `clipboard-store` from P2.4):** every required exclusive role (`bar`, `notifications`, `idle`, `polkit`, `lock`) has **exactly one** enabled provider: the declared provider's unit must be enabled in the evaluated configuration, and no second provider may be enabled. Two sources find second providers:
   - a small table of known HM options (`services.dunst`, `services.mako`, `services.swaync`, `programs.waybar`, `services.hypridle`, `services.cliphist`, …);
   - the theme's own declarations, which cover shell-internal stores that are not HM options, such as Noctalia's clipboard history.
4. **Bindings:**
   - **Frozen fixture (stage 11):** `tests/binds/<id>.json` is committed from the current resolved data, before any bind refactor. Each entry is a full resolved bind (key, action, arguments, flags). Every fixture entry must still be present, unchanged. A stage that intentionally changes a bind updates the fixture in the same commit and lists it as a behavior change (P2.3 for Caelestia, P2.5 for SUPER+R if the launcher is replaced). Stages that add binds add them to the fixture.
   - **Role keys and descriptions (stage 20):** every key that core binds to a role is present, every bind has a non-empty description, and no resolved key is bound twice. All of this is checked on the Nix data, not by grepping text.
5. **Executables (stage 20):** the first word of every role command resolves in the theme's `home-path/bin`, or is an absolute store path.
6. **Builds:** the host toplevel (`host` check, stage 11), each theme's activation package, and `Hyprland --verify-config`.
7. **Command table (stage 13):**
   - every dango subcommand appears in the table;
   - every command has both `effect` and `agent`, and every command whose `effect` is not `read` supports `--dry`;
   - the committed `.claude/settings.json` permission block equals the one generated from the table and the registry.

Checks 1-7 are static. Their runtime counterpart is **`dango doctor`** (stage 18, `read`/`allow`): for the active theme it checks one owner of `org.freedesktop.Notifications` (and that it is the declared provider), a registered polkit agent, a running idle provider, and a single clipboard history writer. Every stage that touches roles runs it after its switch.

**What is not worth it, and why:**

- **Screenshot-to-theme tooling or a generator pipeline.** The agent does that work. What makes it safe is the contract, the checks and the output oracle. A pipeline would be one more thing to maintain, for something done a few times a year.
- **Automated visual regression** (headless Hyprland with Quickshell screenshots). It needs GPU and EGL quirks, is flaky, and is costly. For one user, a manual look after `dango theme <id>` is cheaper and more reliable.
- **One palette driving every family.** Each shell has its own theming engine: Noctalia's palettes and templates, Caelestia's own scheme engine, hand-written QML for an XP clone. Forcing a shared palette means fighting each engine. The contract only requires each theme to *declare* its palette and toolkit source.
- **Many families.** Each family is an external input that churns with Hyprland and Quickshell. Keep it to two or three. Two (Noctalia, Caelestia) is enough to test the contract.
- **Be honest about the XP example.** It is mostly family work (QML for the taskbar, start menu and tray), not palette work. XP-style title bars also need a Hyprland plugin such as hyprbars, and plugins must match the exact Hyprland revision. That works against goal 1, so it should be a conscious choice in the interview, not a default.

**Deferred to the first custom Quickshell theme:**

- **`dango.textSize`** (one option sizing shell, GTK and terminal together). With today's themes it would either take over all GTK theming, because HM's `gtk.font` needs `gtk.enable` and then owns `~/.config/gtk-3.0`/`gtk-4.0` entirely, or it would require declaring Noctalia UI settings. Either contradicts the runtime-palette decision. A custom Quickshell theme owns its own UI and can honour the option cleanly.
- **TheQtCompanyRnD/agent-skills** (official Qt QML skill): enable it when building that theme. It covers Qt Quick in general, not the Quickshell API.

**Worth it:** a `docs/themes.md` checklist for the "screenshot + short
interview" (stage 20). It covers:

- bar position and contents;
- launcher style;
- session menu;
- lock screen;
- notification placement;
- window decorations (plugin: yes or no);
- light, dark or both;
- which optional roles and frontend UIs to provide.

The same doc records the two deferred items above. It is cheap, and it is what an agent actually needs.

## 3. Target command surface

```
command                                   effect   agent  what it does
dango                                     read     allow  short status (active theme, power mode, Foundry state) + help
dango commands                            read     allow  every command with description, effect and agent
                                                          (--json: the agent/frontend API)
dango switch [--home|--host] [--backup]   host     ask    one transaction: build host + home from the checkout, show the
                                                          diff (nvd), activate the host (sudo, only if changed), then home
dango check [--fast]                      read     allow  full: nix flake check (static, host toplevel, every theme's
                                                          build, Hyprland verify, contract); --fast: evaluation only
dango doctor                              read     allow  runtime role checks for the active theme (stage 18)
dango update [input...]                   state    ask    nix flake update for all inputs except the held list (unless
                                                          named), then dango check; on failure restore flake.lock
                                                          byte-for-byte; reports held inputs; never switches or commits
dango theme                               read     allow  list themes, mark selected (state.json) and active, if they differ
dango theme <id>                          state    ask    write the theme to state.json, then build and activate it (home
                                                          only); one transaction
dango foundry [status|logs|check]         read     allow  no argument = status + URL
dango foundry start|stop|restart|open     runtime  ask    start/stop/restart foundryvtt.service (NOPASSWD sudo inside);
                                                          open = start if needed, then open the URL
dango foundry version <zip>               host     ask    validate the ZIP against nix-foundryvtt's version table, add it to
                                                          the store + GC root; if the version differs from state.json,
                                                          record it and switch the host
dango foundry enable|disable              host     ask    write foundry.enable to state.json, then switch the host
dango firmware [--refresh]                read     allow  list devices and available updates; refreshes metadata first if
                                                          it is older than 24 hours (--refresh: always)
dango firmware update                     host     ask    apply firmware updates (never automatic; no background timer)
dango power                               read     allow  (P2.6) AC/battery, ppd profile, override (if any)
dango power auto|saver|balanced|performance
                                          runtime  allow  (P2.6) set or clear the override in $XDG_RUNTIME_DIR
dango keys                                read     allow  (P2.1) cheatsheet from the real bind data (also on SUPER+F1)
dango clipboard [list]                    read     ask    (P2.4) clipboard history from the one core store
dango clipboard pick                      runtime  ask    (P2.4) pick an entry and put it on the clipboard
dango clipboard clear                     state    ask    (P2.4) delete the history
nix fmt                                   —        —      formatting stays the standard flake formatter, not wrapped

Global flags, written before the subcommand: --json (one JSON document on stdout, human progress and build
logs on stderr), --dry (every command whose effect is not `read`: what it would do, no changes), --flake <path>.
Example: `dango --dry switch`.
```

**Effects** (what a command does):

| Effect | Meaning | In search (P2.5) | `--json` verification | Dango lock |
|---|---|---|---|---|
| `read` | changes nothing lasting | yes | runs for real | no |
| `runtime` | reversible runtime change, gone after a stop or a reboot | yes | runs with `--dry` | no |
| `state` | writes persistent state: `state.json`, `flake.lock`, or user data such as clipboard history | no | runs with `--dry` | yes |
| `host` | changes the system configuration or activates it | no | runs with `--dry` | yes |

**Agent** (Claude Code permission) is a separate field. It defaults to `allow`
for `read`/`runtime` and `ask` for `state`/`host`, and the table overrides it
where the effect alone is not the right answer. Re-checked command by command:

- **`dango foundry start|stop|restart|open`:** `runtime` (reversible, so it shows in search), but `ask`. It acts on a system service through `sudo`, and stopping it would end a running game session.
- **`dango clipboard [list]` and `pick`:** `read`/`runtime`, but `ask`. Clipboard history can hold passwords and tokens, so an agent must not read it without asking.
- **`dango power <mode>`:** `runtime`, `allow` (your earlier decision: a reversible mode, and asking for everything trains approval without reading).
- **`dango firmware`:** `read`, `allow`. A metadata refresh changes only fwupd's cache.
- **`dango doctor`:** `read`, `allow`. It reads bus names and unit states only.
- Every other command keeps its default.

**How the permission rules are generated:**

- Rules are generated from the `agent` field, per concrete argument form, so an `allow` form and an `ask` form never share a prefix. For example, there is one ask rule per registry id, such as `dango theme noctalia`, so the bare `dango theme` listing stays allowed. A new theme therefore needs regenerated rules, and check 7 fails until they are.
- The Foundry desktop entries call `dango foundry open`. They are unaffected because permissions apply only to Claude Code.
- `dango --dry …` (the global flag placed **before** the subcommand) is generated as one `allow` rule. That way, `--dry` verification of `ask` commands runs without prompts. A trailing flag cannot cancel `--dry`, because dango parses global flags first and refuses a later `--no-dry`. Any other leading flag (`dango --flake … switch`) does not match the rule and asks.
- Search shows `dango foundry open/start/stop/restart` (`runtime`). When you click them, no permission applies, because permissions are only for Claude Code.

**Where this challenges your draft:**

- **`dango theme` stays as in your draft** (decision 2, revised). It switches the whole desktop presentation; a shell's palette is not a dango theme.
- **`dango update` is gated.** "Update all packages" on its own is the single biggest source of instability. Today's `nfu` is worse than your draft; the gated version with a held list is better than both. It writes `flake.lock` and leaves committing to you. `dango update hyprland` updates a held input on purpose.
- **`dango foundry` changes version and install/remove declaratively.** These write `state.json` and then switch the host, so the repo always describes the system. Version changes take the licensed ZIP as input; the version is read from the ZIP and must be in nix-foundryvtt's own table, whose hash the ZIP must match. Everything else in your draft (start, stop, restart, status, open) is kept.
- **Added: `dango power`** (P2.6). It is needed for goal 2's override.
- **Added: `dango commands`, `dango doctor`, `dango firmware`, `dango keys`, `dango clipboard`** (amendments, 2026-10-13 and 2026-10-14).
- **Not added: `dango fmt`.** `nix fmt` is the standard agents already know.
- **Not added: zoom and scale commands.** Those are binds (P2.2). Their helper is internal and not part of the user surface.
- **Not added yet: `dango rollback`.** It is optional (P2.11). For the host, the boot menu already gives rollback.

**Implementation notes:**

- `dango` is one `writeShellApplication`. Its source is `lib/dango/dango.sh`; Nix injects a small config (host, user, held inputs, default repo path, the path of the locked nix-foundryvtt version table) and the command table.
- `--json` output is built with `jq`. Long-running commands (`switch`, `update`, `check`) emit a single result object at the end, with fields such as `ok`, `steps` (in order), `failedStep`, `recovered`, `hostChanged`, `homeGeneration` and, for `update`, `updated` and `held`.
- The theme list is read from the checkout through `nix eval <flake>#lib.themes --json`. Nothing about the registry is built into the home closure.
- Edits to `state.json` go through `jq` to a temp file and an atomic rename, and are shown as a `git diff` afterwards.
- `apps.default` is dango, so the bootstrap command is `nix run ~/nixos -- switch`.

**Transactions.** Every command whose effect is `state` or `host` runs as one transaction:

1. Refuse unless `$USER` is the configured user (`kit`).
2. Take the dango lock with `flock -n`. Until stage 17 the file is the existing `$XDG_RUNTIME_DIR/kit-home-activation.lock`, so dango, `kit-profile` and `just home-switch` exclude each other; from stage 17 it is `$XDG_RUNTIME_DIR/dango.lock`. A second mutating command fails at once with "another dango command is running" and changes nothing. The lock is held until the command exits, recovery included.
3. Snapshot: `state.json` (and `flake.lock` for `update`, with its sha256), the current host generation (`readlink -f /run/current-system`) and the current home generation (`readlink -f ~/.local/state/nix/profiles/home-manager`).
4. Preflight: if Foundry is enabled (after the planned edit), its payload must be in the store; otherwise stop with a message naming `dango foundry version <zip>` (or `dango foundry disable`).
5. Edit `state.json`.
6. Build the host toplevel and the selected theme's activation package in one `nix build`.
7. Show the nvd diff for both.
8. Host, only if the result differs from `/run/current-system`: `sudo nix-env -p /nix/var/nix/profiles/system --set <path> && sudo <path>/bin/switch-to-configuration switch`. This is what `nixos-rebuild` does internally.
9. Home: `<activationPackage>/activate`. `--backup` sets `HOME_MANAGER_BACKUP_EXT=hm-backup`.
10. Release the lock and show the `git diff` of the repo files it changed.

**Recovery.** A failure in steps 4-7 restores the snapshot files; nothing was
activated. A failure in step 8 or 9 restores the snapshot files, then
re-activates the snapshotted host generation (if step 8 activated a new one)
and the snapshotted home generation (if step 9 started), the same way steps 8
and 9 activate. Home Manager links files before later activation steps can
fail, so re-activating the previous generation is the only sound undo; there
is no step-by-step undo. The JSON result reports `failedStep` and `recovered`.
If recovery itself fails, dango exits 3 and prints the exact commands that
finish it by hand.

`--host` and `--home` restrict a switch to one side. `--dry` never takes the
lock or writes anything: it prints the planned `state.json` diff and, for
`switch`, stops after step 7. `dango update` runs steps 1-3, then
`nix flake update` for the non-held (or named) inputs and `dango check`; on
failure it copies the snapshot back and asserts the sha256 matches.
`dango foundry version <zip>` validates before step 1 (version from the ZIP's
`resources/app/package.json`, which must be in nix-foundryvtt's table; the
ZIP's hash must match the table), then imports it with
`nix-store --add-fixed sha256` and a GC root under `~/FoundryVTT/gcroots`. If
the version equals `state.json`'s, it stops there (no state change, no
switch); otherwise it runs steps 1-10 for the host only.

**Fresh install becomes:**

```sh
# after a stock NixOS install that created the user `kit`,
# with this repo cloned to ~/nixos and /etc/nixos/hardware-configuration.nix
# copied into hosts/nixos/; download the Foundry ZIP for the version in state.json first
nix --extra-experimental-features 'nix-command flakes' run ~/nixos -- foundry version ~/Downloads/FoundryVTT-<version>.zip
# (or: … run ~/nixos -- foundry disable, to skip Foundry)
nix --extra-experimental-features 'nix-command flakes' run ~/nixos -- switch
```

## 4. Migration stages

Rules for every stage:

- One commit per stage, after your review. Each stage ends with its verification; then I stop and show you the diff and the verification output, and commit only after you approve. Stage files explicitly (`git add <paths>`; `git rm` for deletions), never `git commit -a`. New files must be staged before checking, because flakes ignore untracked files.
- `nix flake check --no-write-lock-file` passes before committing; from stage 13 that is `dango check`, which includes the host build.
- `hosts/nixos/hardware-configuration.nix` is never touched.
- **Temporary worktrees.** Tests that change `state.json`, `flake.lock` or Nix code on purpose never run in your checkout. They use `wt=$(mktemp -d) && git worktree add --detach "$wt" "$(git stash create)"`, which snapshots the stage's staged and unstaged work without committing to any branch, and `dango --flake "$wt" …`. The worktree is removed afterwards (`git worktree remove --force "$wt"`), and `git status` in the checkout is unchanged by the test.
- **Oracle:**
  - From stage 3 onward, every stage whose expected diff is "none" must pass `scripts/closure-diff --assert-same HEAD` (with `--removed <id>…` where the stage removes themes).
  - Every stage with a non-empty expected diff runs `scripts/closure-diff HEAD`. The changed derivations it reports must match the stage's list exactly. Anything extra means stop and investigate.
  - Every stage descends from the baseline commit (stage 0, tagged `redesign-baseline`); `scripts/closure-diff redesign-baseline` shows the cumulative change of the redesign so far.
- **`dango doctor`** runs after the switch in every stage that touches roles (from stage 18).
- **CLAUDE.md describes only what exists.** From stage 5 on, any stage that changes something agents rely on updates `CLAUDE.md` in the same commit. The stages below say what changes.

**`scripts/closure-diff` (stage 3):**

- **Stable interface.** It reads theme ids from `lib.themes` at both revisions. It compares the host toplevel (`nixosConfigurations.nixos.config.system.build.toplevel`) and `checks.<system>.home-<id>` for every id present at both. It never relies on `homeConfigurations.kit-*` or option names, which later stages change.
- **`--assert-same`** exits non-zero:
  - if any compared out path differs (it then prints `nix-diff` for each differing derivation);
  - if it compared zero themes;
  - if the set of added or removed themes is not exactly what `--added`/`--removed` declares.
- **Without the flag** it is a diagnostic. It prints:
  - the names of changed derivations (in the new derivation closure but not the old);
  - `nix-diff` for each differing top-level output;
  - `nix store diff-closures`;
  - the text diff of each theme's generated `hyprland.lua`, read from `home-files/.config/hypr/hyprland.lua` inside the built activation package.

**Expected-diff convention.** Stages list only the leaf derivations that change. Wrapper derivations always change along with any leaf below them, and are not repeated:

- home: `home-manager-files`, `home-manager-path`, `home-manager-generation`;
- host: `etc`, `system-path`, `system-units`, `nixos-system-nixos-*`.

Home Manager names a generated file's derivation `hm_<sanitized path>`, and NixOS names a unit's derivation `unit-<name>`. The first `nix-diff` run in each stage confirms the exact names, and the commit message records them.

Before stage 6, create a local tag `last-multi-theme` so retired themes can
be restored with `git checkout last-multi-theme -- profiles themes …`.

### Phase 1 (detailed)

Execution table. **Checkpoint**: after the stage's commit, a reviewer
subagent reviews the diff since the previous checkpoint tag, and the commit
is tagged `checkpoint-<N>` (stage 0 keeps its tag `redesign-baseline`).
**Needs you**: the stage ends `needs-human` because it needs a switch, sudo,
a reboot or a manual check. **Effort**: the reasoning effort the stage runs
at; every stage not marked high runs at medium.

| Stage | Title | Checkpoint | Needs you | Effort |
|---|---|---|---|---|
| 0 | Baseline | ✓ baseline | approval, switch, use the desktop | medium |
| 1 | Plan | | | medium |
| 2 | Stop embedding the flake source | | switch (`kit-profile switch noctalia`) | medium |
| 3 | Output oracle | | | **high** |
| 4 | Drop Graphify and Codex tooling | | | medium |
| 5 | CLAUDE.md + agent tooling | | switch, manual check (claude, hook, `/plugin`) | medium |
| 6 | Default theme = noctalia | | | medium |
| 7 | Retire DMS | | | medium |
| 8 | Retire the classic family | | | medium |
| 9 | Drop Stylix | | | medium |
| 10 | Host cleanup after classic | ✓ after removals | switch, sudo, manual check (lock, fingerprint, suspend) | medium |
| 11 | Checks out of flake.nix | | | **high** |
| 12 | State file | | | medium |
| 13 | dango v1, next to the old commands | ✓ after dango v1 | switch, sudo, manual check (transactions) | **high** |
| 14 | Noctalia runtime keys | | switch, manual check (settings UI) | medium |
| 15 | Firmware | | switch, sudo | medium |
| 16 | Remove old entry points | | switch, manual check (Foundry launchers) | medium |
| 17 | Full rename | | switch | medium |
| 18 | Contract options + `dango doctor` | | switch, manual check (stop/start Noctalia) | **high** |
| 19 | Binds generated from roles | | switch | medium |
| 20 | Contract checks + docs | ✓ after the contract | switch | medium |

No stage needs a reboot; stage 10's suspend/resume is the closest.

#### Stage 0: Baseline

- **Changes.** None by me. First I show you a summary of the uncommitted work and wait for your approval:
  - `flake.nix`: `pkgsUnstable` is imported with `config.allowUnfree = true`;
  - `home/packages.nix`: `pkgsUnstable.claude-code` and the `pkgsUnstable` argument;
  - `flake.lock`: every input whose revision changed, old → new revision and date, with nixpkgs and the held inputs (`hyprland`, `noctalia`, `caelestia`) called out;
  - `patches/graphify-nix-support.patch`: what changed, and whether the new `graphify` lock entry needs it to build;
  - `AGENTS.md`: deleted;
  - left out: the empty untracked `CLAUDE.md` (stage 5 writes it) and this plan (stage 1).
- **Verify (before the commit).** `nix flake check --no-write-lock-file`; `nix build .#nixosConfigurations.nixos.config.system.build.toplevel`; then activate with today's commands (`just switch`, then `just home-switch`) and use the desktop for a while, so any regression from the input update is found here and not blamed on a refactor stage.
- **After your approval.** `git add flake.nix flake.lock home/packages.nix patches/graphify-nix-support.patch`, `git rm AGENTS.md`, commit, and tag `redesign-baseline`. `git show --stat HEAD` lists exactly those five paths.
- **Expected diff.** Whatever the summary shows; nothing else.

#### Stage 1: Plan

- **Changes.** `git add docs/redesign-plan.md`, commit.
- **Verify.** `nix flake check --no-write-lock-file`; `git show --stat HEAD` lists only the plan.
- **Expected diff.** Home (every theme): only the embedded repo `source` path, which every commit changes until stage 2. Host: none.

#### Stage 2: Stop embedding the flake source

- **Changes.** Remove `profileFlakeSource` (`flake.nix:139`, `lib/mk-home.nix:9,34`). `kit-profile` reads the flake **and** the theme list from the checkout: `$KIT_PROFILE_FLAKE`, else `~/nixos`, via `nix eval <flake>#lib.themes --json`. It no longer bakes registry case tables into its script, and a missing checkout is a clear error. Add the flake output `lib.themes` (the registry). `KIT_THEME_FLAKE` fallback kept until stage 16.
- **Verify.** For every theme, `nix build .#checks.x86_64-linux.home-<id>` twice, once clean and once with an uncommitted README edit, gives the same out path; `nix path-info -r` of each activation package contains no copy of the repo; `kit-profile list` and `kit-profile switch noctalia` work from `/tmp`; with `KIT_PROFILE_FLAKE` pointing at a copy, that copy is used.
- **Expected diff.** Home (every theme): `kit-profile`; − the repo `source` path from the closure. Host: none.

#### Stage 3: Output oracle

- **Changes.** Add `scripts/closure-diff` as specified above.
- **Verify.** `scripts/closure-diff --assert-same HEAD` passes on a clean tree. In a temporary worktree: (a) rename `kit.profile.id` to `dango.theme.id` throughout and move `profiles/` to `shells/` (`themes/` still holds the classic palettes), and `--assert-same` still passes; (b) remove one theme, and `--assert-same` fails without `--removed <id>` and passes with it; (c) empty the registry, and it fails with "compared zero themes"; (d) change one Hyprland option, and it fails and prints the `nix-diff`.
- **Expected diff.** None.

#### Stage 4: Drop Graphify and Codex tooling

- **Changes.** Remove `home/graphify.nix` and its import (`home/kit.nix:15`), `graphify-nix/`, `patches/graphify-nix-support.patch`, `.codex/`, the `graphify` input, the `.gitignore` entries and `README.md:178`. Fix the stale comment in `home/pdf2md.nix:32`. Delete `graphify-out/` locally. The `pyproject-nix`, `uv2nix` and `pyproject-build-systems` inputs stay: `home/pdf2md.nix` uses them.
- **Verify.** `nix flake check --no-write-lock-file && scripts/closure-diff HEAD`.
- **Expected diff.** Home (every theme): − `graphify-<version>` (and its Python closure), − `graphify-codex-skill`, − `hm_.codexAGENTS.md`, − `hm_.codexhooks.json`, − the `.codex/skills/graphify` link. Codex's own data in `~/.codex` is untouched. Host: none.

#### Stage 5: CLAUDE.md + agent tooling

Lands right after Graphify removal, so old and new agent tooling never coexist.

- **CLAUDE.md** (≤ 60 lines) describes only what exists at this point: invariants, the loop `edit → nix fmt → nix flake check --no-write-lock-file → scripts/closure-diff --assert-same HEAD` (or the stage's expected changes), the commit rule (stage files explicitly), the mcp-nixos line, one-line permission reminders, and the layout.
- **Claude Code CLI.** Already declared in the baseline (`pkgsUnstable.claude-code`), so `flake.lock` pins it and `dango update` will gate it. Confirm the nixpkgs wrapper sets `DISABLE_AUTOUPDATER=1`; if it does not, wrap it ourselves. Remove any npm or native install (`~/.local/bin/claude`, `~/.npm-global`), one time, on this machine.
- **mcp-nixos.** Pinned `pkgs.mcp-nixos` 2.4.3; a committed project `.mcp.json` (`{"mcpServers":{"nixos":{"command":"mcp-nixos"}}}`); pre-approved with `enabledMcpjsonServers: ["nixos"]`.
- **Plugin.** Only `claude-md-management`, via `extraKnownMarketplaces` (`claude-plugins-official`) and `enabledPlugins` in the committed `.claude/settings.json`, with marketplace auto-update off if supported (otherwise the recorded exception, §6). If the keys are unsupported, the one-time install goes into the manual-steps table. No hookify, no formatting hook.
- **Guards.** *Deny* Edit/Write of `hosts/nixos/hardware-configuration.nix`. One *PreToolUse hook on Bash* blocks any command whose text mentions `hardware-configuration.nix`. The script is a `writeShellApplication` whose dependencies are declared in Nix. Home Manager places it at a fixed path, `~/.config/dango/hooks/bash-guard` (`xdg.configFile`, executable), not in a profile `bin` directory. Claude Code blocks only on exit code 2: a missing file (127) or any other failure is a non-blocking hook error, and the command would run. So the hook command in `settings.json` is `"$HOME/.config/dango/hooks/bash-guard" || exit 2`, which turns every failure into a block: a missing or wrong path, a crash, or a missing dependency. Inside the script, any internal error also exits 2. The path uses `~/.config/dango/` from the start, like other new things (stage 17 renames only existing `kit` paths). It is a strong guard, not a guarantee: a command can reach the file without naming it (globs, variables, scripts), so the final check is your review of the diff.
- **Permissions (hand-written until stage 13).** *Ask* for `sudo`, `nixos-rebuild`, `home-manager switch`, `nix flake update`, `nix flake lock`, `just switch`, `just home-switch`, `nix run .#switch`, `nix run .#home-switch`, `kit-profile switch`, `kit-theme switch`, `foundry`, `foundry-stop`, `foundry-restart`; *allow* `nix build`, `nix eval`, `nix flake check`, `nix fmt`, `foundry-status`, `scripts/closure-diff`. Add `.claude/settings.local.json` to `.gitignore`.
- **Verify.** `nix flake check --no-write-lock-file`; `scripts/closure-diff HEAD`; `readlink -f "$(command -v claude)"` points into `/nix/store` and its wrapper sets `DISABLE_AUTOUPDATER=1`; no `claude` remains in `~/.local/bin`; `claude mcp list` shows `nixos` connected; an Edit of `hardware-configuration.nix` is refused; `cat hosts/nixos/hardware-configuration.nix` through Bash is blocked (reading through the Read tool still works); **negative tests:** the hook blocks when run with `env -i` (stripped PATH); with `~/.config/dango/hooks/bash-guard` removed, every Bash command is blocked (restored by the next `just home-switch`); `nix flake check` runs without a prompt; `sudo true` asks; `/plugin` lists only `claude-md-management`.
- **Expected diff.** Home (every theme): + `mcp-nixos`, + `bash-guard` (the script), + `hm_.configdangohooksbash-guard`; a `claude-code` wrapper only if the nixpkgs one lacks `DISABLE_AUTOUPDATER`. Host: none.

#### Stage 6: Default theme = noctalia

- **Changes.** `profiles/default.nix:2`. Delete `themeOverrideCanary`/`themeOverrideCheck` (`flake.nix:146-165`) in the same commit, because it extends the default theme and asserts values that only `home/waybar.nix` provides.
- **Verify.** `nix flake check …`; `nix eval .#homeConfigurations.kit.config.kit.profile.id` returns `"noctalia"`; `scripts/closure-diff --assert-same HEAD`.
- **Expected diff.** None (`.#kit` now points at noctalia; per-theme outputs are identical).

#### Stage 7: Retire DMS

- **Changes.** Remove `profiles/dms`, its registry entry, the `dms` input, and its assertions in `profileOwnershipCheck`.
- **Verify.** `nix flake check …` and `scripts/closure-diff --assert-same --removed dms HEAD`.
- **Expected diff.** None for the remaining themes.

#### Stage 8: Retire the classic family

- **Changes.** Remove `themes/`, `profiles/classic/`, `home/{waybar,osd,power,screenshots}.nix`, `home/desktop/{theme,wallpaper}.nix`, `home/hyprland/{settings,binds}.nix`, `assets/wallpapers/*`, the `kit.apps.launcher` option, and the classic assertions. Because `selectorArchitectureCheck` reads `home/hyprland/settings.nix`, remove that `readFile` assertion in the same commit; the rest of the selector check goes in stage 11. Keep the Stylix module import for now.
- **Verify.** `nix flake check …` and `scripts/closure-diff --assert-same --removed catppuccin tokyo-night gruvbox kit-dark HEAD`.
- **Expected diff.** None for noctalia and caelestia. If anything differs, the classic code was leaking into the shells: stop and investigate.

#### Stage 9: Drop Stylix

- **Changes.** Remove the `stylix` input and the module import in `lib/mk-home.nix:18`.
- **Verify.** `nix flake check …` and `scripts/closure-diff --assert-same HEAD`.
- **Expected diff.** None. Any difference is something disabled Stylix was still setting; decide explicitly before committing.

#### Stage 10: Host cleanup after classic

- **Precondition.** Find out which PAM service the Noctalia **and** Caelestia lock screens use. `programs.hyprlock` and the `hypridle` force-disable (`hosts/nixos/desktop.nix:15-18,76`) go together: if either lock screen uses the `hyprlock` PAM service, keep **both**; otherwise drop both.
- **Changes.** As the precondition decides; drop the unused system `hyprpolkitagent` package (`hosts/nixos/desktop.nix:115`) either way.
- **Verify.** `nix build .#nixosConfigurations.nixos.config.system.build.toplevel`; `scripts/closure-diff HEAD`; manual test in both themes: lock, unlock with password, unlock with fingerprint, suspend/resume.
- **Expected diff.** Host: − `hyprpolkitagent` (from `system-path`); if dropped: − `hyprlock` (from `system-path`), − `etc` entry `pam.d/hyprlock`. Home: none.

#### Stage 11: Checks out of flake.nix

- **Changes.** Add `lib/checks.nix`, generic over the registry. Delete the grep checks, the hard-coded assertions and the alias checks. Add:
  - contract check 1 (registry, `kit.profile.id == id`, family invariants as module assertions, replacing `profileCheck`, `selectorArchitectureCheck` and `profileOwnershipCheck`, including the `launch_apps_as_systemd_services` assertion);
  - a `host` check that builds the host toplevel, so `nix flake check` (and later `dango check`) fails on host-only build errors;
  - the bind key resolver and the frozen bind fixture `tests/binds/<id>.json` with its check (check 4, fixture part). Each entry is the full resolved bind: key, action, arguments, and every flag (`{ mouse = true; }` on the drag binds included).
- **Verify.** `nix flake check …`; `nix flake show` lists only `static`, `registry`, `binds-fixture`, `host`, `home-<id>`, `hyprland-<id>`; negative tests in a temporary worktree: change one fixture action, and `binds-fixture` fails; drop `mouse = true` from one mouse bind in the Nix data, and `binds-fixture` fails; duplicate a registry id, and `registry` fails; break the host build (e.g. an invalid `boot.kernelPackages` value), and `host` fails; `scripts/closure-diff --assert-same HEAD`.
- **Expected diff.** None.

#### Stage 12: State file

- **Precondition.** Locate the version table in the locked nix-foundryvtt source and confirm it carries, per version, the payload filename and hash that its package uses. If it does not, stop and decide before continuing.
- **Changes.** Add tracked `state.json`: `{ "theme": …, "foundry": { "enable": …, "version": … } }` and nothing else. `homeConfigurations.kit` builds `state.theme`. The Foundry version moves from `lib/settings.nix:14-22`; `shortVersion`, `filename` and `hash` are deleted there, and the payload check (`foundry-check`, until stage 16) derives filename and hash from the nix-foundryvtt table. The host gets only `state.foundry` via `specialArgs`. The registry `default` goes away. Check 1 gains "`state.json`'s theme exists". **CLAUDE.md:** `state.json` holds your choices, and agents change it only when asked.
- **Verify.** `nix flake check …`; `scripts/closure-diff --assert-same HEAD`; `just foundry-check` still passes; in a temporary worktree, a version absent from the nix-foundryvtt table fails evaluation with a clear message.
- **Expected diff.** None.

#### Stage 13: dango v1, next to the old commands

- **Changes.**
  - Add `lib/dango/` (command table with `effect` and `agent`, `dango.sh`) and `home/dango.nix`; `apps.default = dango`. Option `kit.repo` (default `~/nixos`; renamed in stage 17).
  - Subcommands: `switch`, `check` (includes the `host` check), `update` (held list from `lib/settings.nix`, reports held inputs), `theme`, `foundry` (`status/logs/check`, `start/stop/restart/open`, `version`, `enable`/`disable`), and `commands`. Every command supports `--json`, and every non-`read` command supports `--dry`.
  - Every `state`/`host` command runs as the transaction in §3: one lock (the existing `kit-home-activation.lock`) around snapshot, preflight, `state.json` edit, build, host activation, home activation and recovery.
  - `dango foundry version <zip>` validates against the nix-foundryvtt table; `dango switch` preflights the payload.
  - Generate the `.claude/settings.json` permission block from the command table's `agent` field plus the registry (per-id ask rules) plus `allow dango --dry …` plus the hand-written non-dango rules from stage 5, and add check 7. Old commands keep working.
  - **CLAUDE.md:** the loop becomes `edit → nix fmt → dango check --fast → dango check → closure-diff`, command discovery is `dango commands --json`, and the `agent` field (allow/ask) gets one line.
- **Verify, basics (in the checkout).** `dango check`; `dango theme` marks noctalia; `dango theme noctalia` leaves `git diff` empty; `dango --dry switch` on a clean tree reports no change for host and home; `dango switch` reports "host unchanged"; `sudo -u nobody dango switch` refuses; for every command in `dango commands --json`, `read` ones run with `--json` and the rest with `dango --dry --json …`, without any permission prompt, and each output passes `jq -e .`; check 7 fails after a hand edit of the permission block.
- **Verify, transactions (temporary worktree, `dango --flake "$wt"`).**
  1. *Changed host:* an uncommitted harmless host change (`environment.etc."dango-test".text = "1";`), then `switch`: `/etc/dango-test` exists; the JSON `steps` are `host` before `home`, and the `/nix/var/nix/profiles/system` link is older than the home-manager profile link.
  2. *Host activation failure:* add `system.activationScripts.dangoFail = "exit 1";` and run `theme caelestia`: the command fails with `failedStep: "host"`, `recovered: true`; `/run/current-system`, the home generation and the worktree's `state.json` equal their pre-test values.
  3. *Home failure after linking:* together with the host change from 1, add `xdg.configFile."dango-test".text = "1";` and a `home.activation` step after `linkGeneration` that exits 1: the command fails with `failedStep: "home"`, `recovered: true`; `~/.config/dango-test` is gone, and both `/run/current-system` and the home generation equal their pre-test values.
  4. *Competing commands:* start `theme caelestia`, and while it builds run `foundry disable` and `kit-profile switch noctalia`: both fail at once with "another … is running" and change nothing; `state.json` shows only the theme change.
  5. Afterwards `dango switch` from the checkout restores the normal system, and `git -C ~/nixos status` is unchanged.
- **Verify, update (temporary worktree).**
  1. `dango --flake "$wt" --json update`: `jq '.nodes.<held>.locked'` is byte-identical before and after for `hyprland`, `noctalia`, `caelestia`; the JSON `held` lists them.
  2. Reset the lock (`git -C "$wt" checkout flake.lock`), then `update hyprland`: the JSON `updated` contains `hyprland`, and no other top-level input changed.
  3. Reset the lock, record `sha256sum flake.lock`, break one check with an uncommitted edit (an invalid Hyprland option), then `update`: it exits non-zero and `sha256sum flake.lock` equals the recorded hash.
  4. `git diff --exit-code flake.lock` in your checkout passes afterwards.
- **Verify, Foundry (temporary worktree).**
  1. *Payload missing:* set `foundry.version` to a version in the table but not in the store; `switch` fails with `failedStep: "preflight"` before any build, and the message names `dango foundry version <zip>`.
  2. *Wrong ZIP:* a copy of the real ZIP with one byte changed is rejected (hash mismatch); a ZIP whose `package.json` claims a version absent from the table is rejected (unsupported version); in both cases `state.json` is unchanged and no GC root is added.
  3. *Same version:* importing the current ZIP again changes nothing and does not switch.
  4. *Round trip:* `foundry disable` removes `foundryvtt.service` (`systemctl cat` fails); `foundry enable` brings it back; `git -C "$wt" diff state.json` is empty and the host toplevel equals the pre-test one.
  5. A successful version change is tested when a newer supported ZIP is available; until then it is covered by 1-3.
- **Expected diff.** Home (every theme): + `dango` (+ its fish completion file `hm_.configfishcompletionsdango.fish`). Host: none.

#### Stage 14: Noctalia runtime keys

- **Precondition.** Read the locked Noctalia source and confirm: the exact table path of `telemetry_enabled` in `settings.toml`; whether Noctalia rewrites `settings.toml` from memory (on change or on exit); and how it treats a missing or partial file.
- **Changes.** The Noctalia family module gets a named list of runtime keys (now only `telemetry_enabled = false`) and a script, `noctalia-runtime-keys`, that sets exactly those keys in `~/.local/state/noctalia/settings.toml` with a format-preserving TOML editor (Python `tomlkit`, declared in Nix) and touches nothing else. It runs as a Home Manager activation step after `writeBoundary`. If the precondition shows Noctalia rewrites the file from memory, the same script also runs as `ExecStartPre` of the Noctalia user unit, so the key is in place before Noctalia reads it. **CLAUDE.md:** Noctalia's `settings.toml` wins over declarations; enforce runtime keys only through the named list.
- **Verify.** The script on copies in `/tmp` (a real copy, an empty file, a missing path) sets only the named key. Then, on the real sidecar, never deleting it: back it up (`cp -a`); `dango switch`; restart Noctalia; `telemetry_enabled` is false in the file and in Noctalia's settings UI; `diff` against the backup shows only that line, so the palette and every other key are unchanged, and the palette looks the same; restore the backup and restart Noctalia; the next `dango switch` sets the key again. Caelestia: `scripts/closure-diff HEAD` shows it unchanged.
- **Expected diff.** kit-noctalia: + `noctalia-runtime-keys` (and its Python environment), the activation script in `home-manager-generation`, and `hm_.configsystemdusernoctalia.service` only if `ExecStartPre` is needed. kit-caelestia: none. Host: none.

#### Stage 15: Firmware

- **Changes.** `services.fwupd.enable = true` in the host. Turn off fwupd's metadata-refresh timer, so nothing happens in the background. `dango firmware [--json]` (`read`, `allow`) refreshes metadata itself (`fwupdmgr refresh`) only if it is older than 24 hours, then lists devices and available updates; `--refresh` forces it. `dango firmware update` (`host`, `ask`, takes the dango lock) runs `fwupdmgr update`, which is interactive and may ask to reboot. Never automatic.
- **Verify.** Build the host, `dango switch`; a first `dango firmware` refreshes, then lists the ThinkPad UEFI/EC devices; a second run within 24 hours does not refresh; `--refresh` does; `systemctl list-timers` shows no fwupd refresh timer; the regenerated permissions ask for `dango firmware update` but not for `dango firmware`.
- **Expected diff.** Host: + `fwupd` (in `system-path`), + `unit-fwupd.service`, + its D-Bus/polkit files in `etc`. Home: `dango`.

#### Stage 16: Remove old entry points

- **Changes.** Delete `justfile`, the flake apps except `default`, `home/theme-switcher.nix` (`kit-profile`, the `kit-theme` shim, the `kit/theme-id` file), `KIT_PROFILE_FLAKE`/`KIT_THEME_FLAKE`, the `foundry*` scripts (desktop entries now call `dango foundry open|stop|restart`), `scripts/list-packages.py`, the `homeConfigurations.kit-<id>` outputs (dango only uses `.#kit`; checks and the oracle use `checks.home-<id>`), the fish abbreviations `jc jf jp js nfu` (`home/programs/terminal.nix:6-13`), and `just` from the devShell. Remove the now-dead pre-dango ask rules (`just …`, `nix run .#…`, `kit-profile`, `foundry*`). Replace the README's command sections with a short dango section, so the README never documents removed commands (the full manual is P2.12). **CLAUDE.md:** drop every pre-dango command.
- **Verify.** `dango check`; `scripts/closure-diff HEAD`; after `dango switch`, `command -v kit-profile` fails, and the three Foundry launcher entries still work.
- **Expected diff.** Home (every theme): − `kit-profile`, − `hm_.localbinkit-theme`, − `hm_kittheme-id`, − `foundry`, `foundry-stop`, `foundry-restart`, `foundry-status`, `hm_applicationsfoundryvtt*.desktop` (changed `Exec=`), `hm_fishconfig.fish` (abbreviations). Host: none.

#### Stage 17: Full rename

- **Changes.** Options `kit.*` become `dango.*` (including `kit.repo`), and `kit.profile.*` becomes `dango.theme.*`. The directory `profiles/` moves to `themes/` (the classic `themes/` was deleted in stage 8) and the registry becomes `themes/default.nix`; `lib.themes`, `state.json`'s `theme` and `dango theme` already use the new word. Identity file `~/.config/dango/theme-id`; lock `$XDG_RUNTIME_DIR/dango.lock`; flake description "dangoNix". No migration code is needed: the selection lives in `state.json`, and the theme-id file is only an HM-generated marker of the active theme. **CLAUDE.md:** new names (theme, `themes/`).
- **Verify.** `dango check`; `scripts/closure-diff HEAD` (theme ids and `checks.home-<id>` are unchanged, so every theme is still compared); `cat ~/.config/dango/theme-id` after switching; two competing dango commands still exclude each other on the new lock.
- **Expected diff.** Home (every theme): − `hm_kitprofile-id`, + `hm_dangotheme-id`, `dango` (paths and lock). Host: none.

#### Stage 18: Contract options + `dango doctor`

- **Changes.** Add `themes/contract.nix`: manifest fields (`status` included; Caelestia is marked `experimental`) and the four role kinds, including the "frontend with default" mechanism; provider roles name their user unit. The concrete frontend roles (`keybindings`, `clipboard`, `search`) are registered in the phase-2 goals that ship their core default. The Noctalia module declares every role, taking the values from `themes/noctalia/binds.nix`. Temporary warning mode: missing roles in an experimental theme are warnings until P2.3. `home/dango.nix` writes the active theme's role declarations to `~/.config/dango/roles.json`. Add `dango doctor` (`read`, `allow`): one owner of `org.freedesktop.Notifications` and it is the declared provider; a registered polkit agent (the exact probe is confirmed in this stage against polkit's interfaces; fallback: the declared agent's unit is active and its registration line is in the user journal); a running idle provider; at most one clipboard history writer (exactly one from P2.4). For a theme in warning mode it reports undeclared roles as warnings. **CLAUDE.md:** "experimental themes produce role warnings until Caelestia is brought up to the contract; do not add new ones"; run `dango doctor` after switching a theme.
- **Verify.** `dango check` (the new assertions run; Caelestia's missing roles show up as warnings only); `scripts/closure-diff HEAD`; after `dango switch`, `dango doctor --json` passes in Noctalia; with the Noctalia unit stopped, it fails naming notifications, polkit and idle; after starting it, it passes again.
- **Expected diff.** Home (every theme): `dango` (+ its fish completion), + `hm_.configdangoroles.json`. Host: none.

#### Stage 19: Binds generated from roles

- **Changes.** Recreate `home/hyprland/binds.nix` (deleted in stage 8) as the core bind list, which calls roles, and delete `themes/noctalia/binds.nix`. The input/misc deduplication already happened when stage 8 deleted `home/hyprland/settings.nix`. Every bind becomes a record with a human `description`. Every existing bind is kept as the same full resolved entry (key, action, arguments, flags). Descriptions stay in the Nix data and are not emitted into `hyprland.lua`. Caelestia sets `dango.hyprland.coreBinds = false` until P2.3.
- **Verify.** The stage-11 fixture check passes; `scripts/closure-diff --assert-same HEAD` passes, so `hyprland.lua` is byte-identical for both themes; `nix eval` of the bind data shows a description on every entry; `dango doctor` passes after `dango switch`. If keeping the bind order makes the generator contorted, a reorder is acceptable only if the **sorted** lists of full resolved entries, extracted from the old and new bind data, are equal (so only the order differs), the fixture passes, and `--verify-config` passes; the reordered `hm_hyprhyprland.lua` is then the single expected change.
- **Expected diff.** None (or only `hm_hyprhyprland.lua` if reordered, as above).

#### Stage 20: Contract checks + docs

- **Changes.** Add checks 3 (exactly one enabled provider per required exclusive role; without `clipboard-store`, which arrives in P2.4), 4 (role keys, descriptions, no duplicate resolved keys) and 5. Add `docs/themes.md`: contract, interview checklist, and the deferred items from §2 (`dango.textSize`, the Qt QML skill). **CLAUDE.md:** points at `docs/themes.md` for theme work.
- **Verify.** `dango check`; `scripts/closure-diff --assert-same HEAD`; `dango doctor` passes after `dango switch`. Negative tests in a temporary worktree: unset one role in Noctalia, and `dango check --fast` names it; disable the real provider (`programs.noctalia.systemd.enable = false`), and check 3 reports every exclusive role Noctalia provides (a family assertion may fire too; the test requires check 3's message); enable a second bar (`programs.waybar.enable = true`), and check 3 fails; bind two actions to the same resolved key (`mod .. " + R"` vs `"SUPER + R"`), and check 4 fails.
- **Expected diff.** None.

Stages 2-5 (tooling) are independent of the desktop stages. After stage 8,
`nix flake check` builds 2 homes and 2 Hyprland verifications instead of 7 + 7,
so checks get much faster.

**Phase 1 exit.** After stage 20, I write phase 2's stages into this file from
the goals below and what phase 1 taught (actual derivation names, Noctalia's
`settings.toml` behavior, how the doctor probes worked), and you review them
before any phase-2 work starts.

### Phase 2 (goals, decisions and known risks)

The rules above apply unchanged. Order is decided at phase 1 exit, except that
final docs (P2.12) come second to last and Plymouth (P2.13) is last.

| Goal | What it achieves | Already decided | Known risks |
|---|---|---|---|
| P2.1 Cheatsheet | SUPER+F1 shows every bind; `dango keys [--json]` | `keybindings` frontend role with a core default UI; `~/.config/dango/keys.json` from the same Nix list as `hyprland.lua`; a check asserts they match; SUPER+F1 added to the fixture; works under UA and EN layouts | choice of the core default UI |
| P2.2 Zoom and scale | screen zoom and monitor scale from the keyboard | core binds, runtime only, never persisted, reset by `hyprctl reload`; free keys only; `dango.textSize` stays deferred | Hyprland option names change between releases (a held input) |
| P2.3 Caelestia up to the contract | the contract's first real test; Caelestia gets every core and role bind | delete the warning mode; add the exact-assertion guard check (§2); roles through Caelestia's own IPC/CLI, verified against the locked revision; `coreBinds` on; `palette` and `toolkit` declared (`toolkit` probably `"none"`); fixture updated; revising `themes/contract.nix` is expected but must keep Noctalia identical; `dango doctor` passes in Caelestia | Caelestia's IPC churns; Caelestia may bundle providers that collide with "exactly one" |
| P2.4 Clipboard history | one history that survives theme switches | core store (e.g. cliphist + `wl-paste --watch`, text and images); `clipboard` frontend role; each theme declares its private store, which is disabled (Noctalia's through the named-key step); `dango clipboard [list\|pick\|clear]`, all `ask`; `clipboard-store` exactly one in check 3 and `dango doctor`; negative test: Noctalia's private store declared active fails check 3 | Noctalia's existing history is lost; its UI may not read the core store, so the core picker is used |
| P2.5 Search on SUPER+R | a Spotlight-style search on the existing key | the `launcher` role becomes the `search` frontend; core sources: apps, dango commands with `effect` `read`/`runtime`, calculator, files; `state`/`host` commands never appear; SUPER+Space untouched | backend choice (e.g. Walker, Vicinae) by packaging, cadence and idle cost on battery; replacing a theme launcher changes SUPER+R's fixture entry |
| P2.6 Power automation | power-saver and no animations/blur on battery, automatically | one user service `dango-power`: UPower `OnBattery`, Hyprland `configreloaded`, logind resume, applies state at startup; override in `$XDG_RUNTIME_DIR/dango/power-override`; ppd via `powerprofilesctl`; `dango power`; dependencies in Nix. **Lifetime:** `WantedBy=`, `PartOf=` and `After=graphical-session.target`; when the Hyprland socket closes the service exits, and systemd restarts it in the new session. **Tests:** logout and login, Hyprland restart, boot on battery then login, suspend on AC + unplug + resume, override across unplug/replug and gone after reboot, visuals stay off after `dango switch` on battery | ppd's polkit policy for the active user (else a host polkit rule); a shell or ppd that already switches on battery (must be turned off: one writer); the user manager's `HYPRLAND_INSTANCE_SIGNATURE` must be fresh after a compositor restart |
| P2.7 Foundry and Docker on demand | no Node and no Docker daemon running all day | `systemd.services.foundryvtt.wantedBy = lib.mkForce [ ]`, started by `dango foundry start/open`; `virtualisation.docker.enableOnBoot = false`, `docker.socket` stays | containers with a `restart:` policy no longer come back after reboot until Docker starts |
| P2.8 Battery warning role | exactly one low-battery warning | required role `batteryWarning`; `low-battery-notify` moves to `themes/common/`; a shell that warns by itself drops the timer | shells' own thresholds may differ from today's |
| P2.9 Noctalia wallpaper | the wallpaper survives a fresh install | committed to `assets/`, written through the named-key step (decision 14) | asset size in the repo |
| P2.10 Small cleanups | fewer manual steps and stray packages | git identity in `programs.git`/`programs.gh` (move `~/.gitconfig` aside first, it takes priority); `auto-optimise-store = false` + `nix.optimise.automatic`; `programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ]`; remove Discord; Vesktop to `home/packages.nix`; `ConditionVirtualization=vm` on `spice-vdagent` | none known |
| P2.11 `dango rollback` (optional) | one-command rollback | `dango [--dry] rollback [--home\|--host] [--json]`, `host`/`ask`, a transaction like the others | none known |
| P2.12 Final docs | README is the dangoNix manual; `CLAUDE.md` matches §5 | your Ukrainian intro kept, then the command table, fresh install and remaining manual steps; mark this plan done | none |
| P2.13 Plymouth (last) | a neutral boot splash | `hosts/nixos/boot.nix`, host-owned; `bgrt` theme proposed; `boot.initrd.systemd.enable`; quiet boot; SDDM + `thyx` unchanged; `systemd-analyze` baseline before, median within about 1 s after 3 reboots; rollback via the boot menu | systemd initrd changes early boot (LUKS, fingerprint, resume) |

### Optional changes, decided 2026-10-13

- **Accepted, now goals:** Foundry and Docker on demand (P2.7), battery warning as a role (P2.8), scheduled store optimisation, Proton-GE and small cleanups including dropping Discord (P2.10).
- **Rejected:** ThinkPad charge limit. It keeps charging to 100 %.

### Considered, not planned (2026-10-13)

These were raised and deliberately left out of this plan. Each would need its own decision and stage later.

- **Screen capture extras:** OCR, colour picker, screen recording.
- **Dev and agent workflow:** an agent hotkey and theme sync to Claude Code, tmux dev layouts, git worktree helpers, timed passwordless `sudo`, declarative Claude Code settings.
- **Small desktop features:** calculator and emoji hotkeys, LocalSend, Wi-Fi QR codes, web apps, reminders, a screensaver.
- **Data safety:** encrypted off-site backups of `/home`, `/home` snapshots, secrets in the repo (sops-nix or agenix), FIDO2 for `sudo`. Note that **NixOS generations do not protect `/home`**. Rollback restores the system and the Home Manager configuration, not your files, Foundry worlds (`/var/lib/foundryvtt`) or app state. Today nothing in this plan protects that data.

## 5. Tooling to drop, and why

| Drop | Why |
|---|---|
| Graphify: the package, `home/graphify.nix`, `graphify-nix/` (extractor + tests), the patch, the flake input, `graphify-out/` | For 3.3k lines of Nix, `rg` plus reading the file is faster and exact. The local extractor and the patch are pinned to upstream internals, so every Graphify bump is a maintenance task. Query output is noisy at this size (245 nodes, mostly Zed colour options). The 34 MB of output is permanently dirty state. Agents verify against source anyway. |
| Codex files: `.codex/hooks.json`, the HM-installed `~/.codex/AGENTS.md`, `~/.codex/skills/graphify`, the repo `AGENTS.md` (already deleted in the baseline) | Claude Code only (decision 7). The hook ran Graphify on every Codex Bash call. Kept (decided): Zed's `codex-acp` agent server (`home/zed.nix:136-145`) is an editor feature, not repo tooling. |
| The embedded flake source (`profileFlakeSource`) | It made every commit a new home generation and made out-path comparison useless. Removed first, in stage 2. |
| `justfile` | Nine thin aliases over `nix run`, plus a package lister. Replaced by dango. |
| Flake apps `check`, `fmt`, `hyprland-check`, `theme-check`, `foundry-check`, `switch`, `home-switch` | Five ways to do one thing. Replaced by `apps.default` (dango) and the `formatter` output. |
| `kit-profile`, the `kit-theme` shim, the `kit/theme-id` file, `KIT_THEME_FLAKE`, `KIT_PROFILE_FLAKE` | Replaced by `dango theme` and `DANGO_FLAKE`. These were compatibility layers for a migration that is finished. |
| `foundry`, `foundry-stop`, `foundry-restart`, `foundry-status` | Become `dango foundry …`. The three launcher entries stay and call dango. |
| `scripts/list-packages.py` | Regex-parsing Nix gives wrong answers. If a package list is ever needed, `nix eval` the `home.packages` names. |
| Fish abbreviations `jc`, `jf`, `jp`, `js`, `nfu` | The first four point at the justfile; `nfu` bypasses the update gate and the held list. |
| Grep-based and hard-coded checks, the override canary, alias checks | Replaced by the generic checks in `lib/checks.nix` and family-module assertions. |
| Stylix and the `dms` input | Only used by the retired themes. The `caelestia` input stays (decision 1). |
| The command matrix and bootstrap ritual in `README.md` | The README becomes a short manual for dango. |

### Agent tooling added (stage 5)

| Add | Why |
|---|---|
| Claude Code CLI (`pkgsUnstable.claude-code`, in the baseline; self-updater confirmed off in stage 5) | Pinned by `flake.lock` and gated by `dango update`, like every other input. It also closes the fresh-install gap. |
| `mcp-nixos` 2.4.3 (pinned package + committed `.mcp.json`) | Real NixOS/Home Manager package and option names, plus nix.dev, the Wiki and Noogle, instead of guessed names. It is optional and narrow, unlike Graphify's mandatory first step. |
| `.claude/settings.json` permissions + one fail-closed Bash hook | Deterministic guardrails. `hardware-configuration.nix` is denied to Edit/Write and blocked in Bash commands that name it. The hook lives at the fixed path `~/.config/dango/hooks/bash-guard` and is called as `<path> \|\| exit 2`, so a missing file or any error blocks. From stage 13 the rules are generated from the command table's `agent` field. |
| `claude-md-management` (official plugin) | Keeps `CLAUDE.md` audited and short. It is the only plugin. |
| Not added: hookify, formatting hooks | The static check already fails on unformatted files, and the guards fit in native permissions plus one hook. |
| Deferred: TheQtCompanyRnD/agent-skills | Only when the first custom Quickshell theme is built (noted in `docs/themes.md`, stage 20). |

### Agent docs target

This is the **final** `CLAUDE.md` (P2.12). Each earlier stage writes only the
parts that exist at that point (see the "CLAUDE.md:" notes in §4). Aim for
under 60 lines, in English:

- What the repo is, in two sentences. It is a single machine.
- Invariants:
  - never edit `hardware-configuration.nix`;
  - switching a theme never changes the host;
  - every theme in the registry passes `dango check`; `experimental` never relaxes checks;
  - never remove or rebind an existing key or drop a bind's flags; new binds only on free keys, and the bind fixture changes only with a declared behavior change;
  - clipboard history and search sources are core; themes only add UI;
  - Noctalia's `settings.toml` wins over declarations; runtime keys are enforced only through the named list;
  - commands marked `agent = ask` in `dango commands --json` (switching, updating, theme changes, Foundry service control and configuration, firmware updates, clipboard history) and `sudo` only when asked; `dango --dry …` is always allowed;
  - `state.json` holds your choices: agents change it only when asked.
- The loop: edit → `nix fmt` → `dango check --fast` → `dango check` → `scripts/closure-diff --assert-same HEAD`, or the stage's expected changes; explain any difference. After switching a theme: `dango doctor`.
- Tests that change state or code on purpose run in a temporary worktree, never in the checkout.
- Commits: stage files explicitly; never `git commit -a`.
- Discovering commands: `dango commands --json`. Every command has `--json`, and every non-`read` one has `--dry`.
- Nix names: "Look up option and package names with mcp-nixos before writing them when unsure, and query the 26.05 channel; it does not know options from flake inputs (Noctalia, Caelestia, nix-foundryvtt) — read their source for those." Optional, never a mandatory first step.
- The permission rules as one-line reminders. `.claude/settings.json` enforces them. The Bash hook on `hardware-configuration.nix` is a strong guard, not a guarantee; the final check is your review of the diff. `claude-md-management` keeps the file audited and under about 60 lines.
- Where things live: one line per top-level directory.
- How to add a theme: point at `docs/themes.md`.

Nothing else. The README is for you; `CLAUDE.md` is for agents. Neither repeats the other.

## 6. Follow-up decisions

2026-10-13:

- **Noctalia telemetry:** off (stage 14, as a named key).
- **Noctalia palette:** runtime state, not declared, because Noctalia is temporary.
- **Foundry:** on demand with manual start (P2.7).
- **Docker:** on demand (P2.7).
- **Zed's `codex-acp`:** stays.
- **Config edits by dango:** allowed. They go to one tracked `state.json`, and you commit (decision 4; stage 12).
- **Caelestia:** stays as an experimental second theme and is brought up to the contract in P2.3. The warning mode exists only from stage 18 to P2.3; P2.3 deletes it and guards it with an exact-assertion fixture check.
- **Single machine**, no multi-host abstraction.
- **Clipboard and search:** core owns the data, themes own the UI (decision 12; P2.4, P2.5).
- **Keys:** every existing bind stays; cheatsheet on SUPER+F1; search on SUPER+R (decision 11).
- **Boot and login:** SDDM keeps `thyx`; Plymouth is the last goal, with a boot-time baseline and the boot menu as the rollback path (decision 10; P2.13).
- **fwupd:** refresh timer off; `dango firmware` refreshes metadata only if it is older than 24 hours (`--refresh` forces it) (stage 15).
- **Agent tooling (stage 5):**
  - Claude Code CLI from nixpkgs-unstable, self-updater off.
  - mcp-nixos pinned at 2.4.3; agents query the 26.05 channel.
  - Only the `claude-md-management` plugin. If its auto-update cannot be turned off per marketplace, that is an accepted exception to decision 6, because it only edits `CLAUDE.md` and you see that in the diff.
  - No hookify, no formatting hook.

2026-10-14 (after the first review):

- **Oracle:** the embedded flake source goes in stage 2. From stage 3, "none" means identical out paths (`scripts/closure-diff --assert-same`); `nix-diff` explains differences; non-empty stages list their exact changed derivations. The tool uses `lib.themes` + `checks.home-<id>`, fails on zero themes, and is verified across a simulated rename.
- **Command table:** `effect` (`read | runtime | state | host`) drives search, the `--json` verification and the lock; a separate `agent` (`allow | ask`) drives the Claude Code permissions. Overrides: Foundry service control and the clipboard history are `ask` despite a `read`/`runtime` effect.
- **Power:** one user-level service (UPower, Hyprland config reload, resume, startup); override in `$XDG_RUNTIME_DIR` (P2.6).
- **Pinning:** no `?rev=` pins; `flake.lock` plus a held list in `dango update`.
- **Activation order:** host first, then home, everywhere; `dango switch` refuses for any user other than the configured one.
- **Guard hook:** fixed path `~/.config/dango/hooks/bash-guard`, called as `<path> || exit 2` because Claude Code blocks only on exit 2; dependencies in Nix; negative tests with a stripped PATH and with the hook file removed.
- **CLAUDE.md** describes only what exists; stages that change agent-relied behavior update it in the same commit.
- **Scope:** replaced by the explicit list of behavior changes at the top.
- **Zoom and scaling** stay a goal (P2.2); `dango.textSize` is deferred to the first custom Quickshell theme (§2).
- **Kernel:** stays `linuxPackages_latest`; the default-kernel stage is dropped.
- **Commits:** stage files explicitly, never `git commit -a`.
- **Vocabulary:** "theme" instead of "profile" (decision 2, revised). New interfaces use it from the start; existing code is renamed in stage 17.

2026-10-14 (after the second review):

- **Baseline first:** stage 0 summarizes the uncommitted work and, after your approval, commits it as `redesign-baseline`; every comparison descends from it. Stage 5 no longer adds Claude Code, only confirms its self-updater is off.
- **Host in the gate:** `dango check` (and `nix flake check`, via the `host` check from stage 11) builds the host toplevel. `dango update` is tested for real in a temporary worktree: held inputs skipped, explicit override updates them, forced failure restores `flake.lock` byte-for-byte (compared by hash).
- **Transactions:** one lock around the whole mutation (`state.json` edit, build, activation, recovery). Recovery restores `state.json` and re-activates the previous host and home generations. Tested with a changed host, an injected host-activation failure, an injected home failure after linking, and competing commands.
- **Noctalia runtime precedence:** `settings.toml` wins; a named-key activation step sets only listed keys (telemetry now, the private clipboard store in P2.4, the wallpaper in P2.9). Verification backs up the sidecar, never deletes it, and restores it.
- **Fresh install with Foundry:** the ZIP is imported before the first switch; `dango switch` preflights the payload and names `dango foundry version <zip>`.
- **Foundry state:** `state.json` keeps only `enable` + `version`; the ZIP is validated against nix-foundryvtt's own version table.
- **Bind fixtures:** full resolved entries including flags and arguments; an accepted reorder must compare equal after sorting.
- **Providers:** required exclusive roles need exactly one enabled provider, with a negative test that disables the real one; `dango doctor` checks the same at runtime and runs after every switch in role stages.
- **Power lifetime:** `PartOf=`/`After=graphical-session.target`; exits when the Hyprland socket closes and is restarted in the new session; tested across logout/login, Hyprland restart and boot on battery (P2.6).
- **Rolling wave:** phase 1 detailed (stages 0-20), phase 2 as goals; no more full-plan reviews.
- **Corrections found while revising:** the stage-1 plan commit (and the baseline) change the home out path while the repo is still embedded, so their expected diff is not "none"; the oracle's simulated rename moves `profiles/` to `shells/`, because `themes/` still exists at stage 3; the README loses its removed commands in stage 16 instead of waiting for the final docs.

Open questions: none.
