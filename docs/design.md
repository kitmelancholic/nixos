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
state.json              вибір, який робить dangonix: { theme, foundry.instances }
lib/
  settings.nix          user, host, system, held inputs
  mk-home.nix           одна home-конфігурація на тему
  checks.nix            всі flake checks, generic по реєстру, + host build
  dangonix/
    default.nix         пакет dangonix (writeShellApplication)
    commands.nix        таблиця команд — single source of truth
    dangonix.sh         код CLI як справжній файл, не Nix-рядок
hosts/nixos/            єдиний хост; + boot.nix (Plymouth), foundry.nix (інстанси)
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
scripts/quest-verify, campaign, lint-docs, lint-commits, next-version
.github/workflows/ci.yml  eval + лінт + oracle на кожен push, без збірки
docs/themes.md          довідка по контракту + інтерв'ю для нової теми
.mcp.json, .claude/settings.json, CLAUDE.md
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
`experimental` лише ховає тему з `dangonix theme` без `--all` і ніколи не послаблює перевірки. Виняток — тимчасовий warning mode для Caelestia (stage 18 → P2.3).

### Ролі (контракт)
Ядро (Hyprland, apps, input, frontend-сервіси) викликає **ролі**, а не провайдерів. Нова тема = "заповни ролі й пройди перевірки". Чотири види:
- **command** — тема дає команду, core bind її викликає;
- **provider** — тема називає провайдера і user unit, що його запускає; exclusive — рівно один увімкнений;
- **declaration** — факт, який читають checks і docs;
- **frontend with default** — core володіє даними і CLI, тема *може* дати UI поверх них; інакше — core default UI.

| Роль | Вид | Обов'язкова | Де використовується |
|---|---|---|---|
| `launcher` | command | так (→ `search` у P2.5) | SUPER+R |
| `session` | command | так | SUPER+Escape, SUPER+Shift+W |
| `osd` | command ×8 | так | XF86 (гучність, мікрофон, яскравість, підсвітка) |
| `screenshot` | command | так (`region`, `full`; `window` опц.) | Print, Shift+Print, SUPER+Print |
| `lock` | provider | рівно один | `loginctl lock-session`, idle, suspend |
| `idle`, `bar`, `notifications`, `polkit` | provider | рівно один | checks, `dangonix doctor` |
| `wallpaper` | provider | так | checks |
| `batteryWarning` | provider | так (з P2.8) | shell або `themes/common/low-battery-notify.nix` |
| `palette` | declaration | так | `shell \| static` |
| `toolkit` | declaration | так | GTK/Qt/cursor: `shell \| none` |
| `keybindings`, `clipboard`, `search` | frontend with default | ні | SUPER+F1, `dangonix clipboard`, SUPER+R |
| `windowSwitcher`, `controlCenter`, `settings` | command | ні | ALT+Tab, SUPER+S, SUPER+comma |

Ніколи не ролі (core): terminal, explorer, browser, editor, Claude key, керування вікнами, workspaces 1-5, mouse drag/resize, zoom і scale, input, монітори, default apps.

Обов'язкова роль без провайдера → помилка evaluation: `theme <id>: role <role> has no provider`.

### Бінди — це дані
Кожен bind — запис з описом: `{ key = "SUPER+Return"; action = …; description = "Open terminal"; }`. Ідентичність bind'а — **повний resolved запис**: ключ, action, аргументи, всі flags. Ключі нормалізуються (`mod` → `SUPER`, фіксований порядок модифікаторів SUPER, CTRL, ALT, SHIFT, роздільник ` + `). З тих самих даних генеруються `hyprland.lua`, cheatsheet (`keys.json`), перевірка дублікатів і frozen fixture — тому вони не можуть розійтись.

Правило: кожен наявний bind лишається (з усіма flags). Нові — тільки на вільні клавіші. Cheatsheet — SUPER+F1 (однаково під UA і EN), search — апгрейд launcher'а на SUPER+R; SUPER+Space лишається "float toggle", SUPER+K — "focus up".

