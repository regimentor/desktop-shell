# Проверка модели окон в установленном Quickshell

Parent: [Панель Daevox: карта решений](../map.md)
Labels: wayfinder:task
Type: task
Status: resolved
Assignee: codex
Blocked by: 01

## Question

Проверить минимальной временной QML-пробой в установленном Quickshell 0.3.1 фактические типы `Hyprland.toplevels`, `activeToplevel`, связь окна с workspace/monitor и доступ к appId/class. Документация разных версий расходится; эта проверка снимает неопределённость перед выбором архитектуры, не реализуя панель. Зафиксировать вывод и условия запуска; если живая Hyprland-сессия недоступна, явно оставить проверку незавершённой.

## Answer

Выполнена живая read-only QML-проба на Quickshell 0.3.1 / Hyprland 0.56.2. [Результаты и воспроизведение](../research/installed-window-model.md).

Элементы модели — `HyprlandToplevel`, а не Wayland Toplevel. Подтверждены workspace membership, `lastIpcObject.class/initialClass`, `wayland.appId`, attached handle и связь наблюдавшихся окон с монитором после повторной загрузки. Прямого `window.appId` нет. У `activeToplevel` установленная декларация указывает `HyprlandToplevel`, но в живой пробе значение оставалось null.

Обнаружена неполнота встроенной модели мониторов/активного окна относительно прямых IPC-снимков даже после повторного refresh. Причина не установлена; ограничение передано в архитектурное решение. Проба завершена как проверка фактического поведения, а не как подтверждение исправности всех API.
