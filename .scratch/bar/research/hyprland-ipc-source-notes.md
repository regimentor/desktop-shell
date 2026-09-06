# Hyprland IPC: первичные источники

Проверено 2026-09-06. Это исследование возможностей и ограничений, не выбор архитектуры. Текущая wiki описывает Latest git; установленная версия здесь не проверялась.

## Транспорт и события

Каталог сокетов: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/`. `.socket.sock` принимает запросы `[flags]/command args`; `.socket2.sock` передаёт поток `EVENT>>DATA\n`. Request-сокет обслуживается синхронно: открывать непосредственно перед запросом и закрывать после ответа; незакрытое соединение может задержать compositor до пятисекундного timeout. [IPC](https://wiki.hypr.land/IPC/)

Нужные семейства событий:

- Окна: `openwindow`, `closewindow`, `movewindowv2`, `activewindowv2`, `windowtitlev2`.
- Воркспейсы: `workspacev2`, `createworkspacev2`, `destroyworkspacev2`, `moveworkspacev2`, `renameworkspace`, `activespecialv2`.
- Мониторы: `focusedmonv2`, `monitoraddedv2`, `monitorremovedv2`.
- Раскладка: `activelayout` несёт имя клавиатуры и раскладки.
- Дополнительно: `configreloaded`, `urgent`, `pin`, события группирования.

`workspacev2` не покрывает перенос фокуса мышью между мониторами: нужен также `focusedmonv2`. `windowtitlev2` содержит адрес и заголовок, `activewindowv2` — адрес. [IPC, список событий](https://wiki.hypr.land/IPC/#events-list)

## Снимки и команды

JSON запрашивается флагом `j`: `j/clients`, `j/workspaces`, `j/monitors`, `j/devices`, `j/activewindow`, `j/version`. `clients` возвращает окна с их свойствами; `devices` — устройства ввода; `monitors` — активные мониторы, вариант `monitors all` включает неактивные. Полные JSON-схемы для целевой версии необходимо зафиксировать отдельно. Частые info-запросы могут замедлять compositor. [Using hyprctl](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Using-hyprctl/)

Раскладку можно переключать запросом `/switchxkblayout DEVICE next`, `prev` или числовым индексом; `DEVICE` может быть `all`. Выбор клавиатуры для модуля lang остаётся продуктовым решением. [switchxkblayout](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Using-hyprctl/#switchxkblayout)

Версия существенно влияет на команды: документация 0.54 описывает dispatchers `workspace`, `focuswindow`, `focusmonitor`, `togglespecialworkspace`; текущая wiki указывает, что с 0.55 hyprlang deprecated в пользу Lua. Современный пример: `/dispatch hl.dsp.focus({ workspace = "3" })`. Нельзя смешивать примеры разных версий без проверки установленного Hyprland. [Dispatchers 0.54](https://wiki.hypr.land/0.54.0/Configuring/Dispatchers/), [современные Dispatchers](https://wiki.hypr.land/Configuring/Basics/Dispatchers/), [современный dispatch](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Using-hyprctl/#dispatch)

## Восстановление и границы достоверности

В прочитанном `EventManager.cpp` новые подключения получают новые события, replay отсутствует; при переполнении очереди из 64 событий клиент отключается. Данные события ограничиваются 1024 байтами, внутренние переводы строки заменяются пробелами. Это детали прочитанного upstream main, не обещание для каждой версии. [EventManager.cpp](https://raw.githubusercontent.com/hyprwm/Hyprland/main/src/managers/EventManager.cpp)

Следствие для будущей спецификации: предусмотреть повторное соединение и восстановление снимков после разрыва; не считать событийный заголовок гарантированно полным. У источников нет заявленного атомарного snapshot+subscribe или sequence cursor, поэтому согласование начального снимка с событиями требует отдельного решения. Смена instance signature после перезапуска compositor также требует явной политики запуска/переподключения. Эти пункты — инженерные выводы из описанного транспорта, а не готовый алгоритм синхронизации.