### Перевірки (static, `lib/checks.nix`, на кожну тему)
1. **Registry** — унікальні id, `themes/<family>` існує, поля manifest валідні, `dangonix.theme.id == id`, `state.json` theme є в реєстрі. Інваріанти family — assertions у самому модулі family.
2. **Roles** — всі обов'язкові ролі задані (evaluation-time, ловить `dangonix check --fast`).
3. **Providers** — для кожної exclusive ролі рівно один увімкнений провайдер. Другого шукають у таблиці відомих HM options (`services.dunst`, `programs.waybar`, `services.cliphist`, ...) і в деклараціях самої теми.
4. **Bindings** — frozen fixture (кожен запис на місці і незмінний), ключі ролей присутні, у кожного bind'а є опис, немає дублікатів resolved ключів.
5. **Executables** — перше слово кожної role-команди є в `home-path/bin` теми або це абсолютний store path.
6. **Builds** — host toplevel, activation package кожної теми, `Hyprland --verify-config`.
7. **Command table** — кожна підкоманда в таблиці, у кожної є `effect`/`agent`/kind, не-`read` мають `--dry`, `.claude/settings.json` збігається зі згенерованим.

Runtime-відповідник — **`dangonix doctor`**: один власник `org.freedesktop.Notifications` (і це заявлений провайдер), зареєстрований polkit agent, запущений idle daemon, один writer clipboard history.

### Що не варте того
- **Генератор тем зі скріншота.** Цю роботу робить агент; безпечною її роблять контракт, checks і оракул.
- **Автоматична visual regression.** GPU/EGL-квірки, flaky, дорого. Подивитись очима після `dangonix theme <id>` дешевше.
- **Одна палітра для всіх shell'ів.** Кожен має свій theming engine; контракт лише вимагає *задекларувати* джерело палітри і toolkit.
- **Багато families.** Кожна — external input, що churn'ить з Hyprland/Quickshell. 2-3 максимум.
- **XP title bars через Hyprland plugin.** Плагіни мусять збігатись з точною ревізією Hyprland — це проти цілі 1. Тільки свідомим рішенням в інтерв'ю.

Відкладено до першої власної Quickshell-теми: `dangonix.textSize` (одна опція для shell, GTK і терміналу) і Qt QML agent skill (TheQtCompanyRnD/agent-skills).

`docs/themes.md` — чекліст інтерв'ю для нової теми: bar (позиція, вміст), launcher, session menu, lock screen, notifications, декорації вікон (plugin так/ні), light/dark, які опційні ролі і frontend UI.

### Noctalia: runtime-стан
`~/.local/state/noctalia/settings.toml` застосовується останнім, тому перемагає декларації. Activation step пише **тільки іменовані ключі**: telemetry off, вимкнення приватного clipboard store, wallpaper (з `assets/`). Решта, включно з палітрою, — runtime-стан, змінюється в GUI Noctalia. Перевірки ніколи не видаляють цей файл.

## 4. `state.json`
Відстежуваний файл з усім, що може вибрати команда, і нічим більше:
```json
{ "theme": "noctalia",
  "foundry": { "instances": { "main": { "version": "…", "port": 30000 } } } }
```
- dangonix редагує його через `jq` (temp file + atomic rename), показує diff і **ніколи не комітить** — комічу я.
- Хост отримує тільки `state.foundry`, ніколи `state.theme` — зміна теми не може дійти до хоста by construction.
- Foundry: тільки інстанси з `version` і `port`; порожній `instances` = Foundry немає. Ім'я інстансу — `[a-z0-9-]+`, порти унікальні. Filename і hash беруться з власної таблиці версій nix-foundryvtt. Деталі — [§9](#9-foundry-vtt).
- Gitignored-файл відкинуто: flake бачить лише tracked файли, а fresh install втратив би вибір.

## 5. `dangonix`
Одна `writeShellApplication`, код у `lib/dangonix/dangonix.sh`. Nix інжектить конфіг (host, user, held inputs, шлях до репо, таблиця версій Foundry) і таблицю команд. `apps.default = dangonix`.

