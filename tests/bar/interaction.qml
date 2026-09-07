import QtQuick
import Quickshell
import "runtime"

ShellRoot {
    id: root
    property int tick: 0
    property var firstDelegate: null
    Theme { id: theme }
    QtObject {
        id: fixture
        function windowActive(address) { return false; }
        function windowUrgent(address) { return false; }
        function globalPosition(output, point) { return {x: point.x - 2560, y: point.y}; }
        property int active: 1
        property var data: ({ monitors: [{ name: "test", x: -2560, y: 0 }], urgent: {}, active: "" })
        function groups(output) {
            return [1, 2].map(id => ({ id: id, active: id === active, label: String(id), windows: [] }));
        }
    }
    Window {
        width: 400
        height: 40
        visible: true
        WorkspaceStrip { id: strip; x: 13; y: 9; output: "test"; hyprland: fixture; icons: null; theme: theme; availableWidth: 350 }
    }
    Timer {
        interval: 40
        running: true
        repeat: true
        onTriggered: {
            root.tick++;
            const delegates = strip.children[0].children.filter(item => item.workspace !== undefined);
            if (root.tick === 5) {
                root.firstDelegate = delegates[0];
                const point = strip.clickPosition(delegates[0], {x: 2, y: 3});
                if (point.x !== -2545 || point.y !== 12) { console.error("INTERACTION_FAIL mapping", point.x, point.y); Qt.quit(); return; }
                fixture.active = 2;
            } else if (root.tick === 6) {
                if (delegates[0] !== root.firstDelegate || delegates[0].color.a === 0) {
                    console.error("INTERACTION_FAIL delegate replaced or animation missing"); Qt.quit(); return;
                }
            } else if (root.tick === 10) {
                if (delegates[0] !== root.firstDelegate || delegates[0].color.a !== 0 || theme.workspaceAnimationDuration !== 150)
                    console.error("INTERACTION_FAIL final animation state");
                else console.log("INTERACTION_PASS stable delegates, 150 ms transition, click coordinates");
                Qt.quit();
            }
        }
    }
}
