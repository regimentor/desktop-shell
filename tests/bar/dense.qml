import QtQuick
import Quickshell
import "runtime"
import "desktop/StateModel.js" as Model

ShellRoot {
    id: root
    AppIconResolver { id: iconResolver }
    SystemClock { id: wallClock }
    QtObject {
        id: fixture
        property bool ready: true
        property bool canChangeLayout: false
        function windowActive(address) { return address === "0x1"; }
        function windowUrgent(address) { return false; }
        function globalPosition(output, point) { return point; }
        property string language: "RU"
        property var data: {
            const output = Quickshell.screens[0].name;
            const snapshot = { version: { version: "0.56.2" },
                monitors: [{ name: output, activeWorkspace: { id: 1 }, specialWorkspace: { id: 0 } }],
                workspaces: [1, 2, 3, 4, 5].map(id => ({ id: id, name: String(id), monitor: output })),
                clients: Array.from({ length: 30 }, (_, i) => ({ address: "0x" + (i + 1).toString(16), class: "no-such-application", initialClass: "", title: "Long window title ".repeat(20), workspace: { id: i % 5 + 1 } })),
                activewindow: { address: "0x1" }, devices: { keyboards: [] } };
            return Model.reconcile(Model.empty(), snapshot, []);
        }
        function groups(output) { return Model.groups(data, output); }
        function title(output) { return Model.title(data, output); }
        function activateWorkspace() {}
        function activateWindow() {}
        function nextLayout() {}
    }
    Bar {
        id: panel
        screen: Quickshell.screens[0]
        anchors.right: false
        implicitWidth: 1024
        state: fixture
        icons: iconResolver
        clock: wallClock
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            const strip = root.find(panel.contentItem, "workspaces"), right = root.find(panel.contentItem, "rightModules");
            if (strip.groups.reduce((n,w) => n + w.windows.length, 0) !== 30 || strip.x + strip.width > right.x || panel.width !== 1024)
                console.error("DENSE_FAIL");
            else console.log("DENSE_PASS", "30 windows", "density", strip.density, "right", right.x);
        }
    }
    Timer { interval: 4000; running: true; onTriggered: Qt.quit() }
}
