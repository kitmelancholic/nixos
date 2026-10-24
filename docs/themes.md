# Теми

Тема змінює лише home-конфігурацію і ніколи хост. Контракт, ролі, перевірки і
політика описані в [design §3](design.md#перевірки-static-libchecksnix-на-кожну-тему);
тут тільки те, що потрібне, коли пишеш або міняєш тему.

## Контракт

- Тема заповнює ролі `dangonix.roles.*` (`themes/contract.nix`); ядро викликає ролі,
  а не програми. У Noctalia ролі в `themes/noctalia/roles.nix`.
- Обов'язкова роль без значення: помилка evaluation (`theme <id>: role <role> has no
  provider`); в `experimental` темі лише warning.
- Exclusive-роль (`lock`, `idle`, `bar`, `notifications`, `polkit`, `wallpaper`) має
  рівно одного увімкненого провайдера: його user unit має `WantedBy`, і жодна
  відома програма-конкурент (`programs.waybar`, `services.dunst`, …) не увімкнена.
  Таблиця конкурентів у `themes/contract.nix`.
- Кожен bind ядра має опис (`home/hyprland/binds.nix`), resolved ключі не повторюються.
- Перше слово кожної role-команди є в `home-path/bin` теми або це абсолютний
  store path.
- Тема задає `dangonix.look.appearance` ([вигляд](design.md#вигляд)).

Перевірки 3, 4 і 5 (`providers`, `bindings`, `executables` у `lib/checks.nix`) йдуть
на кожну тему в `dangonix check`; перевірка 3 ще й падає як assertion теми з
тим самим текстом. Після перемикання: `dangonix doctor`.

## Інтерв'ю для нової теми

Перш ніж писати модуль, з'ясуй з GM:

1. Bar: позиція, вміст.
2. Launcher і search.
3. Session menu.
4. Lock screen і як він веде відбиток ([§10](design.md#10-відбиток-пальця)).
5. Notifications.
6. Декорації вікон: plugin так чи ні (plugin мусить збігатись з ревізією Hyprland).
7. Світла чи темна: `dangonix.look.appearance`.
8. Які опційні ролі (`windowSwitcher`, `controlCenter`, `settings`) і frontend UI.

## Відкладено

До першої власної Quickshell-теми:

- `dangonix.textSize`: одна опція розміру тексту для shell, GTK і терміналу.
- Qt QML agent skill (TheQtCompanyRnD/agent-skills).
