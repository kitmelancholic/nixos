# dangoNix — design doc

Як [бачення](vision.md) реалізується. Описує **цільовий** стан; що є зараз — [current-state](current-state.md), як дійти — [remake](remake.md). Кожен факт про цільовий стан живе тільки тут; інші доки посилаються на секції.

## 1. Принципи
1. **Хост володіє можливостями, тема — виглядом.** Тема ніколи не вимагає зміни хоста. Якщо майбутній темі потрібна host-можливість (напр. PAM service), її додають у хост безумовно, до появи теми. Boot splash і greeter — host-owned, однакові для всіх тем.
2. **Checkout — єдине джерело правди.** Все працює з `~/nixos` (або `--flake`, `$DANGONIX_FLAKE`). Копії репо в home closure немає, тому docs-only коміт не змінює жодного out path.
3. **Спочатку зібрати все, потім активувати, хост першим.** Хост створює юзера, групи і Hyprland, від яких залежить home.
4. **Вибір — це дані, зміна вибору — одна транзакція.** Все, що може змінити команда, лежить у `state.json`.
5. **Ядро володіє даними, тема — UI.** Clipboard history і джерела пошуку — інваріантні сервіси.
6. **Machine-readable first.** Кожна команда має `--json`; одна таблиця команд генерує все інше.
7. **Кожна перевірка generic по реєстру.** Додати чи прибрати тему — без правок `flake.nix` чи checks.
8. **Одна машина.** Жодної multi-host абстракції. Друга машина = окремий redesign.

## 2. Структура репо
```
flake.nix               inputs + wiring (< 120 рядків); expose lib.themes
state.json              вибір, який робить dangonix: { theme, foundry.instances, fingerprint }
packages.json           пакети, встановлені `dangonix pkg install` (чернетка до переносу в код)
lib/
  settings.nix          user, host, system, held inputs
  mk-home.nix           одна home-конфігурація на тему
  checks.nix            всі flake checks, generic по реєстру, + host build, + політика безпеки
  dangonix/
    default.nix         пакет dangonix (writeShellApplication)
    commands.nix        таблиця команд — single source of truth
    dangonix.sh         код CLI як справжній файл, не Nix-рядок
hosts/nixos/            єдиний хост; + boot.nix (Plymouth, LUKS, Secure Boot), foundry.nix (інстанси), fingerprint.nix,
                        security.nix (firewall, Tailscale, SSH, sysctl, 1Password, managed settings Claude Code), backup.nix
home/                   інваріантне user-середовище
  dangonix.nix          ставить dangonix, пише ~/.config/dangonix/{theme-id,roles.json}
  dangonix-saver.nix    user-сервіс ощадливого режиму (енергія + трафік)
  hyprland/             інваріантні settings + core binds з описами, викликають ролі
  frontends/            core-дані/сервіси + default UI для frontend-ролей
themes/
  default.nix           реєстр = manifest (Nix attrset)
  contract.nix          dangonix.theme.* і dangonix.roles.* options + assertions
  common/               спільні провайдери (polkit agent, low-battery notifier)
  noctalia/             family 1, stable
  caelestia/            family 2, experimental
tests/binds/<id>.json   frozen fixture біндів
tests/dangonix-vm/      fixture-flake і VM-тест транзакцій
scripts/closure-diff    oracle: порівнює drvPath, тільки eval
scripts/quest-verify, campaign, agent, review, lint-docs, lint-commits, next-version, opt
scripts/hooks/          git-guard, ref-guard, commit-msg (спільні для обох агентів)
.github/workflows/ci.yml  eval + лінт + oracle на кожен push, без збірки
docs/themes.md          довідка по контракту + інтерв'ю для нової теми
AGENTS.md, CLAUDE.md (@AGENTS.md), .agents/skills/quest/
.mcp.json, .claude/settings.json, .codex/ (config.toml, hooks.json, rules/)
README.md               мануал для мене (intro + команди + fresh install)
docs/                   vision, design, current-state, remake (укр., для мене); tasks.md (англ., для агентів)
```

## 3. Теми

### Термінологія
- **Family** — одна shell-реалізація: модуль `themes/<family>/`, володіє своїми сервісами.
- **Theme** — family + опційний `variant` (палітра, wallpaper, ...). Команда `dangonix theme`.
- Палітра shell'а — це **не** dangonix theme, а runtime-стан shell'а (навіть якщо Noctalia називає її "theme").

### Manifest
Запис у реєстрі, звичайний Nix attrset (YAML/JSON не варті того). Flake віддає його як `lib.themes` — стабільний інтерфейс для dangonix і оракула.
```nix
themes.noctalia = {
  name = "Noctalia";
  description = "Noctalia v5 as the complete Wayland desktop shell.";
  family = "noctalia";
  status = "stable";        # stable | experimental
  variant = { };
};
```
`experimental` лише ховає тему з `dangonix theme` без `--all` і ніколи не послаблює перевірки. Виняток — тимчасовий warning mode для Caelestia (з c1q20 до кампанії II).

### Ролі (контракт)
Ядро (Hyprland, apps, input, frontend-сервіси) викликає **ролі**, а не провайдерів. Нова тема = "заповни ролі й пройди перевірки". Чотири види:
- **command** — тема дає команду, core bind її викликає;
- **provider** — тема називає провайдера і user unit, що його запускає; exclusive — рівно один увімкнений;
- **declaration** — факт, який читають checks і docs;
- **frontend with default** — core володіє даними і CLI, тема *може* дати UI поверх них; інакше — core default UI.

