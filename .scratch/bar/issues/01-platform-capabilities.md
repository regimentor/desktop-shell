# Возможности Quickshell для IPC, иконок и трея

Parent: [Панель Daevox: карта решений](../map.md)
Labels: wayfinder:research
Type: research
Status: resolved
Assignee: bar_research
Blocked by: none

## Question

Какие официальные API Quickshell и Hyprland позволяют реализовать панель на стеке launcher: события и снимки workspaces/windows/monitors, команды переключения и фокуса, раскладку через IPC, app icon resolution, StatusNotifier tray с меню, верхнюю панель с резервированием места? Указать ограничения, версии и варианты без shell-вызовов hyprctl. Факты отделить от рекомендаций; архитектуру за пользователя не выбирать.

## Answer

Подтверждены API моделей Hyprland, событий и запросов IPC без hyprctl, иконок, tray/menu, часов и панели на каждом мониторе. Установлен Quickshell 0.3.1; различия dispatch между версиями Hyprland и оговорки типов QML требуют проверки перед реализацией. Архитектура не выбрана.

Результат: [Возможности платформы для панели](../research/platform-capabilities.md), с дополнением [Hyprland IPC: первичные источники](../research/hyprland-ipc-source-notes.md). Исследовательская ветка недоступна: git-репозитория нет.
