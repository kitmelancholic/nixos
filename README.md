# kitOS NixOS Configuration

Personal NixOS + Home Manager configuration for the `nixos` host and `kit` user.

## Common Commands

```sh
just fmt
just check
just hyprland-check
```

Direct flake equivalents:

```sh
nix run .#fmt
nix run .#check
nix run .#hyprland-check
```

Rebuild the system:

```sh
nix run .#switch
```

## Layout

- `flake.nix`: inputs, outputs, repo commands, checks.
- `hosts/nixos/`: host-level wiring and hardware config.
- `modules/nixos/core/`: boot, locale, Nix, user, base packages, `nix-ld`.
- `modules/nixos/desktop/`: display manager, Hyprland system integration, PipeWire, fonts, portals, desktop plumbing.
- `modules/nixos/profiles/`: normal personal workloads: development, gaming, streaming, FoundryVTT.
- `home/`: user config for Hyprland, Waybar, Zed, packages, and Home Manager entrypoint.
- `modules/home/`: reusable Home Manager desktop/program modules.
- `themes/`: theme data and selected theme.

## Themes

List themes:

```sh
just theme
```

Select a theme:

```sh
just theme catppuccin
```

List wallpapers:

```sh
just wallpaper
```

Theme selection updates `themes/selected.nix`, which is intentional: Git flakes only see tracked files reliably during rebuilds.

## Hyprland

The Home Manager Hyprland config generates Lua. Validate it before rebuilding:

```sh
just hyprland-check
```

That command generates the Home Manager `hyprland.lua`, runs `luac -p`, then runs:

```sh
Hyprland --verify-config --config <generated-file>
```

## FoundryVTT

FoundryVTT is configured through `nix-foundryvtt` in `modules/nixos/profiles/foundryvtt.nix`.

The service listens on TCP `30000`, and the firewall opens that port. Foundry itself is proprietary, so follow the upstream `nix-foundryvtt` instructions for providing the required Foundry package payload/license material before rebuilding.

## Package Ownership

System packages are kept for drivers, services, and rescue/debug basics. User-facing applications and daily CLI tools live in `home/packages.nix` and Home Manager modules.
