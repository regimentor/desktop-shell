# Daevox launcher

Отдельное приложение Quickshell для Hyprland. Проверено на Quickshell 0.3.1,
Qt 6.11.2, Hyprland 0.56.2 и активной UWSM-сессии.

## Файлы

```text
launcher/
├── shell.qml
├── Launcher.qml
├── AppModel.qml
├── AudioModel.qml
├── AudioRouter.qml
├── AudioMath.js
├── AudioControls.qml
├── AudioPane.qml
├── Theme.qml
└── .qmlls.ini
docs/examples/
├── daevox-launcher.service
└── hyprland-launcher.lua
```

## Зависимости и ручная проверка

Из корня репозитория, в терминале графической сессии:

```bash
# Только если пакеты отсутствуют; -Syu избегает частичного обновления Arch.
sudo pacman -Syu --needed quickshell qt6-declarative qt6-svg uwsm ghostty
# Необязательно: fallback-тема, если текущая тема не содержит нужных иконок.
sudo pacman -S --needed adwaita-icon-theme

qs --version
qs --no-duplicate --path ./launcher/shell.qml
```

Процесс остаётся в терминале, окно изначально скрыто. Из второго терминала:

```bash
qs ipc --path ./launcher/shell.qml call launcher toggle
qs ipc --path ./launcher/shell.qml call launcher status
qs ipc --path ./launcher/shell.qml call launcher close
```

`open` открывает Apps с пустым запросом, в том числе при повторном вызове.
`close` идемпотентен. Закрытие окна сохраняет процесс и модель.
`--no-duplicate` защищает от повторного запуска той же конфигурации.
IPC запускает краткоживущий клиент `qs`, но не второй QML runtime.

## Установка и автозапуск

Для установки или обновления запустите от обычного пользователя, без sudo:

```bash
./install-launcher.sh
```

Скрипт работает из любой директории, проверяет зависимости, устанавливает
файлы и включает user-service. В активной графической сессии launcher будет
перезапущен; иначе запустится при следующем входе. Lua bind выводится в
терминал. `--help` показывает справку.

Установщик также доставляет `shared/DaevoxTheme.qml` и создаёт ссылку
`daevox-launcher/shared → ../shared`. При ручном копировании нужно сохранить
эту структуру; предпочтительно повторно запустить `install-launcher.sh`.

Юнит привязан к `graphical-session.target`: UWSM подготавливает окружение
Wayland, systemd запускает один процесс и останавливает его вместе с сессией.
Запускать `enable --now` следует внутри уже работающей UWSM-сессии.
`RestartSec` — задержка восстановления после сбоя, не ожидание готовности сессии.
Дополнительный `exec-once` не нужен.

При обновлении повторите копирование файлов и:

```bash
systemctl --user restart daevox-launcher.service
```

## Hyprland Lua

Добавьте содержимое `docs/examples/hyprland-launcher.lua` в свой Lua-конфиг:

```lua
hl.bind("SUPER + Space", hl.dsp.exec_cmd(
    'qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher toggle'
))
```

Затем `hyprctl reload`. Уберите прежний bind на Super+Space, если он есть.
Для проверки без установки замените путь в команде на абсолютный путь к
`launcher/shell.qml` в репозитории.

## Ghostty и desktop entries

Поставьте `com.mitchellh.ghostty.desktop` первой строкой в
`~/.config/xdg-terminals.list`, сохранив остальные строки. Если существует
`~/.config/Hyprland-xdg-terminals.list`, проверьте и его: UWSM сначала читает
настройку для текущего desktop. Это задаёт терминал для `Terminal=true`.
Отдельный бинарник `xdg-terminal-exec` для используемого `uwsm app` не нужен:
выбор терминала реализован в UWSM.

`DesktopEntry.execute()` в Quickshell 0.3.1 не обрабатывает Terminal и field
codes полноценно. Поэтому `AppModel.launch()` передаёт desktop ID штатному
`uwsm app -t service -- <id>.desktop` через `Process`, без оболочки и разбора
Exec в QML. UWSM сохраняет quoting, Path, Terminal и field codes. При запуске
без файлов/URL `%U/%u/%F/%f` убираются. Приложение работает в отдельном
systemd user service и не завершается вместе с launcher.

Окно закрывается после успешного запуска service. Ошибки UWSM видны внизу
окна и в журнале. Успешное создание service не гарантирует, что само
приложение не упадёт позже: его вывод находится в user journal.
Desktop actions не выводятся в MVP; точка расширения — `AppModel.launch()`.

## Поиск и управление

Модель `DesktopEntries.applications` читается один раз и обновляется самим
Quickshell при изменениях desktop entries. Она учитывает XDG data directories,
включая `/usr/share/applications` и `~/.local/share/applications`, и исключает
Hidden/NoDisplay. Поиск локальный: имя → generic name → comment → keywords →
разобранная command. Каждое слово запроса должно совпасть хотя бы с одним
полем. Точное имя выше префикса, префикс выше подстроки; равные результаты
сортируются по имени и ID. Регистр игнорируется, ё нормализуется в е.
Полноценного fuzzy и автоматической смены раскладки запроса в MVP нет.
Алгоритм можно заменить в `score()`/`rank()`.

