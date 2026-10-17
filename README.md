# dangoNix

Мій NixOS + Home Manager для одного ThinkPad: Hyprland, змінні теми (Noctalia, Caelestia) і одна CLI `dangonix`. Навіщо і куди це рухається — [бачення](docs/vision.md).

## Документи
- [vision](docs/vision.md) — що це, цілі, чому NixOS.
- [design](docs/design.md) — цільова архітектура: контракт тем, `dangonix`, енергія, трафік, Foundry, відбиток, безпека.
- [current-state](docs/current-state.md) — теперішній стан репо і його недоліки.
- [remake](docs/remake.md) — кампанія перебудови: квести, правила, твоя участь.
- [tasks](docs/tasks.md) — завдання для агентів (англ.), по розділу на квест.

> Нижче — мануал **поточних** команд. Він діє до квесту c1q18, де `dangonix` замінить старі точки входу і цей розділ стане коротким мануалом `dangonix`.

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
- `home/`: invariant Home Manager modules and the Hyprland substrate.
- `profiles/`: the explicit profile registry, classic family, and external-shell adapters.
- `themes/`: the four classic palette variants.

## Desktop profiles

The desktop is one invariant Home Manager environment plus exactly one
ordinary selected profile module. The registry currently provides
`catppuccin` (default), `tokyo-night`, `gruvbox`, `kit-dark`, `dms`,
`noctalia`, and `caelestia`.

The four classic palettes share one profile family, including Waybar, Dunst,
SwayOSD, awww, Hyprlock, Hypridle, Wlogout, screenshots, and classic binds.
External shells are isolated adapters with their own Home Manager/systemd
lifecycle. NixOS owns invariant host capabilities; profile switching does not
rebuild the host.

Activate user-owned changes:

```sh
home-manager switch --flake .#kit
just home-switch
nix run .#home-switch
```

### Terminal profile switching

`kit-profile` selects among the profiles embedded in the installed flake
revision. `kit-theme` remains a compatibility alias. Both can be run from any
directory:

```sh
kit-profile list
kit-profile list --json
kit-profile current
kit-profile switch gruvbox
```

The available IDs are `catppuccin`, `tokyo-night`, `gruvbox`, `kit-dark`, `dms`,
`noctalia`, and `caelestia`.
Missing generated identity reports the default `catppuccin`; a malformed or
unknown identity is an error. Every Home Manager generation writes its
declarative identity to `$XDG_CONFIG_HOME/kit/profile-id` and a migration-
compatible `$XDG_CONFIG_HOME/kit/theme-id` (falling back to `$HOME/.config/kit/`).
Switching and `just home-switch` take the same nonblocking per-user activation lock at
`$XDG_RUNTIME_DIR/kit-home-activation.lock`, or at
`$XDG_STATE_HOME/kit/home-activation.lock` (falling back to
`$HOME/.local/state/kit/home-activation.lock`).

Normal configuration changes still use `home-manager switch --flake .#kit`
(default Catppuccin) or a named profile:

```sh
home-manager switch --flake .#kit-catppuccin
home-manager switch --flake .#kit-tokyo-night
home-manager switch --flake .#kit-gruvbox
home-manager switch --flake .#kit-dark
home-manager switch --flake .#kit-dms
home-manager switch --flake .#kit-noctalia
home-manager switch --flake .#kit-caelestia
```

Home Manager's normal `sd-switch` lifecycle starts and stops profile-owned
services. The selector does not know provider names and performs no service
convergence. `KIT_PROFILE_FLAKE` is the canonical flake override;
`KIT_THEME_FLAKE` remains a compatibility fallback. Profile-local shell state
may persist while inactive; shared GTK, Qt, terminal, editor, and browser state
is not imperatively rewritten.

Activate system-owned changes:

```sh
sudo nixos-rebuild switch --flake .#nixos
just switch
nix run .#switch
```

`just home-switch` preserves the currently active generated profile while
rebuilding it from the current checkout, using `.#kit` only as a first-activation
bootstrap. For the
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
