# dangoNix — поточний стан репозиторію

Стан на 2026-10-16. Код — ще kitOS (`flake.nix`: `description = "kitOS v0.16.3"`), жоден stage remake'у не виконано. Ціль — [design](design.md).

**Гілки.** На GitHub `main` = `ff258ef` (plan + routine). Гілка `redesign` (`804b792` baseline → `ff258ef` → `24b4691` routine review fixes) існує **тільки локально** на ноутбуці, тому хмарні агенти бачать лише `main`.

## 1. Що є
- **Розмір:** ~3.3k рядків Nix, з них `flake.nix` — 285 (≈120 — checks).
- **Inputs:** nixpkgs 26.05 + unstable, home-manager 26.05, hyprland (git master), noctalia, caelestia, dms, stylix, thyx, foundryvtt, zen-browser, claude-desktop-extra, graphify + pyproject-nix/uv2nix (pdf2md).
- **Хост** `hosts/nixos/`: `configuration.nix` (kernel `linuxPackages_latest`), `hardware.nix` (thermald), `desktop.nix` (SDDM + thyx, Hyprland, PipeWire, ppd, host hyprlock, hyprpolkitagent), `workloads.nix` (gaming, streaming, Docker), `foundryvtt.nix`.
- **Home** `home/`: інваріантне середовище + Hyprland (Lua), класичні модулі (waybar, osd, power, screenshots, wallpaper, theme), `theme-switcher.nix` (`kit-profile`), foundry, graphify, pdf2md, zed, claude-desktop.
- **Теми (у коді — "profiles")** — реєстр `profiles/default.nix`, default `catppuccin`:
  - classic family: `catppuccin`, `tokyo-night`, `gruvbox`, `kit-dark` (палітри в `themes/`; Waybar, Dunst, SwayOSD, awww, Hyprlock, Hypridle, Wlogout);
  - external shells: `dms`, `noctalia`, `caelestia`.
- **Agent tooling:** Graphify (`graphify-nix/`, patch, `home/graphify.nix`, 37 MB `graphify-out/`), `.codex/hooks.json`, `.claude/` (`/quest`, `git-guard`, `ref-guard`), `scripts/campaign`, `scripts/quest-verify`, `CLAUDE.md` (тільки build output і git правила).

## 2. Що добре (лишаємо)
- **Host і home розділені.** Standalone Home Manager — зміна теми не перебудовує NixOS.
- **Один явний реєстр тем**, без auto-discovery.
- **Реальна валідація:** кожна тема збирає activation package, її `hyprland.lua` проходить `luac -p` і `Hyprland --verify-config`.
- **Безпечна активація:** per-user lock; identity file змінюється тільки після успішної активації.
- **Foundry зроблено добре:** один pin версії, перевірка payload і GC root, NOPASSWD sudo лише для трьох точних `systemctl` команд.
- **"Why"-коментарі** там, де поведінка неочевидна.
- **`writeShellApplication` скрізь** — shellcheck під час build.
- **Static checks** (treefmt, statix, deadnix) у `nix flake check`.

## 3. Недоліки

### Command surface (ціль 5)
Одна дія — до п'яти точок входу:

| Дія | Точки входу |
|---|---|
| Застосувати home | `just home-switch`, `nix run .#home-switch`, `home-manager switch --flake .#kit`, `… .#kit-<id>` |
| Змінити тему | `kit-profile switch`, `kit-theme`, `home-manager switch --flake .#kit-<id>` |
| Застосувати host | `just switch`, `nix run .#switch`, `sudo nixos-rebuild switch --flake .#nixos` |
| Перевірка | `just check`, `just theme-check`, `just hyprland-check`, `nix run .#…`, fish `jc` |
| Foundry | `foundry`, `foundry-stop`, `foundry-restart`, `foundry-status`, `just foundry-check` |

- README вже розійшовся з кодом: `.#kit-dark` не існує (output — `kit-kit-dark`).
- Order-sensitive bootstrap (home → host, `-b hm-backup` при колізії) задокументований замість того, щоб його робив інструмент.

### Два джерела правди для flake
- `kit-profile` switch'ить з копії репо в store, `just home-switch` — з checkout'у. Зміна теми мовчки ігнорує незакомічені правки.
- Копія репо в home closure: кожен коміт (навіть typo в README) = нова home generation. Через це неможливо довести "нічого не змінилось" порівнянням out paths.

