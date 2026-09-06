import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property AudioModel audio
    property bool available: false
    property string unavailableReason: "Проверка маршрутизации…"
    property string groupKey: ""
    property string message: ""
    property bool pending: false
    property var members: []
    property var target: null
    property var queue: []
    property int failures: 0
    property bool sending: false
    readonly property int confirmed: members.filter(node => audio.usable(node)
        && audio.targets(node).length === 1 && audio.targets(node)[0] === target).length
    onConfirmedChanged: finishIfConfirmed()
    Connections {
        target: root.audio
        function onOutputsChanged() {
            if (root.pending && !root.audio.outputs.includes(root.target)) root.finish("Устройство отключено");
        }
        function onReadyChanged() { root.check(); }
    }
    function check(): void {
        if (probe.running || pending) return;
        available = false;
        unavailableReason = "Проверка маршрутизации…";
        probe.running = true;
    }
    function move(group: var, output: var): void {
        if (!available || pending || writer.running || !group || !audio.outputs.includes(output)) return;
        groupKey = group.key;
        members = group.nodes.slice();
        target = output;
        failures = 0;
        queue = members.slice();
        pending = true;
        sending = true;
        message = "Переключение…";
        deadline.restart();
        sendNext();
    }
    function sendNext(): void {
        if (!pending) return;
        if (!audio.outputs.includes(target)) { finish("Устройство отключено"); return; }
        if (!queue.length) { sending = false; finishIfConfirmed(); return; }
        const node = queue[0];
        queue = queue.slice(1);
        if (!audio.usable(node)) { failures++; sendNext(); return; }
        // Argument array: no application metadata is interpreted by a shell.
        writer.command = ["timeout", "2", "pw-metadata", "-n", "default", String(node.id),
            "target.object", String(target.properties["object.serial"]), "Spa:Id"];
        writer.running = true;
    }
    function finishIfConfirmed(): void {
        if (pending && !sending && confirmed === members.length && !failures)
            finish("Выход переключён");
    }
    function finish(text: string): void {
        pending = false;
        queue = [];
        deadline.stop();
        message = text;
    }
    Process {
        id: probe
        // Only fixed, read-only commands; timeouts also cover missing services.
        command: ["sh", "-c", "command -v pw-metadata >/dev/null && command -v wpctl >/dev/null && command -v timeout >/dev/null || exit 10; timeout 2 wpctl settings linking.allow-moving-streams | grep -q 'Value: true' || exit 11; timeout 2 pw-metadata -l | grep -q 'Found \"default\" metadata' || exit 12"]
        onExited: (code, status) => {
            root.available = code === 0 && status === 0 && root.audio.ready;
            root.unavailableReason = root.available ? "" : code === 10 ? "Нужны pw-metadata, wpctl и timeout"
                : code === 11 ? "WirePlumber недоступен или перенос запрещён" : "Метаданные маршрутизации недоступны";
        }
    }
    Process {
        id: writer
        onExited: (code, status) => {
            if (!root.pending) return;
            if (code !== 0 || status !== 0) root.failures++;
            Qt.callLater(root.sendNext);
        }
    }
    Timer {
        id: deadline
        interval: 6000
        onTriggered: root.finish("Переключено " + root.confirmed + "/" + root.members.length
            + ". " + (root.failures ? "Ошибка команды переноса" : "Связи не подтверждены"))
    }
    Component.onCompleted: check()
}
