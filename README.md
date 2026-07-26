# kitOS NixOS Configuration

Personal NixOS + Home Manager configuration for the `nixos` host and `kit` user.

## Common Commands

```sh
just fmt
just check
just hyprland-check
just foundry-check
```

Direct flake equivalents:

```sh
nix run .#fmt
nix run .#check
nix run .#hyprland-check
nix run .#foundry-check
```

Rebuild the system:

```sh
nix run .#switch
```

## Layout

- `flake.nix`: inputs and output wiring.
- `lib/repo-apps.nix`: repo commands and checks.
- `hosts/nixos/`: host-level wiring and hardware config.
- `hosts/nixos/configuration.nix`: host core policy and system identity.
- `hosts/nixos/hardware.nix`: hand-written hardware policy around generated hardware configuration.
- `hosts/nixos/desktop.nix`: display manager, Hyprland, PipeWire, fonts, portals, and desktop plumbing.
- `hosts/nixos/workloads.nix` and `hosts/nixos/foundryvtt.nix`: gaming, streaming, Docker, and FoundryVTT ownership.
- `home/`: user-owned Home Manager desktop/program modules, Hyprland, Waybar, Zed, packages, and entrypoint.
- `themes/`: the declarative Catppuccin, Tokyo Night, Gruvbox, and Kit Dark profiles.

## Themes

The desktop has four immutable Home Manager profiles: `catppuccin` (the
default), `tokyo-night`, `gruvbox`, and `kit-dark`. Shared Home Manager
defaults are composed with one selected module from `themes/<theme-id>/`.
Theme modules may override appearance and user-owned desktop behavior;
host services, drivers, and system policy belong to NixOS.

Activate user-owned changes:

```sh
home-manager switch --flake .#kit
just home-switch
nix run .#home-switch
```

### Terminal theme switching

`kit-theme` selects among the profiles embedded in the installed flake
revision. It can be run from any directory:

```sh
kit-theme list
kit-theme current
kit-theme switch gruvbox
```

The available IDs are `catppuccin`, `tokyo-night`, `gruvbox`, and `kit-dark`.
Missing generated identity reports the default `catppuccin`; a malformed or
unknown identity is an error. Every Home Manager generation writes its active
theme to `$XDG_CONFIG_HOME/kit/theme-id` (falling back to
`$HOME/.config/kit/theme-id`), so direct named-profile activation stays in
sync with `kit-theme current`. Switching takes a nonblocking per-user lock at
`$XDG_RUNTIME_DIR/kit-theme-switch.lock`, or in the private state directory
when no runtime directory exists.

Normal configuration changes still use `home-manager switch --flake .#kit`
(default Catppuccin) or a named profile:

```sh
home-manager switch --flake .#kit-catppuccin
home-manager switch --flake .#kit-tokyo-night
home-manager switch --flake .#kit-gruvbox
home-manager switch --flake .#kit-dark
```

After activation, `kit-theme` reloads live Hyprland, Waybar, Dunst, SwayOSD,
and the wallpaper service. From a TTY or without a graphical session it skips
inactive graphical components; a successful Home Manager activation still
records the new marker. `KIT_THEME_FLAKE` may override the baked flake source
for testing a newer checkout. Theme switching never runs NixOS activation or
changes the system boot generation.

Activate system-owned changes:

```sh
sudo nixos-rebuild switch --flake .#nixos
just switch
nix run .#switch
```

`just home-switch` rebuilds the currently active generated theme from the
current checkout, using `.#kit` only as a first-activation bootstrap. For the
first migration from the embedded configuration, activate standalone Home
Manager first with `just home-switch`, then switch NixOS with `just switch`.
If activation encounters a file collision, retry with
`home-manager switch -b hm-backup --flake .#kit`.

```sh
home-manager switch --flake .#kit
```

## Hyprland

The Home Manager Hyprland config generates Lua. Validate it before rebuilding:

```sh
just hyprland-check
```

That command builds the authoritative flake Hyprland check, which generates the Home Manager `hyprland.lua`, runs `luac -p`, then runs:

```sh
Hyprland --verify-config --config <generated-file>
```

## FoundryVTT

FoundryVTT is configured through `nix-foundryvtt` in `hosts/nixos/foundryvtt.nix`.

The service listens on TCP `30000`, and the firewall opens that port. Foundry itself is proprietary, so follow the upstream `nix-foundryvtt` instructions for providing the required Foundry package payload/license material before rebuilding.

Validate the configured Foundry version and local payload:

```sh
just foundry-check
```

After switching the system, Foundry runs as `foundryvtt.service` and is available at:

```text
http://127.0.0.1:30000
```

The Home Manager config also adds launcher entries and helper commands:

```sh
foundry          # start the service if needed, then open the web UI
foundry-stop     # stop the service
foundry-restart  # restart the service, then open the web UI
foundry-status   # show service status
```

Launcher entries:

- `Foundry VTT`
- `Stop Foundry VTT`
- `Restart Foundry VTT`

## Package Ownership

System packages are kept for drivers, services, and rescue/debug basics. User-facing applications and daily CLI tools live in `home/packages.nix` and Home Manager modules.

The Graphify Nix extractor remains maintained locally because no compatible pinned upstream or fork was established during the refactor. Its integration suite includes real-repository smoke coverage for `query`, `path`, and `explain`.
