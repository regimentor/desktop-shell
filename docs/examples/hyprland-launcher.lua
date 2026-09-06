-- Hyprland 0.56.x: add this to your Lua config after installing the launcher.
-- The short-lived qs IPC client controls the existing QML process.
hl.bind("SUPER + Space", hl.dsp.exec_cmd(
    'qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher toggle'
))