| Клавиши | Действие |
| --- | --- |
| Up / Ctrl+K / Shift+Tab | Предыдущий результат |
| Down / Ctrl+J / Tab | Следующий результат |
| Enter | Запустить выбранное приложение |
| Escape | Очистить запрос; при пустом запросе закрыть окно |

Навигация циклическая, выбор сбрасывается при изменении выдачи. Пустая выдача
безопасна. Повторный Enter при удержании игнорируется. Ctrl+J/K используют
физические XKB-коды 44/45 из Qt Wayland, поэтому работают в стандартных EN/RU
раскладках. При отсутствии nativeScanCode используются логические J/K.
Up/Down/Enter/Escape не зависят от раскладки. При открытии запрос очищается,
поле сразу получает фокус, выделения старого текста нет.

## Режим «Звук»

Alt+1 / Alt+2 и отдельные облачки над окном переключают Apps / «Звук».
Открытие начинает с Apps; открытие и переключение режима очищают поиск.
В режиме «Звук» сначала выбрана системная громкость текущего выхода по
умолчанию. Она остаётся доступной при фильтрации приложений.

| Клавиши | Действие в режиме «Звук» |
| --- | --- |
| ↑ / ↓ | Выбрать системную строку, приложение или раскрытый поток |
| ← / → | Изменить громкость выбранной строки на 5 процентных пунктов |
| Ctrl+← / Ctrl+→ в поиске | Перемещать курсор по словам |
| Enter | Раскрыть или свернуть потоки приложения |
| Alt+M | Переключить mute выбранной строки |
| Alt+O | Выбрать выход приложения или устройство по умолчанию для системной громкости |
| Tab / Shift+Tab | Обойти доступные контролы |
| Esc | Закрыть список выходов; иначе очистить запрос, затем закрыть окно |

Ползунки поддерживают перетаскивание и задают 0–100%. Внешние значения
выше 100% показываются числом без исправления. Общий уровень приложения —
максимум уровней его потоков; изменение сохраняет пропорции (80/40 → 60/30).
Известные пропорции потоков и баланс каналов сохраняются в памяти при
проходе через ноль. Новый состав группы без полной истории поднимается
из нуля на одинаковые уровни. Изменение громкости не снимает mute.
Смешанный mute обозначается отдельно; общий toggle сначала глушит все,
следующий включает все. Системный mute действует только на текущий выход
по умолчанию и не меняет mute потоков.

`AudioModel.qml` наблюдает PipeWire, объединяет точный application.id,
затем client.id текущего соединения; неизвестные потоки остаются отдельными.
Пауза и mute не исключают существующий поток. DesktopEntries определяет
название и иконку, но не заменяет ключ группировки. Состояние восстанавливает
WirePlumber; лаунчер не хранит настройки звука на диске и не применяет их
при открытии или появлении потока.

Для маршрутизации нужны WirePlumber, `wpctl`, `pw-metadata`, `timeout` и
разрешённая политика `linking.allow-moving-streams`. `AudioRouter.qml`
проверяет доступность при входе в режим и отправляет `target.object`
через массив аргументов `pw-metadata`. Подтверждением служат реальные
активные или приостановленные связи. Через 6 секунд неподтверждённый
перенос показывает число успешно переключённых потоков; исчезновение
цели прерывает ожидание. Разные связи отображаются как «Разные выходы».
При недоступном механизме выбор выхода отключён с причиной внизу окна.
Отсутствие устройства не блокирует остальные доступные контролы.

Отключение устройств следует политике WirePlumber, в том числе возможному
автоматическому переходу. Лаунчер не меняет общую конфигурацию аудиосистемы,
не включает automute и не управляет микрофонами.

## Проверки звука

```bash
node tests/audio/math.test.cjs
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml launcher/*.qml tests/audio/*.qml
bash -n install-launcher.sh tests/audio/run-session.sh
dbus-run-session -- bash tests/audio/run-session.sh
# В активной Hyprland-сессии; кратко открывает тестовое окно.
dbus-run-session -- bash tests/audio/run-session.sh ui
```

Интеграционный тест создаёт отдельные PipeWire/WirePlumber, виртуальные
выходы и беззвучные потоки; профиль WirePlumber `policy` не запускает
аппаратные мониторы. Состояние и конфигурация теста хранятся в `/tmp`.
Проверены шкала и баланс каналов, 80/40 → 60/30, проход через ноль,
смешанный mute, смена default, реальный перенос, новый состав группы,
частичный отказ, отключение цели, запрет переноса и отсутствие выходов.
Wayland-тест проверяет Qt key/mouse events, поиск, Esc, переключение
режимов из контролов, раскрытие потоков, список выходов, Tab и drag.
Путь к журналам и PNG панели выводится после теста; снимок просмотрен.

Проверка физических Bluetooth/HDMI-отключений, аппаратной клавиатуры
EN/RU и клика снаружи остаётся ручной приёмкой. В изолированной сессии
возможны предупреждения RTKit/desktop portal, не относящиеся к QML.

