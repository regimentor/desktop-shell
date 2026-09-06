import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    property bool active: false
    property string label: "—"
    property bool refreshPending: false
    onActiveChanged: if (active) refresh()

    function refresh(): void {
        if (!active) return;
        if (query.running) { refreshPending = true; return; }
        refreshPending = false;
        query.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "activelayout" || event.name === "configreloaded") root.refresh();
        }
    }
    Process {
        id: query
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            root.label = "—";
            if (code === 0 && status === 0) {
                try {
                    const keyboards = JSON.parse(output.text).keyboards || [];
                    const keyboard = keyboards.find(item => item.main) || keyboards[0];
                    if (keyboard) {
                        const layout = (keyboard.layout || "").split(",")[keyboard.active_layout_index];
                        root.label = layout ? (layout === "us" ? "EN" : layout.toUpperCase())
                            : keyboard.active_keymap || "—";
                    }
                } catch (error) { root.label = "—"; }
            }
            if (root.refreshPending) Qt.callLater(root.refresh);
        }
    }
}
