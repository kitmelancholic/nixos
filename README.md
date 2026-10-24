# dangoNix

Мій NixOS + Home Manager для одного ThinkPad: Hyprland, змінні теми (Noctalia, Caelestia) і одна CLI `dangonix`. Навіщо і куди це рухається - [бачення](docs/vision.md).

## Документи
- [vision](docs/vision.md) - що це, цілі, чому NixOS.
- [design](docs/design.md) - цільова архітектура: контракт тем, `dangonix`, енергія, трафік, Foundry, відбиток, безпека.
- [pre-historic-state](docs/pre-historic-state.md) - стан репо на c1q00 (точка відліку) і його недоліки.
- [remake](docs/remake.md) - кампанія перебудови: квести, правила, твоя участь.
- [tasks](docs/tasks.md) - завдання для агентів (англ.), по розділу на квест.

## dangonix

Усе робиться однією командою `dangonix` (`nix run . -- …`, поки вона не встановлена):

```sh
dangonix help             # список команд
dangonix switch           # зібрати і застосувати хост і home
dangonix theme            # поточна тема; зміна: dangonix theme <id>
dangonix check            # перевірки (--fast: лише оцінка, без збірки)
dangonix foundry          # екземпляри Foundry: list, status, start, stop, open
```

Форматування - `nix fmt`. Повний перелік: `dangonix --dry --json commands`.

## Layout

- `flake.nix`: inputs and output wiring.
- `lib/dangonix/`: the `dangonix` CLI; `lib/repo-apps.nix`: formatter and static check commands.
- `hosts/nixos/`: host-level wiring and hardware config.
- `hosts/nixos/configuration.nix`: host core policy and system identity.
- `hosts/nixos/hardware.nix`: hand-written hardware policy around generated hardware configuration.
- `hosts/nixos/desktop.nix`: display manager, Hyprland, PipeWire, fonts, portals, and desktop plumbing.
- `hosts/nixos/workloads.nix` and `hosts/nixos/foundryvtt.nix`: gaming, streaming, Docker, and FoundryVTT ownership.
- `home/`: invariant Home Manager modules and the Hyprland substrate.
- `profiles/`: the theme registry and the shell adapters (Noctalia, Caelestia).

## Desktop profiles

Робочий стіл - одне незмінне Home Manager-середовище плюс рівно один профіль
(тема). Реєстр: `noctalia` (типова) і `caelestia`. Теми не змінюють хост;
перемикання - `dangonix theme <id>`.

## Hyprland

Home Manager генерує Lua-конфіг Hyprland; `dangonix check` збирає перевірку
`hyprland-<id>` (`luac -p` і `Hyprland --verify-config`).

## FoundryVTT

FoundryVTT налаштовано через `nix-foundryvtt` у `hosts/nixos/foundryvtt.nix`.
Сервіс слухає TCP `30000`; payload і ліцензію дає користувач за інструкцією
`nix-foundryvtt`. Керування: `dangonix foundry …`; пункти меню `Foundry VTT`,
`Stop Foundry VTT`, `Restart Foundry VTT` викликають `dangonix foundry open|stop|restart`.

## Package Ownership

System packages are kept for drivers, services, and rescue/debug basics. User-facing applications and daily CLI tools live in `home/packages.nix` and Home Manager modules.
