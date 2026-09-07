import QtQuick
import Quickshell
import "runtime"
import "desktop"

ShellRoot {
    id: root
    DesktopState { id: barState }
    AppIconResolver { id: iconResolver }
    SystemClock { id: wallClock; precision: SystemClock.Minutes }
    Variants {
        id: panels
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            state: barState
            icons: iconResolver
            clock: wallClock
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            if (!barState.ready) { console.error("UI_FAIL", barState.error); Qt.quit(); return; }
            for (const panel of panels.instances) {
                const strip = root.find(panel.contentItem, "workspaces");
                const right = root.find(panel.contentItem, "rightModules");
                if (!strip || !right || strip.x + strip.width > right.x || panel.exclusiveZone !== 36) {
                    console.error("UI_FAIL geometry"); Qt.quit(); return;
                }
                console.log("UI_PANEL", panel.screen.name, "width", panel.width, "groups", strip.groups.length, "reserved", panel.exclusiveZone);
            }
            console.log("UI_READY");
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}
