# Need review

Відомі слабкі місця, які не ламають нічого зараз, але варто вирішити, перш
ніж вони стануть проблемою. Коли пункт вирішено, видали його і згадай коміт
у журналі.

## Бінд без ролі тихо зникає

*Знайдено:* огляд c1q21 (2026-10-24). *Коли:* campaign II, коли Caelestia
вмикає `dangonix.hyprland.coreBinds`.

`home/hyprland/binds.nix` відкидає запис, чия роль у темі `null`
(`lib.filter (entry: entry.action != null)`). Для `status = stable` це
безпечно: контракт (`themes/contract.nix`) робить відсутню обов'язкову роль
помилкою. Для `experimental` відсутня роль - лише warning, тож клавіша
пропаде з `hyprland.lua` без помилки, а це суперечить інваріанту «never
remove or rebind an existing key binding».

Варіанти: падати в `coreBinds` на темі з відсутніми ролями; або лишати
клавішу з заглушкою (`notify-send "<role>: no provider"`); або хоча б
перелічувати відкинуті клавіші в warning `dangonix check`.

## Команда ролі не екранується в Lua

*Знайдено:* огляд c1q21 (2026-10-24). *Коли:* перед першою роллю з лапками
або `\` у команді.

`exec` у `home/hyprland/binds.nix` підставляє команду ролі в Lua-рядок як є:
`hl.dsp.exec_cmd("${command}")`. Команда з `"` або `\` дасть зламаний
`hyprland.lua`, і Hyprland не завантажить конфіг. Зараз таких команд немає
(усі `noctalia msg …`).

Варіанти: екранувати через helper у `home/hyprland/lua-helpers.nix` (`\` і
`"`, або Lua long string `[[…]]`); або перевірка в `themes/contract.nix`, що
команда ролі не містить `"` і `\`.