### Дубльована логіка
- Activation lock і таблиця profile → output написані двічі (`lib/repo-apps.nix`, `home/theme-switcher.nix`).
- Hyprland input/misc settings — двічі (`invariant-settings.nix`, `settings.nix`).
- ~70% `profiles/noctalia/binds.nix` — копія `home/hyprland/binds.nix`; відрізняються тільки launcher, session, osd, screenshot.

### Перевірки
- Частина — text grep по source-файлах (`selectorArchitectureCheck`).
- Частина — hard-coded назви тем (`profileOwnershipCheck`).
- Canary тільки для classic family (`themeOverrideCanary`).
- Три alias'и, що збирають те саме під іншими іменами (`theme`, `hyprland`, `home`).
- **Жодна не збирає host toplevel** — host-only помилка (напр. kernel) проходить усі checks.

### Немає контракту тем
`dms` і `caelestia` мають **0 Hyprland binds**, Stylix/GTK/hyprlock/hypridle вимкнені: ні SUPER+Return, ні клавіш гучності. Нічого це не впіймало, бо ніщо не визначає, що тема мусить дати.

### Стабільність (ціль 1)
- `hyprland` трекає git master, `noctalia` і `caelestia` — default branches; будь-який `nix flake update` їх бампає.
- Fish `nfu` — ungated `nix flake update`.

### Енергія і фон (цілі 2-3)
- Тільки ppd і thermald; на відключення від мережі ніщо не реагує.
- `foundryvtt.service` стартує при boot і цілий день тримає Node; Docker — теж при boot.
- `low-battery-notify` полить кожні 5 хв і, ймовірно, дублює попередження Noctalia.
- На мережі немає ощадливого режиму, тож зарядитись швидше під навантаженням нічим.
- Ніщо не реагує на лімітне з'єднання (хотспот): оновлення і фонові завантаження йдуть як завжди.

### Foundry
Один інстанс, одна версія, один `/var/lib/foundryvtt`: тримати світи під різні версії поруч неможливо.

### Agent tooling (ціль 6)
- Graphify: 1287-рядковий Nix extractor + тести, patch проти upstream internals, flake input, 92-рядковий модуль, hook на кожен Codex Bash call, 37 MB output — для 3.3k рядків Nix. Запит "how are desktop themes selected" дав 245 вузлів, переважно Zed syntax colours.
- `AGENTS.md` робив Graphify обов'язковим (вже видалений); `CLAUDE.md` майже порожній.

### Дрібне
- **Naming drift:** kitOS, `kit-profile`/`kit-theme`, `profile-id`/`theme-id`, `KIT_PROFILE_FLAKE`/`KIT_THEME_FLAKE`; checks звуться "theme", код — "profile".
- `scripts/list-packages.py` (180 рядків) парсить Nix регулярками.
- Stylix і `dms` input потрібні лише темам, які йдуть під видалення.
- Host `hyprlock` і невикористаний системний `hyprpolkitagent`.

## 4. Ручні кроки на fresh install (ціль 4: кожен — дефект)

| # | Ручний крок | Статус у remake |
|---|---|---|
| 1 | Згенерувати `hardware-configuration.nix` | inherent, pre-step |
| 2 | Увімкнути flakes в installer'і | bootstrap з `--extra-experimental-features` |
| 3 | Bootstrap: home → host, `-b hm-backup` | `dangonix switch [--backup]` |
| 4 | Створити юзера `kit` | inherent; dangonix відмовляє іншим юзерам |
| 5 | Foundry payload: `nix-store --add-fixed` + ручний GC root | `dangonix foundry import <zip>` |
| 6 | Foundry licence, admin password, worlds | inherent data; задокументувати backup |
| 7 | Noctalia `settings.toml`: палітра, wallpaper, `telemetry_enabled = true`, lockscreen widgets | telemetry і wallpaper — named keys; палітра — runtime за рішенням |
| 8 | Noctalia plugins ставляться в runtime | задекларувати, якщо можливо |
| 9 | Git identity в unmanaged `~/.gitconfig` | `programs.git`/`programs.gh` |
| 10 | Proton-GE через `protonup-qt` | `programs.steam.extraCompatPackages` |
| 11 | Fingerprint, Wi-Fi, Bluetooth, логіни, SSH keys, `gh auth` | inherent / secret |
| 12 | EasyEffects presets | можна задекларувати пізніше |
| 13 | Вибрана тема — локальний стан (`~/.config/kit/profile-id`) | `state.json` |
| 14 | Логін у Claude Code | inherent |
