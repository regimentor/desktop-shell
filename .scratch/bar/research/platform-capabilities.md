# Возможности платформы для панели

Проверено 2026-09-06. Исследование фактов для карты решений, не выбор архитектуры и не реализация.

## Версии и локальная база

- Локальный `quickshell --version`: **0.3.1, distributed by Arch Linux**. Ниже используются официальные страницы 0.3.1, кроме общей геометрии PanelWindow (0.3.0). Минимальная поддерживаемая версия ещё не выбрана.
- `launcher/shell.qml`, `launcher/AppModel.qml`, `launcher/KeyboardLayout.qml` уже используют Quickshell/QML. Последний читает `devices` через процесс `hyprctl -j devices`, обновляясь на `activelayout` и `configreloaded`; это факт текущего launcher, не обязательная схема панели.
- Git отсутствует по проверке родительской сессии: исследовательская ветка недоступна, материал сохранён рядом с картой.

## Проверенные API

| Область | Возможность и ограничение |
| --- | --- |
| Верхняя панель на каждом экране | `Quickshell.screens` обновляется при изменении мониторов; `Variants` создаёт/удаляет экземпляры окон. `PanelWindow` с anchors top/left/right и `exclusiveZone` резервирует место; нужны 1 или 3 anchors. [Screens](https://quickshell.org/docs/v0.3.1/types/Quickshell/Quickshell/), [PanelWindow](https://quickshell.org/docs/v0.3.0/types/Quickshell/PanelWindow/). |
| Workspaces и мониторы | `Hyprland.workspaces`, `monitors`, `monitorFor(screen)`; `HyprlandWorkspace.monitor`, `toplevels`, `active`, `focused`, `activate()`. Это позволяет связать панель с монитором и перечислить отдельные окна workspace; `active` — активен на своём мониторе, `focused` учитывает фокус монитора. [Hyprland](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/), [Workspace](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandWorkspace/). |
| Окна и заголовок | `Hyprland.activeToplevel`, `toplevels`; `HyprlandToplevel` предоставляет `title`, `address`, `workspace`, `monitor`, `lastIpcObject` и связь с Wayland handle. Некоторые значения могут быть null/пустыми до появления данных. `lastIpcObject` — последний снимок, а не гарантия непрерывного обновления всех полей. [HyprlandToplevel](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandToplevel/). |
| События и команды IPC | `Hyprland.rawEvent` получает события socket2, `dispatch` отправляет dispatcher, `refreshMonitors/Workspaces/Toplevels` обновляют снимки. Docs предупреждают, что не всякая инвалидирующая операция посылает событие. `usingLua` влияет на синтаксис dispatch. [Hyprland](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/). |
| Прямые запросы без hyprctl | `Quickshell.Io.Socket` подключается к Unix socket по `path`, предоставляет `write`, `flush`, `connected`, `error`; Hyprland отдаёт `requestSocketPath` и `eventSocketPath`. Прямой транспорт возможен, но framing ответа, завершение запроса, повторное соединение и порядок снимков/событий потребуют собственной обработки. Последнее — инженерное следствие API, не готовая гарантия библиотеки. [Socket](https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Socket/), [Hyprland](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/). |
| Иконки | Wayland `Toplevel.appId` может служить входом поиска. `DesktopEntries.byId` требует точное совпадение; `heuristicLookup` пытается подобрать запись, может ошибаться или вернуть null. `Quickshell.iconPath` разрешает системную иконку, поддерживает проверку наличия и fallback. Значит, соответствие каждого окна правильной иконке нельзя обещать без политики fallback/исключений. [Toplevel](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/Toplevel/), [DesktopEntries](https://quickshell.org/docs/v0.3.1/types/Quickshell/DesktopEntries/), [Icon path](https://quickshell.org/docs/v0.3.1/types/Quickshell/Quickshell/). |
| Трей | `SystemTray.items` обновляется автоматически. Элемент даёт `icon`, tooltip, `status`, `hasMenu`, `onlyMenu`; действия `activate`, `secondaryActivate`, `scroll`; меню через `display(parentWindow,x,y)` либо `menu` с `QsMenuAnchor`/`QsMenuOpener`. Docs описывают приблизительное соответствие KDE/freedesktop протоколу; совместимость каждого приложения требует проверки. Трей — самостоятельная служба, не источник Hyprland IPC. [SystemTray](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.SystemTray/SystemTray/), [SystemTrayItem](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.SystemTray/SystemTrayItem/). |
| Часы | `SystemClock` предоставляет дату, часы/минуты/секунды и precision; формат даты и времени остаётся решением интерфейса. [SystemClock](https://quickshell.org/docs/v0.3.1/types/Quickshell/SystemClock/). |

## Границы проверки

- Документация Hyprland 0.3.1 связывает `activeToplevel/toplevels` с `Quickshell.Wayland.Toplevel`, в то время как 0.2.0 указывала `HyprlandToplevel`. Точный тип и attached-access необходимо проверить короткой пробой установленной сборки до фиксации QML-контракта. [0.3.1](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/), [0.2.0](https://quickshell.org/docs/v0.2.0/types/Quickshell.Hyprland/Hyprland/).
- Высокоуровневый singleton Hyprland на проверенной странице не предоставляет модель клавиатур. Начальный `devices` и события `activelayout` доступны на уровне IPC; выбор основной клавиатуры и переключение требуют отдельного решения.
- Не проверялись запуск панели, реакция на hotplug/reconnect, восстановление после смены instance, special-workspaces и фактическая работа tray-меню. Ссылки подтверждают наличие API, а не готовность интеграции.
- Обычная Wayland `Toplevel.activate()` не доказывает выполнение требования «Hyprland через IPC»: для IPC-фокуса отдельно доступны Hyprland dispatchers. Синтаксис привязывается к версии композитора.

## Дополнение по протоколу Hyprland

[Официальные источники и ограничения IPC](hyprland-ipc-source-notes.md) содержат socket paths, снимки, события, команды и различия версии с Lua. Выбор между встроенными моделями с дополнительным запросом и своим IPC-клиентом остаётся архитектурным решением.