### Команди
| Команда | effect | agent | Що робить |
|---|---|---|---|
| `dangonix` | read | allow | статус (тема, power mode, Foundry) + help |
| `dangonix commands` | read | allow | всі команди з описом, effect, agent (`--json` — API для агентів/shell'ів) |
| `dangonix switch [--home\|--host] [--backup]` | host | ask | транзакція: build host + home, nvd diff, активувати хост (тільки якщо змінився), потім home |
| `dangonix check [--fast\|--vm]` | read | allow | завжди: лінт доків і комітів, shellcheck; full: `nix flake check` (static, host, всі теми, verify, контракт); `--fast`: тільки eval, без IFD; `--vm`: VM-тести транзакцій (`packages.dangonix-vm`) |
| `dangonix doctor` | read | allow | runtime-перевірка ролей активної теми |
| `dangonix update [input...]` | state | ask | оновити всі inputs крім held, `dangonix check`, при помилці повернути `flake.lock`; ніколи не switch'ить і не комітить |
| `dangonix theme` | read | allow | список тем: selected (`state.json`) і active |
| `dangonix theme <id>` | state | ask | записати тему в `state.json`, зібрати й активувати home |
| `dangonix foundry [list]` | read | allow | інстанси: версія, порт, стан, URL |
| `dangonix foundry status\|logs\|check <name>` | read | allow | один інстанс |
| `dangonix foundry start\|stop\|restart\|open <name>` | runtime | **ask** | керування `foundryvtt-<name>.service` (зупинка обірве гру) |
| `dangonix foundry add <name> <zip> [--port N] [--copy-from <name>]` | host | ask | імпорт ZIP, новий інстанс у `state.json`, switch host; `--copy-from` копіює дані іншого інстансу |
| `dangonix foundry upgrade <name> <zip>` | host | ask | імпорт ZIP, нова версія для інстансу, switch host; між major — тільки з `--backed-up` |
| `dangonix foundry remove <name>` | host | ask | прибрати інстанс зі `state.json`, switch host; дані лишаються на диску |
| `dangonix foundry import <zip>` | state | ask | тільки імпорт ZIP (store + GC root) для версії, що вже є в `state.json`; для fresh install |
| `dangonix firmware [--refresh]` | read | allow | пристрої й оновлення; metadata refresh, якщо старша за 24 год |
| `dangonix firmware update` | host | ask | застосувати firmware updates, тільки на запит |
| `dangonix power [auto\|saver\|balanced\|performance]` | runtime | allow | статус / override енергорежиму ([§7](#7-енергія-і-фон)) |
| `dangonix data [auto\|saver\|normal]` | runtime | allow | статус / override режиму трафіку ([§8](#8-трафік)) |
| `dangonix net metered [on\|off]` | state | ask | позначити поточне з'єднання NetworkManager як лімітне назавжди |
| `dangonix keys` | read | allow | cheatsheet з реальних даних біндів |
| `dangonix clipboard [list\|pick\|clear]` | read/runtime/state | **ask** | історія clipboard (може містити паролі) |
| `dangonix rollback` (опц.) | host | ask | rollback одною командою |

Форматування — `nix fmt`, не обгортається.

Глобальні флаги **перед** підкомандою: `--json` (один JSON на stdout, логи на stderr), `--dry` (кожна не-`read` команда: що зробила б, без змін), `--flake <path>`. Приклад: `dangonix --dry switch`.

### `effect` і `agent`
| effect | Значення | У search | `--json` перевірка | Lock |
|---|---|---|---|---|
| `read` | нічого не змінює надовго | так | запускається реально | ні |
| `runtime` | зворотня зміна, зникає після stop/reboot | так | з `--dry` | ні |
| `state` | пише `state.json`, `flake.lock` або user data | ні | з `--dry` | так |
| `host` | змінює або активує системну конфігурацію | ні | з `--dry` | так |

`agent` (`allow | ask`) — окреме поле для Claude Code permissions. Default: `allow` для read/runtime, `ask` для state/host; винятки — Foundry service control і clipboard (`ask`). Rules генеруються з таблиці по конкретних формах аргументів (напр. ask на `dangonix theme noctalia`, але `dangonix theme` — allow). `dangonix --dry …` — один allow rule.

З таблиці генеруються: help, fish completions, `dangonix commands --json`, що показує search, що проганяє `--json`-перевірка, хто бере lock, permissions для Claude Code.

### Транзакції
Два види мутацій, обидва під lock'ом:
- **configuration transaction** — `switch`, `theme <id>`, `update`, `foundry add|upgrade|remove`. Мають recovery.
- **irreversible operation** — `firmware update`, `clipboard clear`, `foundry import`. Lock + `--dry` + `ask`, без rollback; dangonix каже про це перед дією, JSON має `reversible: false`. Імпорт ZIP усередині `foundry add|upgrade` — теж irreversible крок, але транзакція навколо нього відкочується; `reversible: false` стосується тільки імпорту.

Кроки транзакції:
1. Відмова, якщо `$USER` ≠ `kit`.
2. `flock -n` на `$XDG_RUNTIME_DIR/dangonix.lock`; друга мутуюча команда падає одразу.
3. Snapshot: `state.json` (+ `flake.lock` із sha256 для `update`), поточні host і home generations.
4. Preflight: payload кожного інстансу з `state.json` мусить бути в store.
5. Редагування `state.json`.
6. Build задіяних сторін одним `nix build`.
7. nvd diff.
8. Host — тільки якщо задіяний і відрізняється від `/run/current-system`: `nix-env --set` профілю + `switch-to-configuration switch`.
9. Home: `nix-env --set` профілю + `activate --driver-version 1` (dangonix сам вирішує, куди вказує профіль).
10. Release lock, показати `git diff` змінених файлів.

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
- `dangonix update` пропускає **held list** (`hyprland`, `noctalia`, `caelestia`), якщо input не названо явно; повідомляє про held.
- Gate — `dangonix check`: збирає host toplevel і кожну тему; при помилці повертає `flake.lock` байт-у-байт; ніколи не switch'ить.
- CI на GitHub — другий, eval-only gate: та сама `check --fast` і оракул на кожен push. CD немає: switch завжди робиш ти.
- Kernel — `linuxPackages_latest`, оновлюється тільки через gated `dangonix update`.
- Login: SDDM + `thyx`, спільний для всіх тем. Plymouth — host-owned, остання ціль.

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
- Foundry VTT і Docker стартують на запит, не при boot (`docker.socket` лишається).
- fwupd: refresh timer вимкнено; оновлення тільки через `dangonix firmware update`.
- Low-battery warning — роль: рівно один попереджувач.
- Відкинуто: ThinkPad charge limit.

## 8. Трафік
Ціль: на хотспоті з лімітом ГБ система сама перестає качати зайве.

**Тригер.** NetworkManager тримає прапорець лімітного з'єднання (`Metered` = `yes` або `guess-yes`), і `dangonix-saver` слухає саме його. Мій телефон — iPhone, а iOS-хотспот, на відміну від Android, сам себе лімітним не оголошує. Тому:
- `dangonix net metered on` один раз позначає поточне з'єднання (хотспот iPhone) як лімітне в його профілі NM — далі воно визначається саме;
- опційно: авто-позначення нових з'єднань, чий шлюз у `172.20.10.0/28` (підмережа iOS Personal Hotspot), — перевірити в research spike. Override `dangonix data saver|normal` — у `$XDG_RUNTIME_DIR`, як у power.

**Що робить `saver`** (той самий `dangonix-saver`):
1. **Власні завантаження dangonix:** `update`, `switch`, `foundry add|upgrade`, `firmware` показують розмір завантаження (`nix build --dry-run`) і вимагають `--metered-ok`. Metadata refresh fwupd пропускається.
2. **Фонові завантажувачі на паузу:** список units `dangonix.data.pauseUnits` зупиняється на вході в saver і відновлюється на виході. Склад списку визначає research spike нижче.
3. **Застосунки, що поважають metered самі** (PackageKit, GNOME-застосунки), нічого не потребують.
4. **Опційно, якщо spike покаже, що варто:** мережевий kill-switch для переліку застосунків — вони запускаються в `apps-metered.slice`, nftables `socket cgroupv2` відкидає їхній трафік, поки з'єднання лімітне.

Постійно, незалежно від режиму (дешево і корисно): у Zen вимкнені prefetch, DNS prefetch і autoplay відео (`policies.json`), telemetry вимкнена всюди, де є опція.

Чесне обмеження: більшість Linux-застосунків прапорець metered ігнорують. «Всі застосунки в режимі економії» гарантує тільки kill-switch (п. 4), а він ламає ці застосунки на хотспоті — тому він опційний і за списком.

**Research spike (перед реалізацією):** виміряти, що качає у фоні на цій машині за годину idle (`bandwhich`/`nethogs`); перевірити Steam, Zen, Vesktop, Zed, Noctalia, Docker на власні налаштування економії; вирішити, чи потрібен kill-switch.

## 9. Foundry VTT
Кілька версій поруч, кожна зі своїми конфігами і світами, запускаються окремо.

- Модуль nix-foundryvtt однoінстансний (один `foundryvtt.service`, один `dataDir`), тому хост має власний `hosts/nixos/foundry.nix`. Він з `state.foundry.instances` генерує по unit'у на інстанс і перевикористовує пакети nix-foundryvtt (`foundryvtt_<major>` + `overrideAttrs` на точну версію).
- **Інстанс `<name>`:** unit `foundryvtt-<name>.service`, дані `/var/lib/foundryvtt-<name>/{Config,Data,Logs}` (свої `options.json`, ліцензія, світи, модулі), порт зі `state.json`. Firewall відкриває порти всіх інстансів.
- Один системний юзер і група `foundryvtt`; `kit` у групі (group-writable дані, як зараз) і має NOPASSWD sudo тільки на `start|stop|restart` кожного unit'а.
- Жоден інстанс не стартує при boot. Кілька можуть працювати одночасно на різних портах.
- **Major upgrade** мігрує світи in-place без дороги назад, тому `foundry upgrade` між major вимагає `--backed-up`. Безпечніший шлях — `foundry add v14 <zip> --copy-from main`: новий інстанс з копією даних, старий лишається.
- `foundry remove` ніколи не видаляє дані; видалити `/var/lib/foundryvtt-<name>` — мій ручний крок.
- **Міграція:** поточний `/var/lib/foundryvtt` стає інстансом `main` (`/var/lib/foundryvtt-main`) — одноразовий ручний крок після backup.
- Ризик: умови ліцензії Foundry щодо одночасного запуску кількох інстансів з одним ключем — перевірити до реалізації.

## 10. Агенти
- **Тільки Claude Code.** Graphify і Codex repo tooling видалено (Zed `codex-acp` лишається — це фіча редактора). CLI з nixpkgs-unstable, self-updater off, оновлюється через `dangonix update`.
- **`CLAUDE.md`** англійською, < 60 рядків, описує тільки те, що вже існує. Будь-яка зміна, на яку покладаються агенти, оновлює його в тому самому коміті. README — для мене, CLAUDE.md — для агентів; не дублюють одне одного.
- **Інваріанти для агентів:** не чіпати `hardware-configuration.nix`; тема не змінює хост; кожна тема проходить `dangonix check`; не прибирати й не перебиндовувати наявні клавіші; clipboard і search — core; `settings.toml` Noctalia — тільки через named keys; `ask`-команди і `sudo` — тільки на запит; `state.json` — тільки на запит.
- **Цикл:** edit → `nix fmt` → `dangonix check --fast` → `dangonix check` → `scripts/closure-diff --assert-same HEAD` (або очікувані зміни); після зміни теми — `dangonix doctor`. Тести, що навмисно змінюють стан, — у тимчасовому worktree.
- **Guards:** permissions у `.claude/settings.json` (генеруються з таблиці команд); fail-closed Bash hook `~/.config/dangonix/hooks/bash-guard || exit 2` (новий шлях одразу, бо нові речі з початку звуться по-новому; rename у c1q17 стосується тільки наявних `kit`-шляхів) блокує команди з `hardware-configuration.nix`. Це сильний guard, не гарантія — фінальна перевірка мій review diff'у.
- **Tooling:** `mcp-nixos` (опційно, канал 26.05; не знає options з flake inputs), плагін `claude-md-management` — єдиний. Без hookify і formatting hook.
- Discovery: `dangonix commands --json`.

## 11. Запозичено з Omarchy 4.0
Ідея: один Quickshell-процес, CLI — джерело правди, shell — її клієнт. **Логіка живе в CLI і core-сервісах; shell лише малює UI.**

Взято: одна CLI з `--json`, firmware updates, cheatsheet (SUPER+F1), zoom і scale моніторів (runtime only), clipboard history (текст і картинки), Spotlight-search на SUPER+R (apps, dangonix-команди read/runtime, калькулятор, файли; backend — пізніше, напр. Walker чи Vicinae), автоматичні power profiles.

## 12. Свідомо поза scope
- **Відкладено:** `dangonix.textSize`; OCR, color picker, запис екрану; agent hotkey, tmux layouts, worktree helpers, timed passwordless sudo, декларативні налаштування Claude Code; calculator/emoji hotkeys, LocalSend, Wi-Fi QR, web apps, reminders, screensaver.
- **Data safety — окремий етап після phase 2:** backups `/home` і даних Foundry, snapshots, secrets у репо (sops-nix/agenix), FIDO2 для sudo. До того ніщо не захищає `/home`, світи Foundry і стан застосунків.
- **Відкинуто:** screenshot-to-theme pipeline, visual regression, одна палітра для всіх shell'ів, XP title bars через plugin, ThinkPad charge limit, multi-host.

## 13. Ручні кроки, що лишаються (inherent)
- Згенерувати `hardware-configuration.nix`, створити юзера `kit` в installer'і.
- Завантажити ліцензований Foundry ZIP для кожного інстансу; ліцензія, admin password, світи (`/var/lib/foundryvtt-<name>`) — дані.
- Fingerprint, Wi-Fi, Bluetooth, логіни в застосунки, SSH keys, `gh auth`, логін у Claude Code.
- Палітра Noctalia (runtime-стан за рішенням); Noctalia plugins і EasyEffects presets — задекларувати, якщо можливо.
