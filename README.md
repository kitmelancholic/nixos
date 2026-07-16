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
- `themes/`: the fixed declarative Catppuccin theme.

## Themes

The desktop uses one fixed dark Catppuccin (Mocha) theme. Theme, wallpaper,
Hyprland, Waybar, Zed, user packages, and other `home/` changes belong to
Home Manager; host services, drivers, and system policy belong to NixOS.

Activate user-owned changes:

```sh
home-manager switch --flake .#kit
just home-switch
nix run .#home-switch
```

Activate system-owned changes:

```sh
sudo nixos-rebuild switch --flake .#nixos
just switch
nix run .#switch
```

For the first migration from the embedded configuration, activate standalone
Home Manager first with `just home-switch`, then switch NixOS with
`just switch`. If activation encounters a file collision, retry with
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
