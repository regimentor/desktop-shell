import QtQuick
import Quickshell
import "StateModel.js" as Model

Scope {
    id: root
    property alias socketDirectory: ipc.socketDirectory
    property alias timeoutMs: ipc.timeoutMs
    property bool ready: false
    property string error: ""
    property var data: Model.empty()
    property var snapshot: ({})
    property var pendingEvents: []
    property bool loading: false
    property bool dirty: false
    property int commandSerial: 0
    property var pendingQueries: []
    property var activeQueries: []
    readonly property bool canChangeLayout: ready && !!data.keyboard
    function globalPosition(output: string, point: var): var {
        const monitor = ready ? data.monitors.find(m => m.name === output) : null;
        return monitor ? {x: monitor.x + point.x, y: monitor.y + point.y} : null;
    }
    function windowActive(address: string): bool { return ready && data.active === address; }
    function windowUrgent(address: string): bool { return ready && !!data.urgent[address]; }
    readonly property string activeMonitor: ready ? ((data.monitors.find(m => m.focused) || {}).name || "") : ""
    function screenFor(screens: var): var {
        return screens.find(s => s.name === activeMonitor)
            || screens.slice().sort((a, b) => a.name.localeCompare(b.name))[0] || null;
    }
    readonly property string language: ready ? Model.language(data.keyboard) : "—"
    readonly property var queries: ["version", "monitors", "workspaces", "clients", "activewindow", "devices"]

    function refresh(): void {
        if (!ipc.online) return;
        if (loading) { dirty = true; return; }
        loading = true;
        dirty = false;
        activeQueries = pendingQueries.length ? queries.filter(k => pendingQueries.includes(k)) : queries;
        pendingQueries = [];
        for (const key of activeQueries) ipc.enqueue(key, "j/" + key);
    }
    function invalidate(keys: var): void {
        for (const key of keys) if (!pendingQueries.includes(key)) pendingQueries.push(key);
        if (loading) dirty = true;
        else if (!coalesce.running) coalesce.start();
    }
    function groups(output: string): var { return ready ? Model.groups(data, output) : []; }
    function title(output: string): string { return ready ? Model.title(data, output) : ""; }
    function command(text: string): void { if (ready) ipc.enqueue("command:" + (++commandSerial), text); }
    function activateWorkspace(output: string, group: var, cursor: var): void {
        if (!ready || !groups(output).some(w => w.id === group.id)) return;
        command(Model.atCursor([Model.focusMonitor(output), Model.workspaceCommand(group)], cursor));
    }
    function activateWindow(address: string, cursor: var): void {
        if (ready && data.clients.some(c => c.address === address)) command(Model.atCursor([Model.focusWindow(address)], cursor));
    }
    function nextLayout(): void {
        if (ready && data.keyboard && /^[\w.-]+$/.test(data.keyboard.name))
            command("/switchxkblayout " + data.keyboard.name + " next");
    }
    Timer { id: coalesce; interval: 40; onTriggered: root.refresh() }
    HyprlandIpc {
        id: ipc
        onOpened: root.refresh()
        onUnavailable: reason => {
            root.ready = false;
            if (root.error !== reason) console.warn("desktop:", reason);
            root.error = reason;
            root.data = Model.empty();
            root.loading = false;
            root.dirty = false;
            root.snapshot = {};
            root.pendingEvents = [];
            root.pendingQueries = [];
            root.activeQueries = [];
            coalesce.stop();
        }
        onEventReceived: line => {
            const split = line.indexOf(">>");
            if (split < 0) return;
            const name = line.slice(0, split), value = line.slice(split + 2);
            if (!/^(openwindow|closewindow|movewindow|activewindow|windowtitle|workspace|createworkspace|destroyworkspace|moveworkspace|renameworkspace|activespecial|focusedmon|monitoradded|monitorremoved|activelayout|configreloaded|urgent|pin|changegroup|moveintogroup|moveoutofgroup|togglegroup|fullscreen)/.test(name)) return;
            const address = value.split(",")[0];
            if (["openwindow", "activewindowv2", "urgent"].includes(name))
                root.pendingEvents.push({ name: name, address: address.startsWith("0x") ? address : "0x" + address });
            const keys = name.startsWith("windowtitle") ? ["clients", "activewindow"]
                : name === "activelayout" ? ["devices"]
                : name === "configreloaded" ? root.queries
                : ["monitors", "workspaces", "clients", "activewindow"];
            root.invalidate(keys);
        }
        onResponse: (key, body) => {
            if (key.startsWith("command:")) {
                if (!Model.commandSucceeded(body)) { ipc.fail("Command rejected: " + body.slice(0, 160)); return; }
                root.invalidate(["monitors", "workspaces", "clients", "activewindow", "devices"]);
                return;
            }
            try {
                root.snapshot[key] = JSON.parse(body);
                if (key !== root.activeQueries[root.activeQueries.length - 1]) return;
                Model.validate(root.snapshot);
                root.loading = false;
                if (root.dirty) { coalesce.restart(); return; }
                root.data = Model.reconcile(root.data, root.snapshot, root.pendingEvents);
                root.pendingEvents = [];
                root.ready = true;
                root.error = "";
                ipc.retryMs = 250;
            } catch (e) { ipc.fail("Invalid IPC response: " + e.message); }
        }
    }
}