| Роль | Вид | Обов'язкова | Де використовується |
|---|---|---|---|
| `launcher` | command | так (→ `search` у кампанії II) | SUPER+R |
| `session` | command | так | SUPER+Escape, SUPER+Shift+W |
| `osd` | command ×8 | так | XF86 (гучність, мікрофон, яскравість, підсвітка) |
| `screenshot` | command | так (`region`, `full`; `window` опц.) | Print, Shift+Print, SUPER+Print |
| `lock` | provider | рівно один | `loginctl lock-session`, idle, suspend |
| `idle`, `bar`, `notifications`, `polkit` | provider | рівно один | checks, `dangonix doctor` |
| `wallpaper` | provider | так | checks |
| `batteryWarning` | provider | так (з кампанії II) | shell або `themes/common/low-battery-notify.nix` |
| `palette` | declaration | так | `shell \| static` |
| `toolkit` | declaration | так | GTK/Qt/cursor: `shell \| none` |
| `appearance` | declaration | так | темний чи світлий режим: `shell \| dark \| light`, з `dangonix.look` ([вигляд](#вигляд)) |
| `keybindings`, `clipboard`, `search` | frontend with default | ні | SUPER+F1, `dangonix clipboard`, SUPER+R |
| `windowSwitcher`, `controlCenter`, `settings` | command | ні | ALT+Tab, SUPER+S, SUPER+comma |

Ніколи не ролі (core): terminal, explorer, browser, editor, Claude key, керування вікнами, workspaces 1-5, mouse drag/resize, zoom і scale, input, монітори, default apps.

Обов'язкова роль без провайдера → помилка evaluation: `theme <id>: role <role> has no provider`.

### Бінди — це дані
Кожен bind — запис з описом: `{ key = "SUPER+Return"; action = …; description = "Open terminal"; }`. Ідентичність bind'а — **повний resolved запис**: ключ, action, аргументи, всі flags. Ключі нормалізуються (`mod` → `SUPER`, фіксований порядок модифікаторів SUPER, CTRL, ALT, SHIFT, роздільник ` + `). З тих самих даних генеруються `hyprland.lua`, cheatsheet (`keys.json`), перевірка дублікатів і frozen fixture — тому вони не можуть розійтись.

Правило: кожен наявний bind лишається (з усіма flags). Нові — тільки на вільні клавіші. Cheatsheet — SUPER+F1 (однаково під UA і EN), search — апгрейд launcher'а на SUPER+R; SUPER+Space лишається "float toggle", SUPER+K — "focus up".

### Вигляд
Тема задає вигляд програм ядра одним attrset `dangonix.look` (`home/look.nix`): ядро дає значення за замовчуванням, тема перебиває потрібні.
```nix
dangonix.look = {
  appearance = "shell";   # shell | dark | light; без значення за замовчуванням, кожна тема вибирає
  terminal = { dark = "manuscript-dark"; light = "manuscript-light"; };   # теми Ghostty
  editor = { dark = "Manuscript Dark"; light = "Manuscript Light"; };     # теми Zed
  fonts = { mono = [ "Rec Mono Casual" "Maple Mono" ]; monoSize = 14; ui = "Miriam Libre"; };
};
```
- Режим живе в одному значенні `org.gnome.desktop.interface color-scheme`, а портал GTK хоста віддає його програмам. `shell`: його пише перемикач оболонки (у Noctalia темний, світлий чи «авто», `theme.sync_color_scheme`), ядро не чіпає. `dark`, `light`: його пише Home Manager під час активації (`dconf.settings`), перемикача немає. Noctalia — `shell`, Caelestia — `dark`, поки сама не пише `color-scheme`.
- За режимом ідуть Ghostty (`theme = "light:…,dark:…"`), Zed (`theme.mode = "system"`), GTK4, Electron і Firefox через портал; dangonix, starship і fish — через 16 ANSI-кольорів терміналу. Іконки (Papirus-Dark) однакові в обох режимах.
- Палітри Manuscript Dark і Light беруться з одного зафіксованого розширення Zed (`home/manuscript.nix`): Ghostty читає кольори з його JSON, тож редактор і термінал не розходяться. У Ghostty `minimum-contrast = 3`; шаблон Ghostty з палітри Noctalia не вмикається.
- `home/look.nix` пише `~/.config/dangonix/look.json` (`appearance` і тема), його читає `dangonix status`.

### Перевірки (static, `lib/checks.nix`, на кожну тему)
1. **Registry** — унікальні id, `themes/<family>` існує, поля manifest валідні, `dangonix.theme.id == id`, `state.json` theme є в реєстрі. Інваріанти family — assertions у самому модулі family.
2. **Roles** — всі обов'язкові ролі задані (evaluation-time, ловить `dangonix check --fast`).
3. **Providers** — для кожної exclusive ролі рівно один увімкнений провайдер. Другого шукають у таблиці відомих HM options (`services.dunst`, `programs.waybar`, `services.cliphist`, ...) і в деклараціях самої теми.
4. **Bindings** — frozen fixture (кожен запис на місці і незмінний), ключі ролей присутні, у кожного bind'а є опис, немає дублікатів resolved ключів.
5. **Executables** — перше слово кожної role-команди є в `home-path/bin` теми або це абсолютний store path.
6. **Builds** — host toplevel, activation package кожної теми, `Hyprland --verify-config`.
7. **Command table** — кожна підкоманда в таблиці, у кожної є `effect`/`agent`/kind, не-`read` мають `--dry`, `agent = allow` тільки в `read` (і `check`), а `dangonix`-правила в `.claude/settings.json` і `.codex/rules/dangonix.rules` — рівно allow на `dangonix --dry …` і `dangonix check …`.

Runtime-відповідник — **`dangonix doctor`**: один власник `org.freedesktop.Notifications` (і це заявлений провайдер), зареєстрований polkit agent, запущений idle daemon, один writer clipboard history.

### Що не варте того
- **Генератор тем зі скріншота.** Цю роботу робить агент; безпечною її роблять контракт, checks і оракул.
- **Автоматична visual regression.** GPU/EGL-квірки, flaky, дорого. Подивитись очима після `dangonix theme <id>` дешевше.
- **Одна палітра для всіх shell'ів.** Кожен має свій theming engine; контракт лише вимагає *задекларувати* джерело палітри і toolkit.
- **Багато families.** Кожна — external input, що churn'ить з Hyprland/Quickshell. 2-3 максимум.
- **XP title bars через Hyprland plugin.** Плагіни мусять збігатись з точною ревізією Hyprland — це проти цілі 1. Тільки свідомим рішенням в інтерв'ю.

Відкладено до першої власної Quickshell-теми: `dangonix.textSize` (одна опція для shell, GTK і терміналу) і Qt QML agent skill (TheQtCompanyRnD/agent-skills).

`docs/themes.md` — чекліст інтерв'ю для нової теми: bar (позиція, вміст), launcher, session menu, lock screen (і як він веде відбиток, [§10](#10-відбиток-пальця)), notifications, декорації вікон (plugin так/ні), light/dark, які опційні ролі і frontend UI.

### Noctalia: runtime-стан
`~/.local/state/noctalia/settings.toml` застосовується останнім, тому перемагає декларації. Activation step пише **тільки іменовані ключі**: telemetry off, вимкнення приватного clipboard store, wallpaper (з `assets/`). Решта, включно з палітрою, — runtime-стан, змінюється в GUI Noctalia. Перевірки ніколи не видаляють цей файл.

## 4. `state.json`
Відстежуваний файл з усім, що може вибрати команда, і нічим більше:
```json
{ "theme": "noctalia",
  "foundry": { "instances": { "main": { "version": "…", "port": 30000 } } },
  "fingerprint": true }
```
- dangonix редагує його через `jq` (temp file + atomic rename), показує diff і **ніколи не комітить** — комічу я.
- Хост отримує тільки `state.foundry` і `state.fingerprint`, ніколи `state.theme` — зміна теми не може дійти до хоста by construction.
- Foundry: тільки інстанси з `version` і `port`; порожній `instances` = Foundry немає. Ім'я інстансу — `[a-z0-9-]+`, порти унікальні. Filename і hash беруться з власної таблиці версій nix-foundryvtt. Деталі — [§9](#9-foundry-vtt).
- Gitignored-файл відкинуто: flake бачить лише tracked файли, а fresh install втратив би вибір.

## 5. `dangonix`
Одна `writeShellApplication`, код у `lib/dangonix/dangonix.sh`. Nix інжектить конфіг (host, user, held inputs, шлях до репо, таблиця версій Foundry) і таблицю команд. `apps.default = dangonix`.

### Граматика
- `dangonix <іменник> [<дієслово>] [<ім'я>] [аргументи]`. Іменник без дієслова — завжди статус (`read`): `dangonix power`, `dangonix fingerprint`, `dangonix backup`.
- Режими задаються самим словом (`power saver`, `net saver`, `theme <id>`), перемикачі — `on|off` (`fingerprint on`, `net metered off`, `foundry share main on`).
- `<name>` інстансу Foundry можна не писати, коли інстанс один.
- Глобальні флаги **перед** підкомандою: `--json` (один JSON на stdout, логи на stderr), `--dry` (приймає кожна команда; не-`read` каже, що зробила б, без змін, `read` працює як завжди), `--yes` (підтвердження irreversible-кроку без TTY), `--metered-ok` (дозвіл качати на лімітному з'єднанні, [§8](#8-трафік)), `--flake <path>`. Приклад: `dangonix --dry switch`. У кожної команди є `--help`; `dangonix help <команда>` — те саме.
- **JSON:** `{ command, ok, exit, data, warnings }`; мутації додають `steps`, `failedStep`, `recovered`, `reversible`.
- **Exit codes:** `0` — успіх; `1` — команда впала, стан відновлено; `2` — помилка використання; `3` — відновлення не вдалося, надруковано ручні кроки; `4` — відмова до будь-яких змін (lock зайнятий, не той юзер, лімітне з'єднання без `--metered-ok`, irreversible без підтвердження, немає пристрою).
- Irreversible-крок на TTY питає `y/N`; без TTY потребує `--yes`.

### Вивід
Оформлення живе тільки в `lib/dangonix/ui.sh`; команди викликають його функції (`ui_step`, `ui_ok`, `ui_warn`, `ui_err`, `ui_hint`, `ui_build`) і ніколи не пишуть escape-коди самі. Мова виводу українська.
- **Кольори за ролями**, тільки 16 ANSI-кольорів терміналу (тема, що фарбує Ghostty, фарбує й dangonix): green — успіх, `✓`, додані пакети; yellow — увага, `!`, плашка `DRY`, питання `?`; red — помилка, `✗`, видалені пакети (stderr); cyan — дієслова кроків і команди, які можна скопіювати, `help:`; blue — `↑` оновлення версії; dim — мітки, час, пояснення; bold — значення, назви, заголовки помилок.
- **Іконки** — звичайний Unicode `✓ ! ✗ – ● ○ ↑ + −`, без Nerd Font.
- **Форми:** статус — рядки «мітка, значення, стан»; кроки — дієслово, вирівняне праворуч у 10 колонок (як cargo); `--dry` починається з плашки `DRY`; збірка — прогрес nix-output-monitor, потім diff пакетів nvd; підсумок мутації — рамка з лівою смугою, generations і командою відкату; помилка — заголовок `✗`, рядок про стан системи й код виходу, далі готові команди (для коду `3` пронумеровані), для eval — файл:рядок, вказівник `^^^` і `help:`; шляхи — OSC 8 посилання.
- **Коли вмикається** (stdout і stderr окремо): `--json` або агент (`CLAUDECODE`, `DANGONIX_AGENT`) — ні кольорів, ні прогресу; не TTY або `TERM=dumb` — так само; `NO_COLOR` — без кольорів, жирний і прогрес лишаються; `CLICOLOR_FORCE` — кольори навіть у пайпі, без прогресу. Нового флага немає.
- Перевірка: у пайпі, з `--json` і з `CLAUDECODE=1` вивід жодної команди не містить байта `\e`.

### Команди
| Команда | effect | agent | Що робить |
|---|---|---|---|
| **Система** | | | |
| `dangonix` | read | allow | `status` + коротка довідка |
| `dangonix status` | read | allow | тема, вигляд (режим і хто його ставить), power і net mode, Foundry, щит, чи система зібрана з поточного `state.json`; бар читає `dangonix --json status` |
| `dangonix help [<команда>]` | read | allow | довідка з таблиці команд |
| `dangonix commands` | read | allow | всі команди з описом, effect, agent (`--json` — API для агентів, search і shell'ів) |
| `dangonix version` | read | allow | версія dangoNix (`git describe`), коміт, чи брудне дерево, host і home generations, дата `nixpkgs` |
| `dangonix switch [--home\|--host] [--overwrite]` | host | ask | транзакція: build host + home, nvd diff, активувати хост (тільки якщо змінився), потім home; `--overwrite` відкладає вбік файли, з якими зіткнувся Home Manager (`-b`) |
| `dangonix update [<input>...\|-<input>...]` | state | ask | оновити всі inputs крім held, `dangonix check`, при помилці повернути `flake.lock`; ніколи не switch'ить і не комітить. Імена — оновити тільки їх; `-<input>` — оновити все, крім held і названих з мінусом (`update -zen-browser`); змішувати не можна, невідомий input — exit 2 |
| `dangonix history` | read | allow | журнал транзакцій (команда, час, результат, `failedStep`) разом з host і home generations |
| `dangonix rollback [--host\|--home]` | host | ask | активувати попередню пару generations з журналу; `state.json` не чіпає, тож `status` попереджає, що система не з нього |
| `dangonix clean [--older-than <14d>]` | host | ask | видалити старші generations (поточна й попередня лишаються завжди) і зібрати сміття store; GC roots Foundry не чіпає; друкує, скільки звільнено |
| **Перевірки** | | | |
| `dangonix check [--fast\|--vm]` | read | allow | завжди: лінт доків і комітів, shellcheck; full: `nix flake check` (static, host, всі теми, verify, контракт, політика безпеки); `--fast`: тільки eval; `--vm`: VM-тести транзакцій (`packages.dangonix-vm`) |
| `dangonix doctor` | read | allow | наживо: ролі активної теми, відбиток ([§10](#10-відбиток-пальця)) |
| `dangonix security [<id>]` | read | allow | щит: стан усіх перевірок безпеки з командою-виправленням ([§11](#dangonix-security)) |
| **Теми й робочий стіл** | | | |
| `dangonix theme` | read | allow | список тем: selected (`state.json`) і active |
| `dangonix theme <id>` | state | ask | записати тему в `state.json`, зібрати й активувати home |
| `dangonix keys` | read | allow | cheatsheet з реальних даних біндів |
| `dangonix clipboard [list\|pick\|clear]` | read/runtime/state | **ask** | історія clipboard (може містити паролі) |
| **Пакети** ([нижче](#пакети)) | | | |
| `dangonix pkg [list]` | read | allow | пакети з `packages.json`: канал, дата, примітка, скільки днів чекає переносу в код |
| `dangonix pkg search <слова…>` | read | allow | пошук по всьому nixpkgs (stable і unstable) з версіями з `flake.lock`; позначає встановлене (будь-яким шляхом) і програми з опцією модуля |
| `dangonix pkg install <attr> [stable\|unstable] [--note <текст>]` | state | ask | записати в `packages.json`, зібрати й активувати home |
| `dangonix pkg remove <attr>` | state | ask | прибрати з `packages.json`, активувати home; рукописні пакети не чіпає, а показує, де вони в коді |
| `dangonix pkg try <attr>` | runtime | ask | тимчасова оболонка з пакетом (`nix shell`), конфіг не змінюється |
| **Foundry** ([§9](#9-foundry-vtt)) | | | |
| `dangonix foundry [list]` | read | allow | інстанси: версія, порт, стан, URL |
| `dangonix foundry status [<name>]` | read | allow | повний звіт по інстансу, без імені — по всіх ([§9](#статус)) |
| `dangonix foundry logs [<name>] [-f]` | read | allow | журнал інстансу |
| `dangonix foundry start\|stop\|restart\|open [<name>]` | runtime | ask | керування `foundryvtt-<name>.service` (зупинка обірве гру) |
| `dangonix foundry share [<name>] [on\|off]` | runtime | ask | Tailscale Funnel для інстансу: друкує посилання для гравців; вимикається разом з інстансом ([§11](#мережа)) |
| `dangonix foundry add <name> <zip> [--port N] [--copy-from <name>]` | host | ask | імпорт ZIP, новий інстанс у `state.json`, switch host; `--copy-from` копіює дані іншого інстансу |
| `dangonix foundry upgrade <name> <zip> [--backed-up]` | host | ask | імпорт ZIP, нова версія для інстансу, switch host; між major — тільки з `--backed-up` |
| `dangonix foundry remove <name>` | host | ask | прибрати інстанс зі `state.json`, switch host; дані лишаються на диску |
| `dangonix foundry import <zip>` | state | ask | тільки імпорт ZIP (store + GC root) для версії, що вже є в `state.json`; для fresh install |
| **Енергія й мережа** | | | |
| `dangonix power [auto\|saver\|balanced\|performance]` | runtime | ask | статус / override енергорежиму ([§7](#7-енергія-і-фон)) |
| `dangonix net [auto\|saver\|normal]` | runtime | ask | статус з'єднання (лімітне чи ні) / override режиму трафіку ([§8](#8-трафік)) |
| `dangonix net metered [on\|off]` | state | ask | позначити поточне з'єднання NetworkManager як лімітне назавжди |
| **Залізо** | | | |
| `dangonix firmware [--refresh]` | read | allow | пристрої й оновлення; metadata refresh, якщо старша за 24 год |
| `dangonix firmware update` | host | ask | застосувати firmware updates, тільки на запит |
| `dangonix fingerprint` | read | allow | стан відбитка: увімкнено, пристрій, записані пальці, де діє ([§10](#10-відбиток-пальця)) |
| `dangonix fingerprint add [<finger>]` | state | ask | записати палець (default `right-index-finger`) |
| `dangonix fingerprint remove <finger>\|--all` | state | ask | видалити записаний відбиток |
| `dangonix fingerprint check` | runtime | ask | прикласти палець один раз: `match \| no-match \| no-device` |
| `dangonix fingerprint on\|off` | host | ask | записати `state.fingerprint`, switch host |
| **Дані** ([§11](#бекапи)) | | | |
| `dangonix backup` | read | allow | вік останнього бекапу, чи підключений диск, вільне місце на ньому |
| `dangonix backup list` | read | allow | snapshots: дата, розмір, що в них |
| `dangonix backup now` | state | ask | бекап зараз (диск має бути підключений) |
| `dangonix backup check` | read | allow | `restic check` цілісності сховища |
| `dangonix backup restore <snapshot> <path> [--to <dir>]` | state | ask | відновити в окрему теку (default `~/restore/<snapshot>/`), ніколи поверх живих даних |

### Пакети
Ціль: шукати й ставити програми однією командою, але так, щоб вони жили в конфігу.
- `packages.json` (tracked): `{ "<attr>": { "channel": "stable|unstable", "added": "YYYY-MM-DD", "note": "…" } }`. `home/packages.nix` читає його `builtins.fromJSON` і додає `pkgs.<attr>` або `pkgsUnstable.<attr>` до `home.packages` поруч з рукописним списком. dangonix редагує його через `jq`, як `state.json`, і не комітить. Це чернетка: згодом пакети переносяться в рукописний список руками, а `pkg remove` прибирає їх звідси.
- `search` шукає в назві й описі по обох зафіксованих nixpkgs, тож показана версія — та, що встановиться (перший пошук після `update` — десятки секунд, далі eval cache). «Встановлено» — за зібраною системою: `home.packages` і `environment.systemPackages`.
- `install` перевіряє, що атрибут існує в зафіксованому nixpkgs, і відмовляє (exit 4) з назвою опції, якщо для програми є опція NixOS чи Home Manager (`programs.<name>.enable`): такій програмі мало пакета. Тільки `home.packages`; системні пакети й сервіси — лише в коді.

**Свідомо не команди.** `nix fmt` — форматування, не обгортається. `scripts/` (closure-diff, quest-verify, campaign, next-version, opt, lint-*) — інструменти розробки репо, не системи; єдиний міст — `dangonix check`. `docker`, `tailscale`, `op`, `fprintd-*` викликаються напряму: dangonix обгортає тільки те, де додає стан, транзакцію або захист. Zoom і scale моніторів, lock, suspend — бінди.

### `effect` і `agent`
| effect | Значення | У search | `--json` перевірка | Lock |
|---|---|---|---|---|
| `read` | нічого не змінює надовго | так | запускається реально | ні |
| `runtime` | зворотня зміна, зникає після stop/reboot | так | з `--dry` | ні |
| `state` | пише `state.json`, `flake.lock` або user data | ні | з `--dry` | так |
| `host` | змінює або активує системну конфігурацію | ні | з `--dry` | так |

`agent` (`allow | ask`) — чи агент запускає команду без мене. `wraps` — сирі команди, які рядок обгортає; з нього генерується deny для агентів у managed settings ([§11](#агенти)). `allow` — тільки `read`; `runtime`, `state` і `host` — `ask`, виняток — `clipboard` (`ask`, бо історія може містити паролі: з `--dry` він нічого не показує). Rules не генеруються і не змінюються з кожною новою командою: `--dry` приймає кожна команда (для `read` він нічого не міняє), тож агентові досить двох allow — `dangonix --dry …` і `dangonix check …`; усе інше без правила, і Claude Code питає (headless — відмовляє), а sandbox Codex не дає активувати. Catch-all `ask` не можна: в обох CLI ask сильніший за allow. Так файли дозволів, які агент сам міняти не може, не потребують ходу майстра на кожен квест.

З таблиці генеруються: help, fish completions, `dangonix commands --json`, що показує search, що проганяє `--json`-перевірка, хто бере lock.

### Транзакції
Три види мутацій, усі під lock'ом:
- **configuration transaction** — `switch`, `rollback`, `theme <id>`, `pkg install|remove`, `update`, `foundry add|upgrade|remove`, `fingerprint on|off`. Мають recovery.
- **irreversible operation** — `firmware update`, `clean`, `clipboard clear`, `foundry import`, `fingerprint remove`. Lock + `--dry` + `ask`, без rollback; dangonix каже про це перед дією, JSON має `reversible: false`. Імпорт ZIP усередині `foundry add|upgrade` — теж irreversible крок, але транзакція навколо нього відкочується; `reversible: false` стосується тільки імпорту.
- **проста мутація** — `fingerprint add`, `net metered on|off`, `backup now`, `backup restore`. Lock + `--dry` + запис у журнал, без `y/N` і без recovery: вони не чіпають конфіг і нічого не знищують.

Кроки транзакції:
1. Відмова, якщо `$USER` ≠ `kit`.
2. Транзакція працює у власному user scope `dangonix-<pid>` (`systemd-run --user --scope`), тож не залежить від терміналу чи user unit'а, що її запустив; ігнорує SIGHUP і пише stderr у `~/.local/state/dangonix/last.log`. `flock -n` на `$XDG_RUNTIME_DIR/dangonix.lock`; друга мутуюча команда падає одразу.
3. Snapshot: `state.json` (+ `flake.lock` із sha256 для `update`), поточні host і home generations.
4. Preflight: payload кожного інстансу з `state.json` мусить бути в store.
5. Редагування `state.json`.
6. Build задіяних сторін одним `nix build`.
7. nvd diff.
8. Host — тільки якщо задіяний і відрізняється від `/run/current-system`: `nix-env --set` профілю + `switch-to-configuration switch`.
9. Home: `nix-env --set` профілю + `activate --driver-version 1` (dangonix сам вирішує, куди вказує профіль).
10. Запис у журнал `~/.local/state/dangonix/journal.jsonl` (його читають `history` і `rollback`), release lock, показати `git diff` змінених файлів.

**Гарантовано:** при помилці `state.json` і `flake.lock` байт-у-байт як у snapshot; lock завжди звільняється; помилка build нічого не активує; `theme` ніколи не торкається хоста. Результат містить `failedStep`, `recovered`, `reversible`.
**Best effort:** при помилці на кроці 8/9 — повторна активація попередніх generations. Відновлюється конфіг, не side effects (перезапущені сервіси, записані файли, runtime-ключі Noctalia). На першому install немає попередньої home generation → `recovered: false` + наступний крок. Якщо recovery впав — exit 3 і точні команди, щоб доробити руками.

### Fresh install
```sh
# після stock NixOS install з юзером kit, репо в ~/nixos,
# hardware-configuration.nix скопійовано в hosts/nixos/
# для кожного інстансу з state.json:
nix --extra-experimental-features 'nix-command flakes' run ~/nixos -- foundry import ~/Downloads/FoundryVTT-<version>.zip
# (або: … -- foundry remove <name>)
nix --extra-experimental-features 'nix-command flakes' run ~/nixos -- switch
```

## 6. Стабільність
- `flake.lock` пінить усе, без `?rev=` у `flake.nix`.
- `dangonix update` пропускає **held list** (`hyprland`, `noctalia`, `caelestia`), якщо input не названо явно; повідомляє про held. Разове виключення — `-<input>` (`dangonix update -zen-browser`), JSON `excluded`; постійно не оновлювати — додати input у held.
- Gate — `dangonix check`: збирає host toplevel і кожну тему; при помилці повертає `flake.lock` байт-у-байт; ніколи не switch'ить.
- CI на GitHub — другий, eval-only gate: та сама `check --fast` і оракул на кожен push. CD немає: switch завжди робиш ти.
- Kernel — `linuxPackages_latest`, оновлюється тільки через gated `dangonix update`.
- Login: SDDM + `thyx`, спільний для всіх тем. Plymouth — host-owned, у кампанії III після LUKS: він малює запит пароля диска.

## 7. Енергія і фон
Один user-сервіс `dangonix-saver` (ppd лишається), прив'язаний до `graphical-session.target`, керує і енергією, і трафіком ([§8](#8-трафік)). Слухає UPower, NetworkManager, Hyprland config reload, resume.

**Ощадливий набір** (`saver`) — один і той самий, від батареї чи від мережі: ppd `power-saver`, вимкнені animations і blur. Інші режими: `balanced`, `performance`.

| Режим `dangonix power` | Батарея | Мережа |
|---|---|---|
| `auto` (default) | saver | balanced |
| `saver` | saver | saver — «швидка зарядка»: споживає як від батареї |
| `balanced` / `performance` | як названо | як названо |

- Override (`saver|balanced|performance`) живе в `$XDG_RUNTIME_DIR`: переживає plug/unplug, скидається після reboot або `dangonix power auto`.
- Чесне обмеження: швидша зарядка помітна, лише коли блок живлення — вузьке місце (слабкий USB-C, навантаження під час зарядки). Струм заряду обмежує EC ноутбука; на штатному блоці без навантаження різниця мала. Ціна режиму — повільніша система, тому на мережі він вмикається тільки вручну.
- Foundry VTT і Docker стартують на запит, не при boot. Системний Docker вимкнений; rootless Docker ([§11](#хост)) — user-сервіс із socket activation.
- fwupd: refresh timer вимкнено; оновлення тільки через `dangonix firmware update`.
- Low-battery warning — роль: рівно один попереджувач.
- Відкинуто: ThinkPad charge limit.

## 8. Трафік
Ціль: на хотспоті з лімітом ГБ система сама перестає качати зайве.

**Тригер.** NetworkManager тримає прапорець лімітного з'єднання (`Metered` = `yes` або `guess-yes`), і `dangonix-saver` слухає саме його. Мій телефон — iPhone, а iOS-хотспот, на відміну від Android, сам себе лімітним не оголошує. Тому:
- `dangonix net metered on` один раз позначає поточне з'єднання (хотспот iPhone) як лімітне в його профілі NM — далі воно визначається саме;
- опційно: авто-позначення нових з'єднань, чий шлюз у `172.20.10.0/28` (підмережа iOS Personal Hotspot), — перевірити в research spike. Override `dangonix net saver|normal` — у `$XDG_RUNTIME_DIR`, як у power.

**Що робить `saver`** (той самий `dangonix-saver`):
1. **Власні завантаження dangonix:** кожна команда, що збирає або качає (`switch`, `update`, `rollback`, `theme <id>`, `pkg install|try`, `foundry add|upgrade`, `fingerprint on|off`, `firmware`), показує розмір завантаження (`nix build --dry-run`) і вимагає `--metered-ok`. Metadata refresh fwupd пропускається.
2. **Фонові завантажувачі на паузу:** список units `dangonix.data.pauseUnits` зупиняється на вході в saver і відновлюється на виході. Склад списку визначає research spike нижче.
3. **Застосунки, що поважають metered самі** (PackageKit, GNOME-застосунки), нічого не потребують.
4. **Опційно, якщо spike покаже, що варто:** мережевий kill-switch для переліку застосунків — вони запускаються в `apps-metered.slice`, nftables `socket cgroupv2` відкидає їхній трафік, поки з'єднання лімітне.

Постійно, незалежно від режиму (дешево і корисно): у Zen вимкнені prefetch, DNS prefetch і autoplay відео (`policies.json`), telemetry вимкнена всюди, де є опція.

Чесне обмеження: більшість Linux-застосунків прапорець metered ігнорують. «Всі застосунки в режимі економії» гарантує тільки kill-switch (п. 4), а він ламає ці застосунки на хотспоті — тому він опційний і за списком.

**Research spike (перед реалізацією):** виміряти, що качає у фоні на цій машині за годину idle (`bandwhich`/`nethogs`); перевірити Steam, Zen, Vesktop, Zed, Noctalia, Docker на власні налаштування економії; вирішити, чи потрібен kill-switch.

## 9. Foundry VTT
Кілька версій поруч, кожна зі своїми конфігами і світами, запускаються окремо.

- Модуль nix-foundryvtt однoінстансний (один `foundryvtt.service`, один `dataDir`), тому хост має власний `hosts/nixos/foundry.nix`. Він з `state.foundry.instances` генерує по unit'у на інстанс і перевикористовує пакети nix-foundryvtt (`foundryvtt_<major>` + `overrideAttrs` на точну версію).
- **Інстанс `<name>`:** unit `foundryvtt-<name>.service`, дані `/var/lib/foundryvtt-<name>/{Config,Data,Logs}` (свої `options.json`, ліцензія, світи, модулі), порт зі `state.json`. Firewall портів інстансів не відкриває: гравці заходять через `foundry share` ([§11](#мережа)).
- Один системний юзер і група `foundryvtt`; `kit` у групі (group-writable дані, як зараз) і має NOPASSWD sudo тільки на `start|stop|restart` кожного unit'а.
- Жоден інстанс не стартує при boot. Кілька можуть працювати одночасно на різних портах.
- **Major upgrade** мігрує світи in-place без дороги назад, тому `foundry upgrade` між major вимагає `--backed-up`. Безпечніший шлях — `foundry add v14 <zip> --copy-from main`: новий інстанс з копією даних, старий лишається.
- `foundry remove` ніколи не видаляє дані; видалити `/var/lib/foundryvtt-<name>` — мій ручний крок.
- **Міграція:** поточний `/var/lib/foundryvtt` стає інстансом `main` (`/var/lib/foundryvtt-main`) — одноразовий ручний крок після backup.
- Ризик: умови ліцензії Foundry щодо одночасного запуску кількох інстансів з одним ключем — перевірити до реалізації.

### Статус
`dangonix foundry status [<name>]` — усе, що можна дізнатись без змін, одним екраном (`--json` — те саме для бару і агентів); без імені — блок на кожен інстанс і підсумок. `dangonix foundry` лишається коротким списком.

| Блок | Що показує | Звідки |
|---|---|---|
| Інстанс | ім'я, версія в `state.json` і реально зібрана, major, порт, `http://127.0.0.1:<port>` | `state.json`, пакет хоста |
| Сервіс | стан unit'а, uptime, пам'ять, CPU, перезапуски, останні помилки з журналу (кількість + останній рядок) | `systemctl show`, `journalctl` |
| Гра | активний світ і система, гравців онлайн | `GET /api/status` інстансу (перевірити поля при реалізації) |
| Гравці | Funnel `on/off`, публічне посилання, порт Funnel (443/8443/10000), чи з'єднання лімітне | `tailscale funnel status`, NetworkManager |
| Дані | світи (назва, система, розмір, остання зміна), кількість модулів і систем, розмір `Data`, вільне місце на диску | `/var/lib/foundryvtt-<name>/Data` |
| Безпека | admin-пароль заданий, ліцензія є (сам ключ не друкується), `✗`, якщо Funnel увімкнений без admin-пароля | `Config/` |
| Бекап | вік останнього бекапу з цим інстансом | restic ([§11](#бекапи)) |

Кожне попередження — з командою-виправленням, як у `dangonix security`; ті самі перевірки Foundry щит показує одним рядком.

## 10. Відбиток пальця
Ціль: всюди, де система питає мій пароль і це має сенс, спершу можна прикласти палець; пароль завжди лишається запасним шляхом.

**Як це працює.** `fprintd` (libfprint) тримає сенсор і дає D-Bus API; PAM-модуль `pam_fprintd` додає відбиток у стек автентифікації. На NixOS `security.pam.services.<name>.fprintAuth` за замовчуванням дорівнює `services.fprintd.enable`, тобто ввімкнений fprintd додає `pam_fprintd` (`sufficient`, перед `pam_unix`) у **кожен** PAM service. Тому хост не перелічує, де ввімкнути, а вимикає там, де відбиток заважає.

PAM-стек послідовний: `pam_fprintd` чекає палець і питає пароль тільки після тайм-ауту або вичерпаних спроб. Палець **або** пароль паралельно (що раніше) вміє лише застосунок, який сам веде сенсор через D-Bus, а пароль перевіряє окремим PAM-стеком, — так роблять обидва lock screen'и.

| Де | Як | Чому |
|---|---|---|
| Lock screen Noctalia | паралельно | Noctalia v5 сама веде сенсор через fprintd D-Bus (`lockscreen.fingerprint`, default `true`), а пароль перевіряє стеком `login` |
| Lock screen Caelestia | паралельно | власні `assets/pam.d/fprint` (`pam_fprintd` за шляхом `/run/current-system/sw/lib/security/`) і `passwd`; відбиток активний, якщо `fprintd-list $USER` успішний (`lock.enableFprint`, default `true`) |
| `sudo`, `su`, `run0`, діалоги polkit | спершу палець; пароль після 10 с або 3 промахів | стандартний `pam_fprintd` з `timeout=10` (дефолтні 30 с задовгі, напр. із закритою кришкою) |
| SDDM після boot, TTY `login` | тільки пароль; після LUKS SDDM робить автологін ([§11](#диск-і-вхід)) | пароль при вході розблоковує gnome-keyring (відбиток — ні); SDDM з `pam_fprintd` блокує поле пароля до тайм-ауту; у стеку `login` `pam_fprintd` конфліктує з lock screen Noctalia, який сам тримає сенсор (коментар у її `lock_screen.cpp`) |
| Шифрування диска, Plymouth | неможливо | сенсор не дає ключа диска; диск відкриває пароль LUKS або TPM2 + PIN ([§11](#диск-і-вхід)) |

**Правило для тем** (доповнює [контракт](#ролі-контракт)): lock screen, що вміє відбиток, веде сенсор сам; PAM service, яким він перевіряє пароль, не має `pam_fprintd`. Інтерв'ю нової теми питає, який це service.

**Хост** — `hosts/nixos/fingerprint.nix`, читає `state.fingerprint`:
- `true`: `services.fprintd.enable`; `fprintAuth = false` для `login`, `sddm` (і `hyprlock`, якщо він лишився після c1q10); `rules.auth.fprintd.args = [ "timeout=10" ]` для `sudo` і `polkit-1`. Явні `fprintAuth = true` з `desktop.nix` прибираються (вони дублюють default або тепер хибні).
- `false`: fprintd вимкнений, `pam_fprintd` немає ніде, lock screen'и не бачать пристрою й показують тільки пароль. Записані відбитки лишаються на сенсорі й у `/var/lib/fprint`, тож `on` повертає все як було.
- Сенсор: Synaptics Prometheus `06cb:00bd` (match-on-chip, відбитки зберігаються на самому сенсорі), підтримується libfprint без TOD; fprintd його бачить (перевірено 2026-10-17). Firmware сенсора оновлює `dangonix firmware`.

**CLI** `dangonix fingerprint` (рядки в [таблиці команд](#команди)):
- без аргументів — увімкнено чи ні, пристрій (назва, USB ID), записані пальці, таблиця «де діє»;
- `add [<finger>]` — `fprintd-enroll -f <finger>`; імена пальців як у fprintd (`right-index-finger`, `left-thumb`, …); polkit питає мій пароль (`auth_self_keep`); відмова з підказкою, якщо `state.fingerprint` false або пристрою немає;
- `remove <finger>|--all` — `fprintd-delete`, без відкату;
- `check` — одна спроба `fprintd-verify`; `runtime`, а не `read`, щоб `--json`-перевірка запускала його з `--dry`, а не чекала на палець;
- `on|off` — configuration transaction: `state.fingerprint`, build і switch хоста.

`add`, `remove` і `check` потребують живого пальця, тому агенту — `ask`.

`dangonix doctor` при `state.fingerprint = true`: fprintd бачить пристрій, записано хоча б один палець, у `/etc/pam.d/login` і `/etc/pam.d/sddm` немає `pam_fprintd`.

**Перевірити при реалізації:** що `/run/current-system/sw/lib/security/pam_fprintd.so` існує (на нього Caelestia патчить шлях); чи агент polkit теми показує підказку «прикладіть палець»; чи Ctrl+C у `sudo` пропускає відбиток до пароля.

## 11. Безпека
Від чого захищаємось: крадіжка чи втрата ноутбука, хтось поруч із розблокованим ноутбуком, чужа мережа, застаріле ПЗ (браузер передусім), агент робить зайве, чужий код у flake inputs, втрата даних. Не захищаємось від цілеспрямованої атаки з фізичним доступом і часом.

### Диск і вхід
- **LUKS2** на весь диск разом зі swap; розмітка — disko, тому [fresh install](#fresh-install) отримує крок розмітки. Шлях — перевстановлення після перевіреного відновлення з [бекапу](#бекапи).
- **Secure Boot** — lanzaboote: власні ключі плюс ключі Microsoft (оновлення BIOS). Пароль BIOS supervisor — ручний крок ([§15](#15-ручні-кроки-що-лишаються-inherent)).
- **Розблокування диска:** пароль LUKS; після Secure Boot — TPM2 + PIN (`systemd-cryptenroll --tpm2-with-pin`). Dictionary-attack lockout TPM тимчасовий (`tpm2_dictionarylockout`: 5 спроб, далі одна раз на 10 хв). Пароль LUKS лишається в окремому слоті, recovery key (`--recovery-key`) — в 1Password. TPM без PIN заборонений.
- **Один вхід:** після LUKS SDDM робить автологін; gnome-keyring з порожнім паролем, бо його захищає LUKS (відбитком keyring не відкрити: відбиток не секрет). Автологін дозволений тільки разом з LUKS.
- **Блокування екрана:** idle, перед сном, при закритті кришки — роль `lock` ([§3](#ролі-контракт)), живу перевірку робить `dangonix doctor`.

### Мережа
- Firewall увімкнений; на звичайних інтерфейсах вхідних портів немає. Steam Remote Play і LAN transfers без `openFirewall`.
- **Tailscale:** єдиний інтерфейс з вхідним портом — `tailscale0` (22). Key expiry ноутбука вимкнено, на акаунті 2FA, ACL пускає до :22 тільки мої пристрої.
- **Foundry для гравців** — Tailscale Funnel: постійне HTTPS-посилання без білої IP, гравцям нічого не треба ставити. Funnel слухає тільки 443, 8443, 10000, тож одночасно до трьох інстансів. `dangonix foundry share <name> on|off` (runtime) вмикає Funnel на порт інстансу і друкує посилання; зупинка інстансу вимикає Funnel; на лімітному з'єднанні — попередження ([§8](#8-трафік)). Admin-пароль і паролі гравців у світах обов'язкові. Запасний варіант — Cloudflare Tunnel з власним доменом.
- **SSH з Windows:** `services.openssh`, `openFirewall = false`, порт 22 тільки на `tailscale0`; лише ключі, без root, `AllowUsers = [ "kit" ]`; публічні ключі — `users.users.kit.openssh.authorizedKeys.keys`. На Windows: Tailscale + 1Password SSH agent з Windows Hello, `ssh kit@nixos`. Поки є SSH-сесія, idle-suspend інгібується (кришка все одно присипляє). `sudo` по SSH — паролем.
- Wi-Fi MAC: `networking.networkmanager.wifi.macAddress = "stable"`.

### Хост
- sysctl `kernel.kptr_restrict = 2`, `kernel.dmesg_restrict = 1`, `kernel.unprivileged_bpf_disabled = 1`, `net.core.bpf_jit_harden = 2`; `security.sudo.execWheelOnly = true`; `boot.loader.systemd-boot.editor = false`.
- Docker rootless (`virtualisation.docker.rootless` з `setSocketVariable`), системний демон вимкнений; user-сервіс стартує через socket activation, а не при вході (перевірити при реалізації). `kit` не в групі `docker` (вона дає root без пароля).
- Bluetooth `powerOnBoot = false`.

### 1Password
- `programs._1password-gui` (`polkitPolicyOwners = [ "kit" ]`) і `programs._1password` (`op`). Розблокування — system authentication: polkit → fprintd ([§10](#10-відбиток-пальця)).
- User-сервіс `1password --silent` у `graphical-session.target`, застосунок живе в треї, автоблокування на максимум. Master-пароль — раз після старту застосунку (на Linux system authentication не переживає перезапуск), далі відбиток.
- Zen у `/etc/1password/custom_allowed_browsers` (root, 0755; ім'я бінарника з `ps`), розширення з'єднане з застосунком, тому браузер master-пароль не питає.
- SSH: `IdentityAgent ~/.1password/agent.sock`, SSH-агент gnome-keyring вимкнено, приватних ключів у `~/.ssh` немає. Git підписує коміти SSH-ключем (`gpg.format = ssh`, `gpg.ssh.program = op-ssh-sign`).
- `gh` — через 1Password Shell Plugins, токена в `~/.config/gh` немає. Quick Access — бінд Hyprland на вільну клавішу → `1password --quick-access`. Секрети для `dangonix` — `op read op://…`.
- Поза 1Password: пароль restic (файл тільки для root, копія в 1Password), Wi-Fi (NetworkManager), паролі застосунків (gnome-keyring: 1Password не дає Secret Service на Linux). sops-nix/agenix не потрібні, поки немає системних секретів для boot.

### Агенти
- **Managed settings Claude Code** генерує NixOS-модуль: `/etc/claude-code/managed-settings.json`, змінюється тільки через switch, налаштування репо його не послаблять. Вміст: sandbox `enabled`, `failIfUnavailable`, `allowUnsandboxedCommands: false`; `credentials.files` deny для `~/.ssh`, `~/.config/gh`, `~/.local/share/keyrings`, `~/.1password`, профілю Zen; `network.allowedDomains` — GitHub, `cache.nixos.org`, cachix; `network.allowUnixSockets` — тільки сокет nix-daemon (сокети Docker і 1Password — ні); `Read(...)` deny на ті самі шляхи, бо інструмент Read працює поза sandbox. `bubblewrap` і `socat` — у системі. Точні ключі звірити з документацією Claude Code під час реалізації.
- **Codex** — ті самі обмеження через `/etc/codex/` (managed `config.toml`/`requirements.toml` з NixOS-модуля): sandbox `workspace-write` обов'язковий, ті самі deny на шляхи й домени. Точні ключі звірити з документацією Codex.
- `scripts/campaign` запускає агента (`claude` чи `codex`) цілком у bubblewrap: видно тільки `~/nixos`, `~/.claude` або `~/.codex` і сокет nix-daemon.
- **Сирі команди, які обгортає `dangonix`,** агентам заборонені тими самими managed settings (deny генерується з поля `wraps` таблиці команд): `nixos-rebuild`, `home-manager switch`, `switch-to-configuration`, `nix-env --set`, `nix-env -i`, `nix profile install`, `nix-collect-garbage`, `nix flake update`, `fwupdmgr update`, `fprintd-enroll`, `fprintd-delete`, `tailscale funnel`, `restic`, `systemctl start|stop|restart foundryvtt-*`, `nmcli … metered`, `Edit`/`Write` на `state.json` і `packages.json`. Агент змінює систему тільки через `dangonix`. Мені — тільки підказка: fish-функції `nixos-rebuild` і `home-manager` друкують «це робить `dangonix switch`», сира команда — `command nixos-rebuild …`; ручні кроки після exit 3 працюють.
- `.claude/settings.json` у репо лишається для allow/ask ([§12](#12-агенти)).
- **Перевірити при реалізації:** клітка `scripts/campaign` має бачити й fail-closed hook `~/.config/dangonix/hooks/bash-guard` ([§12](#12-агенти)), `~/.claude.json` і `~/.cache/nix`, інакше кожна Bash-команда героя падає; клієнт `nix` сам качає flake inputs і пише в `~/.cache/nix`, тож `allowedDomains` і дозволений запис мають це покривати (домени — з `flake.lock`); read-команди `dangonix` (`status`, `doctor`, `foundry status`, `security`) потребують D-Bus, systemd і сокета tailscaled — краще виключити `dangonix` із sandbox, ніж відкривати агенту session bus (там keyring з порожнім паролем); deny на `state.json`/`packages.json` має стосуватися тільки checkout'у, а квест, що змінює їхню схему, отримує виняток; `tailscale funnel` без sudo — через `tailscale set --operator=kit`, а не NOPASSWD.

### Бекапи
restic у власну теку на зовнішньому HDD (решту файлів диска не чіпає): `/home` без кешів і `/var/lib/foundryvtt-*`. Стартує сам, коли підключаю диск, і сповіщає «можна від'єднувати». `dangonix backup [list|now|check|restore]`; відновлення — тільки в окрему теку. Перевірене відновлення — умова переходу до LUKS. Згодом — друга копія в хмарі (там же — важливі файли з HDD, яких більше ніде немає).

### Політика (статична перевірка в `dangonix check`)
Падає, якщо: firewall вимкнено; відкриті порти не збігаються з задекларованим списком (кожен з причиною); порт 22 відкритий не тільки на `tailscale0`; SSH з паролем або root-логіном; NOPASSWD поза whitelist (`start|stop|restart` Foundry); `systemd-boot.editor` не `false`; `nix.settings.trusted-users` не тільки root; substituter без відомого ключа; автологін без LUKS або TPM без PIN; немає managed settings Claude Code або sandbox у них вимкнений; `kit` у групі `docker`.

### `dangonix security`
Один екран «щит»: рядок на перевірку (диск, Secure Boot, бекап, Foundry Funnel, SSH, оновлення, firewall-політика, блокування, відбиток, firmware, 1Password, агент) зі станом `✓ ! ✗ –` і командою-виправленням. Перевірки — таблиця даних, як таблиця команд: з неї вивід, `--json` і рядок «щит: N ✗ M !» у статусі `dangonix`; бар малює іконку щита з `dangonix --json security`. Оновлення: `!`, якщо `nixpkgs` або `zen-browser` у `flake.lock` старші за 14 днів. Firmware: рівень HSI з `fwupdmgr security`. 1Password: застосунок запущений, агент відповідає, приватних ключів у `~/.ssh` і токена в `~/.config/gh` немає.

**Не робимо:** антивірус, USBGuard, AppArmor/firejail, hardened kernel і профіль `hardened` (ламають Steam, Proton, `nix-ld`), `security.protectKernelImage` (вимикає гібернацію), VPN за замовчуванням, FIDO2-ключ (немає), DNS over TLS (поки).

## 12. Агенти
- **Claude Code і Codex на рівних.** Будь-який з них виконує або продовжує будь-який квест: стан — тільки в репо (`docs/tasks.md`, журнал `docs/progress.md` з рядком `agent:` у кожному записі, git). Одна процедура квесту `.agents/skills/quest/SKILL.md` (`/quest` у Claude, `$quest` у Codex), один `scripts/agent` для headless-запуску обох, суддя — окремий виклик `scripts/review`, тож може бути іншим агентом. Моделі за tier (squire, hero, cleric, judge) — таблиця в `AGENTS.md`. Graphify видалено; Zed `codex-acp` лишається. Обидва CLI з nixpkgs-unstable, self-updater off, оновлюються через `dangonix update`.
- **Дешевий виконавець, дорогий контроль.** Squire (Haiku 5.5) бере короткі механічні квести зі строгим oracle (`diff=none`, кілька кроків), hero (Sonnet 5.5) — решту, cleric (Opus) — ключові квести й ретраї, judge (Opus) — боси й long rest. Слабкість дешевої моделі — губить деталі на довгому контексті й упевнено помиляється — закривають `quest-verify` і ретрай cleric'ом, а не довіра до моделі. Тому квест на squire має бути коротким, а контекст — малим: hook `scripts/context-watch` (PostToolUse, тільки Claude Code) попереджає на 80k токенів «досить досліджувати» і на 95k «заверши або поверни квест `провалений кидок`», ретрай зберігає незакомічену роботу. Пороги — `DANGONIX_CTX_WARN`. Для Codex такого hook'а поки немає: формат його rollout-логу не перевірено. Ідея — з [r/ClaudeAI](https://www.reddit.com/r/ClaudeAI/s/1o8ZR3kjl3), 2026-10.
- **`AGENTS.md`** англійською, < 60 рядків, описує тільки те, що вже існує; `CLAUDE.md` — один рядок `@AGENTS.md`. Будь-яка зміна, на яку покладаються агенти, оновлює його в тому самому коміті. README — для мене, AGENTS.md — для агентів; не дублюють одне одного.
- **Інваріанти для агентів:** не чіпати `hardware-configuration.nix`; тема не змінює хост; кожна тема проходить `dangonix check`; не прибирати й не перебиндовувати наявні клавіші; clipboard і search — core; `settings.toml` Noctalia — тільки через named keys; `ask`-команди і `sudo` — тільки на запит; `state.json` — тільки на запит.
- **Цикл:** edit → `nix fmt` → `dangonix check --fast` → `dangonix check` → `scripts/closure-diff --assert-same HEAD` (або очікувані зміни); після зміни теми — `dangonix doctor`. Тести, що навмисно змінюють стан, — у тимчасовому worktree.
- **Guards однакові для обох:** permissions у `.claude/settings.json` і `.codex/rules/dangonix.rules` (`dangonix`-правила сталі, [§5](#effect-і-agent)); git hooks `scripts/hooks/` спрацьовують за `CLAUDECODE=1` або `DANGONIX_AGENT` (Codex ставить його з `.codex/config.toml`); `git-guard` і fail-closed hook `~/.config/dangonix/hooks/bash-guard || exit 2` в обох CLI (новий шлях одразу, бо нові речі з початку звуться по-новому; rename у c1q19 стосується тільки наявних `kit`-шляхів) блокує команди з `hardware-configuration.nix`. Це сильний guard, не гарантія — фінальна перевірка мій review diff'у.
- **Tooling:** `mcp-nixos` (опційно, канал 26.05; не знає options з flake inputs, для них — `scripts/opt`), плагін `claude-md-management` — єдиний (тільки Claude). Без hookify і formatting hook.
- Discovery: `dangonix commands --json`.

## 13. Запозичено з Omarchy 4.0
Ідея: один Quickshell-процес, CLI — джерело правди, shell — її клієнт. **Логіка живе в CLI і core-сервісах; shell лише малює UI.**

Взято: одна CLI з `--json`, firmware updates, cheatsheet (SUPER+F1), zoom і scale моніторів (runtime only), clipboard history (текст і картинки), Spotlight-search на SUPER+R (apps, dangonix-команди read/runtime, калькулятор, файли; backend — пізніше, напр. Walker чи Vicinae), автоматичні power profiles.

## 14. Свідомо поза scope
- **Відкладено:** `dangonix.textSize`; `dangonix display` (zoom і scale з CLI, поки тільки бінди); OCR, color picker, запис екрану; agent hotkey, tmux layouts, worktree helpers, timed passwordless sudo; calculator/emoji hotkeys, LocalSend, Wi-Fi QR, web apps, reminders, screensaver.
- **Безпека і data safety** ([§11](#11-безпека)) — кампанії II і III. До бекапів ніщо не захищає `/home`, світи Foundry і стан застосунків.
- **Відкинуто:** screenshot-to-theme pipeline, visual regression, одна палітра для всіх shell'ів, XP title bars через plugin, ThinkPad charge limit, multi-host.

## 15. Ручні кроки, що лишаються (inherent)
- Згенерувати `hardware-configuration.nix`, створити юзера `kit` в installer'і.
- Завантажити ліцензований Foundry ZIP для кожного інстансу; ліцензія, admin password, світи (`/var/lib/foundryvtt-<name>`) — дані.
- Записати відбитки (`dangonix fingerprint add`), Wi-Fi, Bluetooth, логіни в застосунки, логін у Claude Code.
- Безпека: пароль LUKS і TPM2 + PIN (`systemd-cryptenroll`), recovery key в 1Password, пароль BIOS supervisor, ключі Secure Boot (`sbctl`); вхід у 1Password (SSH-ключі в сховище, `op plugin init gh`, з'єднання розширення Zen); вхід у Tailscale (Funnel, ACL, вимкнений key expiry ноутбука); пароль restic.
- Палітра Noctalia (runtime-стан за рішенням); Noctalia plugins і EasyEffects presets — задекларувати, якщо можливо.
