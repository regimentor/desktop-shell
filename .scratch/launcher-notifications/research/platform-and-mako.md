# Возможности уведомлений и зависимости от mako

Дата: 2026-09-06. Исследование только чтением; процессы, сервисы и конфигурация сессии не менялись, содержимое уведомлений не запрашивалось.

## Вывод

Полная замена mako технически возможна на установленном Quickshell. Нужно спроектировать постоянно живущий сервер, отдельно жизненный цикл активных уведомлений и архив, UI всплывающих сообщений и переход всех способов автозапуска. Это исследовательский вывод, не утверждение, что совместимость уже проверена исполнением.

## Локальные факты

- `quickshell --version`: **0.3.1**, пакет Arch Linux. Установленный [qmltypes](/usr/lib/qt6/qml/Quickshell/Services/Notifications/quickshell-service-notifications.qmltypes) содержит NotificationServer, Notification, NotificationAction, urgency, tracked, expire/dismiss, resident/transient, image, hints и inline reply.
- mako **1.11.0-1** установлен, `pacman -Qi mako` сообщает Required By / Optional For: None.
- [Hyprland autostart](/home/evgen/.config/hypr/hyprland.lua:65) прямо выполняет `hl.exec_cmd("mako")` при `hyprland.start`.
- Read-only `GetNameOwner` на org.freedesktop.DBus вернул владельца `org.freedesktop.Notifications` **:1.363**; `GetConnectionUnixProcessID` сопоставил его с PID **180732**, `pgrep` подтвердил **mako**.
- `systemctl --user show mako.service`: **inactive**, **disabled**, unit [mako.service](/usr/lib/systemd/user/mako.service) запускает `/usr/bin/mako`, Type=dbus, BusName=org.freedesktop.Notifications. Отключение этого unit само по себе не устраняет прямой запуск из Hyprland.
- Пакет предоставляет [D-Bus activation](/usr/share/dbus-1/services/fr.emersion.mako.service): Name=org.freedesktop.Notifications, Exec=/usr/bin/mako, SystemdService=mako.service. Простого удаления строки автозапуска тоже недостаточно: нужно устранить возврат mako через D-Bus. [Официальный mako README](https://github.com/emersion/mako#running) подтверждает автоматический запуск по запросу уведомления.
- `~/.config/mako` отсутствует. Поиск mako / notify-send / notifications в `~/.config/hypr`, `~/.local/bin`, пользовательских systemd/autostart, `/etc/xdg`, пользовательских D-Bus services не выявил других интеграций mako или makoctl. Это ограниченная инвентаризация этих путей, не всего домашнего каталога.
- daevox-launcher.service и daevox-bar.service активны. [Launcher root](../../../launcher/shell.qml) содержит постоянно созданный Launcher и IPC; [Launcher](../../../launcher/Launcher.qml) скрывается через visible=false. [Пример сервиса](../../../docs/examples/daevox-launcher.service) задаёт Restart=on-failure. Вывод: сервер можно держать независимо от видимости лаунчера; выбор этого процесса или отдельного сервиса ещё предстоит согласовать.

## API и жизненный цикл

[NotificationServer](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/NotificationServer/) требует выставлять `tracked=true` при приёме; иначе сообщение отбрасывается. Большинство capabilities выключены по умолчанию: объявлять actions/images/markup/persistence следует лишь вместе с реализацией поведения. `keepOnReload=true` переносит активные объекты между QML reload, помечая `lastGeneration`; это не обещание сохранения на диск или после завершения процесса.

[Исходник server.cpp v0.3.1](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.1/src/services/notifications/server.cpp) показывает: сервер захватывает `org.freedesktop.Notifications`, при занятом имени ждёт его освобождения и повторяет регистрацию. Поэтому даже пробный экземпляр потенциально становится рабочим сервером. Обновление через `replaces_id` меняет существующий объект, **не испускает повторный notification signal**; UI и архив должны отслеживать изменения объекта. Сервер сообщает протокол **1.2**, поэтому нельзя обещать полную 1.3-совместимость только по наличию модуля. Хранилище живёт в памяти процесса.

По [Notification](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/Notification/), `dismiss()` означает закрытие пользователем, `expire()` — истечение времени; `tracked=false` эквивалентен dismiss. `closed(reason)` сообщает завершение; сохранение объекта через Retainable не сохраняет право вызывать действия. Следствие для модели: скрыть popup и закрыть уведомление — разные операции; архив закрытых сообщений хранит снимки, а не работающие кнопки.

[Протокол](https://specifications.freedesktop.org/notification/latest/protocol.html) задаёт таймаут в **миллисекундах**, -1 означает политику сервера, 0 — без автоматического истечения; закрытый ID больше недействителен. Persistence означает удержание уведомления до подтверждения/удаления/отзыва, а не просто наличие текстового журнала. Сроки хранения архива и обрезание активных уведомлений нужно согласовать с рекламируемой capability.

**Расхождение документации:** описание Quickshell называет expireTimeout секундами, но [notification.cpp v0.3.1](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.1/src/services/notifications/notification.cpp) напрямую присваивает входное значение D-Bus свойству, без деления на 1000; автоматического таймера там нет. При реализации проверять 1000 ms в изолированном тесте, не умножать значение вслепую. Тот же исходник запрещает вызовы действий и inline reply у закрытых retained-объектов; изображения из image-data представлены внутренним URL, а байтовые hints удалены. Следствие: одного сохранённого URL недостаточно для изображений в архиве после рестарта; нужна выбранная политика копирования либо fallback. В этом теге также виден подозрительный обратный guard `setText`: изменение подписи существующего action может не применяться. Нужен целевой compatibility test обновления actions на реально установленном пакете; патч дистрибутива здесь не проверялся.

[NotificationAction](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/NotificationAction/) предоставляет invoke; нерезидентное сообщение закрывается после действия. [Hints](https://specifications.freedesktop.org/notification/latest/hints.html) определяет resident как сохранение после действия, transient как обход persistence. Не сохранять transient в обычной истории — рекомендуемый совместимый вариант, требующий уточнения формулировки «все уведомления».

[Urgency](https://specifications.freedesktop.org/notification/latest/urgency-levels.html) различает Low, Normal, Critical и рекомендует не закрывать Critical автоматически. Пропуск Critical через DND, время скрытия popup и подавление звука — продуктовые решения. Sound hints можно получить через hints, но само наличие этих данных не означает воспроизведение звука сервером. Inline reply доступен в локальном API, но включать его следует после решения об охвате UI и тестов клиентов.

## Кандидат перехода и проверки — ещё не выполнены

1. Подготовить новый постоянно живущий сервер и проверить его в отдельной D-Bus сессии: Notify, replacement, CloseNotification, причины закрытия, actions/resident, transient, изображения, 0/-1/1000 ms, Critical, DND, reload/restart.
2. Выбрать, когда архив обрывает связь с активным объектом; проверить отключённые действия после закрытия и рестарта. Проверить остановленное приложение, пустые поля, всплеск сообщений и ограничение памяти.
3. Зафиксировать будущий запуск, восстановление после сбоя и готовность владельца D-Bus. Подготовить резервные копии конфигурации и понятный rollback.
4. Во время согласованного переключения убрать прямой autostart mako, исключить его D-Bus активацию, остановить текущий процесс, запустить выбранный сервер и проверить единственного владельца имени. Удаление пакета после проверки — самый прямой кандидат для полного отказа, но конкретная последовательность ещё не решение.
5. Проверить вход в новую сессию, падение/перезапуск сервера, закрытый launcher, Alt+3, новые сообщения из реальных приложений и отсутствие возврата mako. Не считать unit active достаточной проверкой владения D-Bus.

Не обещать перенос активных сообщений mako: стандарт не предоставляет метод экспорта истории/живых callback-связей. Импорт архива — отдельное решение, здесь частные сообщения не читались.

## Вопросы человеку

- История только до выхода или на диск; срок/лимит, изображения, данные на экране блокировки?
- DND подавляет Critical тоже? Transient исключаем из истории? Что значит прочитано и что удаляет «Очистить всё»?
- Как долго popup виден, где/на каком мониторе, очередь, hover, клик и keyboard focus?
- Нужны ли inline reply, звук, markup/ссылки, группировка/замена progress-уведомлений?
- Полный отказ включает удаление пакета сразу после приёмки или сначала промежуточный rollback-период?

## Контекст исследования

HEAD существовал: `04d7e788362158410e3566b4aa1adef7ef01e593`. Создана отдельная throwaway-ветка `research/notification-platform` в `/tmp/daevox-notification-research`, чтобы не переключать основной checkout с параллельными изменениями. Отчёт сохранён на этой ветке и скопирован в рабочую карту; runtime не запускался. Первичные источники: upstream docs/source/spec и перечисленные локальные файлы/команды. Проверка поведения работающего сервера Quickshell не проводилась.
