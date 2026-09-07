import QtQuick
import Quickshell
import "runtime"
import "desktop"
import "desktop/StateModel.js" as Model

ShellRoot {
    id: root
    property int stage: 0
    property var originalKeyboard: null
    DesktopState {
        id: state
        onErrorChanged: if (error) console.error("COMMAND_FAIL", error)
    }
    Timer {
        interval: 450
        repeat: true
        running: true
        onTriggered: {
            if (!state.ready) return;
            if (root.stage === 0) {
                root.originalKeyboard = state.data.keyboard;
                const monitor = state.data.monitors.find(m => m.focused);
                if (!monitor || !state.data.active) { console.error("COMMAND_FAIL no active window"); Qt.quit(); return; }
                state.activateWorkspace(monitor.name, state.groups(monitor.name).find(w => w.id === monitor.activeWorkspace.id));
                state.activateWindow(state.data.active);
            } else if (root.stage === 1) {
                console.log("COMMAND_FOCUS_PASS");
                state.nextLayout();
            } else if (root.stage === 2) {
                if (state.data.keyboard.active_layout_index === root.originalKeyboard.active_layout_index)
                    console.error("COMMAND_FAIL layout unchanged");
                else console.log("COMMAND_LAYOUT_PASS");
                state.command("/switchxkblayout " + root.originalKeyboard.name + " " + root.originalKeyboard.active_layout_index);
            } else if (root.stage === 3) {
                console.log("COMMAND_RESTORED", state.data.keyboard.active_layout_index === root.originalKeyboard.active_layout_index);
                Qt.quit();
            }
            root.stage++;
        }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.error("COMMAND_FAIL timeout"); Qt.quit(); } }
}