API сверены с [исходником громкости Quickshell 0.3.1](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.1/src/services/pipewire/node.cpp)
и [групп связей](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.1/src/services/pipewire/link.cpp):
QML уже использует визуальную шкалу, а сами группы связей нужно привязывать
через PwObjectTracker для получения их состояния.
Маршрутизация соответствует [политике WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/policies/linking.html)
и [интерфейсу pw-metadata](https://docs.pipewire.org/page_man_pw-metadata_1.html).

## Окно и иконки

`PanelWindow` без anchors центрируется на активном мониторе. Overlay-слой
отображается поверх workspace и не резервирует место для панели. Ширина
560 логических px, на маленьком экране размеры ограничены. Цвета, размеры,
скругление и шрифты находятся в экземпляре `Theme`, без глобального singleton.
Тень статическая, анимаций и polling нет. Палитра — Catppuccin Mocha,
акцент — Mauve. Используется установленный системный шрифт Monoid во всех
текстовых элементах. Проверка шрифта: `fc-match Monoid`. Высота строки —
48 px, одновременно видны шесть результатов; остальные доступны прокруткой.

`HyprlandFocusGrab` закрывает окно при клике снаружи или снятии захвата
композитором. Простое движение мыши наружу его не закрывает. Это надёжнее,
чем закрывать окно на промежуточном изменении Qt activeFocus при создании
Wayland surface. Esc и IPC close доступны независимо от захвата.

`Quickshell.iconPath()` использует текущую Qt icon theme и поддерживает
абсолютные icon paths. Сначала запрашивается иконка entry, затем
`application-x-executable`; если обе отсутствуют или загрузка не удалась,
показывается первая буква имени. Копий иконок в проекте нет.

`.qmlls.ini` содержит пути для Arch. Quickshell может автоматически переписать
его при запуске, добавив путь к своему виртуальному дереву типов — это нормально.

## Диагностика

```bash
systemctl --user status daevox-launcher.service
journalctl --user -u daevox-launcher.service -b -n 80
qs list
qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" show
qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher status
qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher open
qs log --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" -t 80
hyprctl layers
hyprctl configerrors
systemctl --user is-active graphical-session.target
systemctl --user show-environment | rg '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_CURRENT_DESKTOP)='
```

Если IPC не находит instance, проверьте одинаковый путь у daemon и клиента.
При `visible:true` проверьте слой `daevox-launcher` и активный монитор.
Если не запускается entry, проверьте непосредственно
`uwsm app -t service -- firefox.desktop` и `journalctl --user -b -n 80`.
Если каталог пуст, проверьте XDG_DATA_HOME/XDG_DATA_DIRS процесса.

Статическая проверка на Arch:

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml launcher/*.qml
```

Метаданные пакета 0.3.1 дают два предупреждения линтера: PanelWindow отмечен
как uncreatable до платформенной подстановки Quickshell, а QProcess::ExitStatus
не разрешается в qmltypes. Реальный `qs` загружает оба API без ошибок.

## Проверки реализации

В реальной Wayland-сессии выполнены QtTest-проверки ранжирования по нескольким
полям, регистра и кириллицы, фокуса, клавиш, пустой выдачи, Enter/Esc и десяти
циклов toggle. Четыре временные desktop entries проверили `%U/%u/%F/%f`,
`%i/%c/%k`, quoting и Path через настоящий UWSM. Проверены отрисовка и
защита от дубликатов. Пользовательские bind и автозапуск автоматически не
изменялись. Клик снаружи и физическая клавиатура EN/RU требуют ручной
приёмки; тесты проверяли Qt key events и обработку nativeScanCode.

## Проверенные API и источники

- [DesktopEntries](https://quickshell.org/docs/v0.3.0/types/Quickshell/DesktopEntries/): системный каталог.
- [DesktopEntry](https://quickshell.org/docs/v0.3.0/types/Quickshell/DesktopEntry/) и
  [реализация 0.3.1](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.1/src/core/desktopentry.cpp): метаданные и ограничения execute.
- [IpcHandler](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/IpcHandler/): типизированные toggle/open/close/status.
- [PanelWindow](https://quickshell.org/docs/v0.3.0/types/Quickshell/PanelWindow/) и
  [WlrLayershell](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/WlrLayershell/): overlay и keyboard focus.
- [HyprlandFocusGrab](https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/HyprlandFocusGrab/): закрытие снаружи.
- [Quickshell.iconPath](https://quickshell.org/docs/v0.3.0/types/Quickshell/Quickshell/): theme resolution.
- [Qt KeyEvent](https://doc.qt.io/qt-6/qml-qtquick-keyevent.html): nativeScanCode.
- [UWSM](https://github.com/Vladimir-csp/uwsm): desktop launch и systemd session lifecycle;
  сверено также с установленными `uwsm app --help` и `/usr/share/doc/uwsm/README.md`.
- [Hyprland Lua binds](https://wiki.hypr.land/Configuring/Basics/Binds/): hl.bind и hl.dsp.exec_cmd.

Документация Quickshell использует раздел v0.3.0 для ветки 0.3;
сигнатуры сверены с установленными qmltypes 0.3.1 и рабочим runtime.
