# Исходники runtime Daevox Shell

Снимок создаётся командой `python3 scripts/update-source-snapshot.py`.

## shell.qml

```qml
//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
import QtQuick
import Quickshell
import Quickshell.Io
import "desktop" as Desktop
import "bar" as Bar
import "launcher" as Launcher

ShellRoot {
    id: root
    Desktop.DesktopState { id: desktopState }
    Bar.BarRuntime { desktop: desktopState }
    Loader {
        id: notificationRuntime
        active: Quickshell.env("DAEVOX_NOTIFICATIONS") === "1"
        Component.onCompleted: if (active) setSource(Qt.resolvedUrl("notifications/NotificationRuntime.qml"), {desktop: desktopState})
    }
    Launcher.Launcher {
        id: launcher
        desktop: desktopState
        notifications: notificationRuntime.item ? notificationRuntime.item.model : null
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle(); }
        function open(): void { launcher.open(); }
        function close(): void { launcher.close(); }
        function notifications(): void { launcher.openMode("notifications"); }
        function status(): string { return launcher.status(); }
    }
}
```

## desktop/DesktopState.qml

```qml
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
```

## desktop/HyprlandIpc.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string socketDirectory: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property int timeoutMs: 2500
    property int generation: 0
    property bool online: false
    property var queue: []
    property var requestSocket: null
    property var eventSocket: null
    property int retryMs: 250
    signal opened()
    signal eventReceived(string line)
    signal response(string key, string body)
    signal unavailable(string reason)

    function start(): void {
        retry.stop();
        const socket = eventFactory.createObject(root, { epoch: generation });
        eventSocket = socket;
        deadline.restart();
        socket.connected = true;
    }
    function fail(reason: string): void {
        ++generation;
        online = false;
        queue = [];
        deadline.stop();
        const request = requestSocket, events = eventSocket;
        requestSocket = null;
        eventSocket = null;
        if (request) { request.connected = false; request.destroy(); }
        if (events) { events.connected = false; events.destroy(); }
        unavailable(reason);
        retry.interval = retryMs;
        retryMs = Math.min(8000, retryMs * 2);
        retry.restart();
    }
    function enqueue(key: string, command: string): void {
        if (!online) return;
        queue.push({ key: key, command: command });
        pump();
    }
    function pump(): void {
        if (!online || requestSocket || !queue.length) return;
        const job = queue.shift();
        const socket = requestFactory.createObject(root, { epoch: generation, key: job.key, command: job.command });
        requestSocket = socket;
        deadline.restart();
        socket.connected = true;
    }
    function finish(socket: var): void {
        if (!socket || socket.epoch !== generation || socket !== requestSocket) return;
        deadline.stop();
        requestSocket = null;
        const key = socket.key, body = socket.body;
        socket.destroy();
        response(key, body);
        Qt.callLater(pump);
    }
    Component.onCompleted: start()
    Timer { id: retry; onTriggered: root.start() }
    Timer { id: deadline; interval: root.timeoutMs; onTriggered: root.fail("IPC timeout") }
    Component {
        id: eventFactory
        Socket {
            id: events
            required property int epoch
            path: root.socketDirectory + "/.socket2.sock"
            parser: SplitParser {
                onRead: data => {
                    if (events.epoch === root.generation && events.connected)
                        root.eventReceived(data);
                }
            }
            onConnectionStateChanged: {
                if (epoch !== root.generation) return;
                if (connected) {
                    root.deadlineStop();
                    root.online = true;
                    root.opened();
                } else root.fail("Event stream disconnected");
            }
            onError: error => { if (epoch === root.generation) root.fail("Event socket error " + error); }
        }
    }
    function deadlineStop(): void { deadline.stop(); }
    Component {
        id: requestFactory
        Socket {
            id: request
            required property int epoch
            required property string key
            required property string command
            property bool sent: false
            readonly property string body: collector.text
            path: root.socketDirectory + "/.socket.sock"
            // Collect bytes before decoding, including UTF-8 split across reads.
            parser: StdioCollector { id: collector; waitForEnd: false }
            onConnectionStateChanged: {
                if (epoch !== root.generation) return;
                if (connected) { sent = true; write(command); flush(); }
                else if (sent) Qt.callLater(() => root.finish(request));
            }
            onError: error => {
                // PeerClosedError is the normal response delimiter on this socket.
                if (epoch === root.generation && !(error === 1 && sent))
                    root.fail("Request socket error " + error);
            }
        }
    }
}
```

## desktop/StateModel.js

```javascript
.pragma library

function empty() {
    return { monitors: [], workspaces: [], clients: [], active: "", keyboard: null, history: {}, urgent: {} };
}
function validate(s) {
    if (!s.version || typeof s.version.version !== "string" || !/^0\.56\.2(?:$|[-+])/.test(s.version.version))
        throw new Error("Requires Hyprland 0.56.2");
    if (!Array.isArray(s.monitors) || !Array.isArray(s.workspaces) || !Array.isArray(s.clients)
        || !s.devices || !Array.isArray(s.devices.keyboards) || !s.activewindow || typeof s.activewindow !== "object" || Array.isArray(s.activewindow))
        throw new Error("Invalid snapshot schema");
    if (s.monitors.some(m => typeof m.name !== "string" || !m.activeWorkspace || !m.specialWorkspace
            || typeof m.activeWorkspace.id !== "number" || typeof m.specialWorkspace.id !== "number")
        || s.workspaces.some(w => typeof w.id !== "number" || typeof w.monitor !== "string" || typeof w.name !== "string")
        || s.clients.some(c => typeof c.address !== "string" || !c.workspace || typeof c.workspace.id !== "number" || typeof c.title !== "string"))
        throw new Error("Invalid monitor/workspace/window schema");
    if (s.devices.keyboards.some(k => !k || typeof k.name !== "string"))
        throw new Error("Invalid keyboard schema");
}
function focus(history, workspace, address) {
    history[workspace] = (history[workspace] || []).filter(a => a !== address).concat(address);
}
function reconcile(previous, s, events) {
    validate(s);
    const addresses = s.clients.map(c => c.address);
    const order = previous.clients.map(c => c.address).filter(a => addresses.includes(a));
    for (const event of events) {
        if (event.name === "openwindow" && addresses.includes(event.address) && !order.includes(event.address)) order.push(event.address);
    }
    for (const a of addresses) if (!order.includes(a)) order.push(a);
    const clients = order.map(a => s.clients.find(c => c.address === a));
    const history = {}, urgent = {};
    for (const w of s.workspaces) {
        const own = clients.filter(c => c.workspace.id === w.id).map(c => c.address);
        history[w.id] = (previous.history[w.id] || []).filter(a => own.includes(a));
        if (!history[w.id].length && own.includes(w.lastwindow)) focus(history, w.id, w.lastwindow);
    }
    for (const a of Object.keys(previous.urgent)) if (addresses.includes(a)) urgent[a] = true;
    for (const event of events) {
        const c = clients.find(c => c.address === event.address);
        if (event.name === "urgent" && c) urgent[c.address] = true;
        if (event.name === "activewindowv2" && c) { focus(history, c.workspace.id, c.address); delete urgent[c.address]; }
    }
    const active = clients.find(c => c.address === s.activewindow.address);
    if (active) { focus(history, active.workspace.id, active.address); delete urgent[active.address]; }
    return { monitors: s.monitors, workspaces: s.workspaces, clients: clients,
        active: active ? active.address : "", keyboard: s.devices.keyboards.find(k => k.main) || s.devices.keyboards[0] || null,
        history: history, urgent: urgent };
}
function groups(state, output) {
    const monitor = state.monitors.find(m => m.name === output);
    if (!monitor) return [];
    const workspaces = state.workspaces.filter(w => w.monitor === output).slice();
    if (!workspaces.some(w => w.id === monitor.activeWorkspace.id))
        workspaces.push({ id: monitor.activeWorkspace.id, name: monitor.activeWorkspace.name, monitor: output });
    const result = workspaces.map(w => ({ id: w.id, name: w.name, special: w.id < 0,
        active: w.id === monitor.activeWorkspace.id || w.id === monitor.specialWorkspace.id,
        windows: state.clients.filter(c => c.workspace.id === w.id) }))
        .filter(w => !w.special || w.active || w.windows.length)
        .sort((a, b) => Number(a.special) - Number(b.special) || a.id - b.id);
    const specialCount = result.filter(w => w.special).length;
    return result.map(w => Object.assign({}, w, { label: w.special ? (specialCount === 1 ? "S" : w.name.replace(/^special:/, "")) : String(w.id) }));
}
function title(state, output) {
    const monitor = state.monitors.find(m => m.name === output);
    if (!monitor) return "";
    const workspace = monitor.specialWorkspace.id || monitor.activeWorkspace.id;
    const clients = state.clients.filter(c => c.workspace.id === workspace);
    const history = state.history[workspace] || [];
    const last = clients.find(c => c.address === history[history.length - 1]) || clients[0];
    return last ? last.title : "";
}
function language(keyboard) {
    if (!keyboard) return "—";
    const layout = (keyboard.layout || "").split(",")[keyboard.active_layout_index];
    if (layout) return layout.trim() === "us" ? "EN" : layout.trim().toUpperCase();
    const name = keyboard.active_keymap || "";
    const known = { "English (US)": "EN", "Russian": "RU" };
    return known[name] || name.slice(0, 3).toUpperCase() || "—";
}
// Lua quoted strings: do not interpolate window/workspace metadata as executable code.
function quote(value) {
    return '"' + String(value).replace(/[\\";\[\]\x00-\x1f\x7f]/g, c => "\\" + c.charCodeAt(0).toString().padStart(3, "0")) + '"';
}
function focusWindow(address) { return "/dispatch hl.dsp.focus({ window = " + quote("address:" + address) + " })"; }
function focusMonitor(output) { return "/dispatch hl.dsp.focus({ monitor = " + quote(output) + " })"; }
function workspaceCommand(group) {
    return group.special ? "/dispatch hl.dsp.workspace.toggle_special(" + quote(group.name.replace(/^special:/, "")) + ")"
        : "/dispatch hl.dsp.focus({ workspace = " + quote(String(group.id)) + " })";
}

// Hyprland executes a batch synchronously, before painting the next frame.
// Restore the click position in that same request, including monitor/window warps.
function atCursor(commands, cursor) {
    if (!cursor || !Number.isFinite(cursor.x) || !Number.isFinite(cursor.y))
        return "[[BATCH]]" + commands.join(";");
    return "[[BATCH]]" + commands.concat("/dispatch hl.dsp.cursor.move({ x = "
        + Math.round(cursor.x) + ", y = " + Math.round(cursor.y) + " })").join(";");
}
function commandSucceeded(body) {
    return body.trim().split(/\s+/).every(part => part === "ok");
}
```

## bar/AppIconResolver.qml

```qml
import QtQuick
import Quickshell

QtObject {
    id: root
    property var cache: ({})
    readonly property var catalogue: DesktopEntries.applications.values
    onCatalogueChanged: cache = ({})
    function resolve(appClass: string, initialClass: string): string {
        const key = appClass + "\n" + initialClass;
        if (cache[key]) return cache[key];
        let entry = null;
        for (const name of [appClass, initialClass]) {
            if (name) entry = DesktopEntries.byId(name.replace(/\.desktop$/, ""));
            if (entry) break;
        }
        if (!entry) for (const name of [appClass, initialClass]) {
            if (name) entry = DesktopEntries.heuristicLookup(name);
            if (entry) break;
        }
        const icon = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
        const fallback = Quickshell.iconPath("application-x-executable", true) || Qt.resolvedUrl("application.svg").toString();
        cache[key] = icon || fallback;
        return cache[key];
    }
}
```

## bar/Bar.qml

```qml
import QtQuick
import QtQuick.Controls
import Quickshell

PanelWindow {
    id: barWindow
    required property var state
    required property var icons
    required property var clock
    Theme { id: barTheme }
    anchors { top: true; left: true; right: true }
    implicitHeight: barTheme.height + barTheme.margin
    exclusiveZone: implicitHeight
    color: "transparent"
    Rectangle {
        x: barTheme.margin - 1
        y: barTheme.margin - 2
        width: parent.width - 2 * x
        height: barTheme.height + 2
        radius: barTheme.radius + 1
        color: barTheme.shadow
    }
    Rectangle {
        id: surface
        x: barTheme.margin
        y: barTheme.margin
        width: parent.width - 2 * barTheme.margin
        height: barTheme.height
        radius: barTheme.radius
        color: barTheme.background
        border.width: 1
        border.color: barTheme.border
        WorkspaceStrip {
            id: workspaces
            objectName: "workspaces"
            x: barTheme.padding
            anchors.verticalCenter: parent.verticalCenter
            hyprland: barWindow.state
            icons: barWindow.icons
            theme: barTheme
            output: barWindow.screen ? barWindow.screen.name : ""
            availableWidth: Math.max(0, right.x - x - 8)
        }
        Text {
            id: title
            objectName: "windowTitle"
            anchors.centerIn: parent
            width: Math.max(0, Math.min(parent.width / 2 - workspaces.x - workspaces.width - 8,
                right.x - parent.width / 2 - 8) * 2)
            text: barWindow.state.title(barWindow.screen ? barWindow.screen.name : "")
            visible: width > 0
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: barTheme.textMuted
            font.family: barTheme.fontFamily
            font.pixelSize: barTheme.fontSize
            MouseArea { id: titleHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            ToolTip.visible: titleHover.containsMouse && title.truncated
            ToolTip.delay: 500
            ToolTip.text: text
        }
        Row {
            id: right
            objectName: "rightModules"
            anchors.right: parent.right
            anchors.rightMargin: barTheme.padding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Tray { theme: barTheme; panel: barWindow }
            Rectangle {
                width: languageText.implicitWidth + 8
                height: 24
                radius: 5
                color: languageHover.containsMouse ? barTheme.hover : "transparent"
                Text {
                    id: languageText
                    anchors.centerIn: parent
                    text: barWindow.state.language
                    color: barTheme.accent
                    font.family: barTheme.fontFamily
                    font.pixelSize: barTheme.fontSize
                }
                MouseArea {
                    id: languageHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: barWindow.state.canChangeLayout
                    cursorShape: Qt.PointingHandCursor
                    onClicked: barWindow.state.nextLayout()
                }
            }
            Text {
                text: Qt.formatDateTime(barWindow.clock.date, "dd.MM.yyyy  HH:mm")
                height: 24
                verticalAlignment: Text.AlignVCenter
                color: barTheme.text
                font.family: barTheme.fontFamily
                font.pixelSize: barTheme.fontSize
            }
        }
    }
}
```

## bar/BarRuntime.qml

```qml
pragma ComponentBehavior: Bound
import Quickshell

Scope {
    id: root
    required property var desktop
    AppIconResolver { id: iconResolver }
    SystemClock { id: wallClock; precision: SystemClock.Minutes }
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            state: root.desktop
            icons: iconResolver
            clock: wallClock
        }
    }
}
```

## bar/Theme.qml

```qml
import QtQuick
import "../shared" as Shared

Shared.DaevoxTheme {
    readonly property int workspaceAnimationDuration: 150
    readonly property color hover: border
    readonly property int height: 30
    readonly property int margin: 6
    readonly property int radius: 8
    readonly property int padding: 7
    readonly property int fontSize: 12
    readonly property int iconSize: 16
    readonly property int trayIconSize: 14
}
```

## bar/Tray.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Services.SystemTray

Row {
    id: root
    required property var theme
    required property var panel
    spacing: 5
    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: item
            required property SystemTrayItem modelData
            width: 20
            height: 24
            Rectangle {
                anchors.fill: parent
                radius: 5
                color: mouse.containsMouse ? root.theme.hover : "transparent"
            }
            Image {
                anchors.centerIn: parent
                width: root.theme.trayIconSize
                height: width
                source: item.modelData.icon
                sourceSize.width: 28
                sourceSize.height: 28
                fillMode: Image.PreserveAspectFit
            }
            function menu(): void {
                if (!modelData.hasMenu) return;
                const point = item.mapToItem(root.panel.contentItem, 0, height);
                modelData.display(root.panel, Math.round(point.x), Math.round(point.y));
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && item.modelData.onlyMenu)) item.menu();
                    else if (event.button === Qt.MiddleButton) item.modelData.secondaryActivate();
                    else item.modelData.activate();
                }
                onWheel: event => {
                    if (event.angleDelta.y) item.modelData.scroll(event.angleDelta.y, false);
                    if (event.angleDelta.x) item.modelData.scroll(event.angleDelta.x, true);
                    event.accepted = true;
                }
            }
            ToolTip.visible: mouse.containsMouse
            ToolTip.delay: 500
            ToolTip.text: [modelData.tooltipTitle || modelData.title, modelData.tooltipDescription].filter(Boolean).join("\n")
        }
    }
}
```

## bar/WorkspaceStrip.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
    id: root
    required property var hyprland
    required property var theme
    required property var icons
    required property string output
    required property real availableWidth
    readonly property var groups: hyprland.groups(output)
    readonly property real labelsWidth: groups.reduce((sum, w) => sum + metrics.advanceWidth(w.label), 0)
    readonly property real decorationWidth: groups.reduce((sum, w) => sum + 10 + w.windows.length * 19, 0) + Math.max(0, groups.length - 1) * 2
    readonly property real naturalWidth: labelsWidth + decorationWidth
    readonly property real density: decorationWidth ? Math.max(0.01, Math.min(1, (availableWidth - labelsWidth) / decorationWidth)) : 1
    readonly property real emergencyScale: labelsWidth + decorationWidth * density > availableWidth ? Math.max(0, availableWidth / (labelsWidth + decorationWidth * density)) : 1
    implicitWidth: Math.min(naturalWidth, Math.max(0, availableWidth))
    implicitHeight: 24
    function clickPosition(item: var, event: var): var {
        const point = item.mapToItem(null, event.x, event.y);
        return hyprland.globalPosition(output, point);
    }
    FontMetrics { id: metrics; font.family: root.theme.fontFamily; font.pixelSize: root.theme.fontSize }
    Row {
        spacing: 2 * root.density
        scale: root.emergencyScale
        transformOrigin: Item.Left
        Repeater {
            model: ScriptModel { values: root.groups.map(w => w.id) }
            delegate: Rectangle {
                id: group
                required property var modelData
                readonly property var workspace: root.groups.find(w => w.id === modelData) || { active: false, label: "", windows: [] }
                width: contents.implicitWidth + 10 * root.density
                height: 24
                radius: 5
                color: workspaceHover.containsMouse ? root.theme.hover : workspace.active ? root.theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: root.theme.workspaceAnimationDuration; easing.type: Easing.InOutQuad } }
                MouseArea {
                    id: workspaceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => root.hyprland.activateWorkspace(root.output, group.workspace, root.clickPosition(workspaceHover, event))
                    onWheel: wheel => { wheel.accepted = true; }
                }
                Row {
                    id: contents
                    anchors.centerIn: parent
                    spacing: 3 * root.density
                    Text {
                        text: group.workspace.label
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        color: group.workspace.active ? root.theme.accent : root.theme.textMuted
                        Behavior on color { ColorAnimation { duration: root.theme.workspaceAnimationDuration; easing.type: Easing.InOutQuad } }
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSize
                    }
                    Repeater {
                        model: ScriptModel { values: group.workspace.windows.map(w => w.address) }
                        delegate: Item {
                            id: windowIcon
                            required property var modelData
                            readonly property var windowData: group.workspace.windows.find(w => w.address === modelData) || { address: "", title: "" }
                            width: 16 * root.density
                            height: 24
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: hover.containsMouse ? root.theme.hover : "transparent"
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: root.theme.urgent
                                opacity: 0.3
                                visible: root.hyprland.windowUrgent(windowIcon.windowData.address) || !!windowIcon.windowData.urgent
                            }
                            Image {
                                anchors.centerIn: parent
                                width: parent.width
                                height: width
                                source: root.icons.resolve(windowIcon.windowData.class || "", windowIcon.windowData.initialClass || "")
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(8, parent.width)
                                height: 2
                                radius: 1
                                color: root.theme.accent
                                visible: root.hyprland.windowActive(windowIcon.windowData.address)
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => root.hyprland.activateWindow(windowIcon.windowData.address, root.clickPosition(hover, event))
                                onWheel: wheel => { wheel.accepted = true; }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

## launcher/AppModel.qml

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string query: ""
    property string error: ""
    readonly property bool launching: launchProcess.running
    signal launched()

    // Reactive to the system catalogue, never rebuilt just because the window opens.
    readonly property var catalogue: DesktopEntries.applications.values.map(entry => ({
        entry: entry,
        name: normalize(entry.name),
        fields: [entry.genericName, entry.comment, entry.keywords.join(" "),
                 entry.command.join(" ")].map(value => normalize(value))
    }))
    readonly property var results: rank(catalogue, query)

    function normalize(value: string): string {
        return value.toLowerCase().replace(/ё/g, "е").trim();
    }

    // A single scoring seam for a future fuzzy matcher. All query words must match.
    function score(record: var, tokens: var): int {
        let total = 0;
        for (const token of tokens) {
            let best = -1;
            if (record.name === token) best = 100;
            else if (record.name.startsWith(token)) best = 80;
            else if (record.name.includes(token)) best = 60;
            for (let i = 0; i < record.fields.length; ++i) {
                if (record.fields[i].includes(token))
                    best = Math.max(best, 40 - i * 5);
            }
            if (best < 0) return -1;
            total += best;
        }
        return total;
    }

    function rank(records: var, text: string): var {
        const normalized = normalize(text);
        const tokens = normalized ? normalized.split(/\s+/) : [];
        return records.map(record => ({ record: record, score: score(record, tokens) }))
            .filter(hit => hit.score >= 0)
            .sort((a, b) => b.score - a.score
                || a.record.name.localeCompare(b.record.name)
                || a.record.entry.id.localeCompare(b.record.entry.id))
            .map(hit => hit.record.entry);
    }

    function launch(index: int): void {
        if (launching || index < 0 || index >= results.length) return;
        const entry = results[index];
        // Quickshell IDs omit the final .desktop suffix (including nested XDG IDs).
        const desktopId = entry.id + ".desktop";
        error = "";
        // 0.3.1 execute() ignores Terminal and field codes. Let UWSM launch the entry.
        launchProcess.command = ["uwsm", "app", "-t", "service", "--", desktopId];
        launchProcess.running = true;
    }

    Process {
        id: launchProcess
        stderr: SplitParser {
            onRead: data => {
                root.error = data.trim();
                console.warn("launcher:", data);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                root.error = "";
                root.launched();
            } else if (!root.error) {
                root.error = "Launch failed (" + exitCode + "). Check the launcher log.";
            }
        }
    }
}
```

## launcher/Launcher.qml

```qml
pragma ComponentBehavior: Bound
import "../shared" as Shared

import QtQuick
import "audio"
import "../notifications" as Notifications
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    required property var desktop
    property string mode: "apps"
    property var notifications: null
    readonly property real panelTop: modes.y + modes.height + 4
    property bool opened: false
    property real reveal: 0
    property real modeReveal: 1
    visible: opened || reveal > 0
    NumberAnimation {
        id: revealAnimation
        target: root; property: "reveal"
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: modeAnimation
        target: root; property: "modeReveal"
        from: 0; to: 1
        duration: theme.motionNormal
        easing.type: Easing.OutCubic
    }
    color: theme.transparent
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.min(theme.windowWidth, screen.width - 2 * theme.spacing)
    implicitHeight: Math.min(panelTop + theme.searchHeight + theme.rowHeight * theme.visibleRows
        + theme.footerHeight + 2.5 * theme.spacing, screen.height - 2 * theme.spacing)
    WlrLayershell.namespace: "daevox-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Keep the layer focus stable through exit so reopening cannot clear a new grab.
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        item: panel
        Region { x: modes.x - 2; y: modes.y; width: modes.width + 4; height: modes.height + 4 }
    }

    Theme { id: theme }
    AudioModel { id: audio }
    AudioRouter { id: router; audio: audio }
    AppModel {
        id: apps
        query: search.text
        onResultsChanged: root.resetSelection()
        onLaunched: root.close()
    }
    Connections {
        target: root.notifications
        function onBlockedChanged() { if (root.notifications.blocked) root.closeImmediately(); }
    }
    HyprlandFocusGrab {
        objectName: "launcherFocusGrab"
        windows: [root]
        active: root.opened
        onCleared: root.close()
    }

    function open(): void { openMode("apps"); }

    function openMode(value: string): void {
        if (notifications && notifications.blocked) return;
        const target = desktop.screenFor(Quickshell.screens);
        if (!target) return;
        screen = target;
        search.text = "";
        const nextMode = ["apps", "audio", "notifications"].includes(value) ? value : "apps";
        if (opened && mode !== nextMode) modeAnimation.restart();
        mode = nextMode;
        if (notificationPane.item) notificationPane.item.cancelReply();
        if (mode === "audio") router.check();
        audioPane.reset();
        apps.error = "";
        resetSelection();
        opened = true;
        animateReveal(1);
        search.forceActiveFocus();
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!Quickshell.screens.includes(root.screen)) {
                root.closeImmediately();
                root.screen = root.desktop.screenFor(Quickshell.screens);
            }
        }
    }

    function animateReveal(target: real): void {
        revealAnimation.stop();
        revealAnimation.to = target;
        revealAnimation.duration = target === 1 ? theme.motionEnter : theme.motionExit;
        revealAnimation.start();
    }

    function close(): void {
        if (!opened) return;
        if (notificationPane.item) notificationPane.item.cancelReply();
        opened = false;
        animateReveal(0);
    }

    // Lock and screen removal must hide content without an exit transition.
    function closeImmediately(): void {
        close();
        revealAnimation.stop();
        reveal = 0;
    }

    function toggle(): void {
        if (opened) close();
        else open();
    }

    function status(): string {
        return JSON.stringify({ visible: visible, applications: apps.catalogue.length,
            mode: mode, audioApplications: audio.groups.length, audioReady: audio.ready,
            routingAvailable: router.available, routingMessage: router.message,
            results: apps.results.length, selected: list.currentIndex,
            notifications: notifications ? {ready: notifications.ready, total: notifications.records.filter(row => !row.transient).length,
                unread: notifications.records.filter(row => !row.transient && row.unread).length,
                dnd: notifications.dnd, lock: notifications.lockState} : null,
            query: search.text, inputFocused: search.activeFocus,
            launching: apps.launching, error: apps.error });
    }

    function resetSelection(): void {
        list.currentIndex = apps.results.length ? 0 : -1;
        list.positionViewAtBeginning();
    }

    function moveSelection(delta: int): void {
        if (!list.count) return;
        list.currentIndex = (list.currentIndex + delta + list.count) % list.count;
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function handleKey(event: var, editing: bool): void {
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        if (alt && (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3)) {
            switchMode(event.key === Qt.Key_1 ? "apps" : event.key === Qt.Key_2 ? "audio" : "notifications");
            event.accepted = true;
            return;
        }
        if (mode === "audio" && audioPane.pickerOpen) {
            audioPane.pickerKey(event);
            return;
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        // Qt Wayland reports XKB keycodes: evdev KEY_J/K (36/37) + 8.
        const next = ctrl && (event.nativeScanCode === 44
            || (event.nativeScanCode === 0 && event.key === Qt.Key_J));
        const previous = ctrl && (event.nativeScanCode === 45
            || (event.nativeScanCode === 0 && event.key === Qt.Key_K));
        if (event.key === Qt.Key_Escape) {
            if (mode === "notifications" && notificationPane.item && notificationPane.item.cancelReply()) {}
            else if (search.text) search.text = "";
            else close();
        }
        else if (mode === "notifications") {
            if (!notificationPane.item) return;
            if (event.key === Qt.Key_Down) notificationPane.item.moveSelection(1);
            else if (event.key === Qt.Key_Up) notificationPane.item.moveSelection(-1);
            else if (event.key === Qt.Key_Backspace && !editing) notificationPane.item.removeSelected();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat) notificationPane.item.activate();
            } else return;
        }
        else if (mode === "audio") {
            if (event.key === Qt.Key_Down) audioPane.moveSelection(1);
            else if (event.key === Qt.Key_Up) audioPane.moveSelection(-1);
            else if (!ctrl && event.key === Qt.Key_Left) audioPane.changeVolume(-0.05);
            else if (!ctrl && event.key === Qt.Key_Right) audioPane.changeVolume(0.05);
            else if (alt && event.key === Qt.Key_M) audioPane.toggleMute();
            else if (alt && event.key === Qt.Key_O) audioPane.openPicker(audioPane.selectedGroup);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat && audioPane.selectedRow && !audioPane.selectedRow.node)
                    audioPane.expand(audioPane.selectedGroup);
            } else return;
        }
        else if (event.key === Qt.Key_Down || next) moveSelection(1);
        else if (event.key === Qt.Key_Up || previous) moveSelection(-1);
        else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && shift)) moveSelection(-1);
        else if (event.key === Qt.Key_Tab) moveSelection(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) apps.launch(list.currentIndex);
        } else return;
        event.accepted = true;
    }

    function switchMode(value: string): void {
        if (value === mode) return;
        modeAnimation.restart();
        if (notificationPane.item) notificationPane.item.cancelReply();
        mode = value;
        search.text = "";
        audioPane.reset();
        resetSelection();
        search.forceActiveFocus();
        if (value === "audio") router.check();
    }

    Item {
        id: presentation
        anchors.fill: parent
        enabled: root.opened
        opacity: root.reveal
        transform: Translate { y: -8 * (1 - root.reveal) }

        Row {
            id: modes
            anchors.top: parent.top
            anchors.topMargin: theme.spacing
            anchors.left: panel.left
            spacing: 8
            Repeater {
                model: [{ mode: "apps", icon: "apps", label: "Приложения" },
                    { mode: "audio", icon: "volume", label: "Звук" },
                    { mode: "notifications", icon: "bell", label: "Уведомления" }]
                delegate: Shared.IconButton {
                    id: modeButton
                    shadowEnabled: true
                    required property var modelData
                    objectName: "mode-" + modelData.mode
                    theme: theme
                    iconName: modelData.icon
                    label: modelData.label
                    active: root.mode === modelData.mode
                    onClicked: root.switchMode(modelData.mode)
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => root.handleKey(event, false)
                }
            }
        }

        // The shadow moves with the launcher surface.
        Rectangle {
            anchors.fill: panel
            anchors.margins: -3
            anchors.topMargin: 0
            anchors.bottomMargin: -6
            radius: theme.radius + 3
            color: theme.shadow
        }
        Rectangle {
            id: panel
            objectName: "launcherPanel"
            anchors.fill: parent
            anchors.margins: theme.spacing
            anchors.topMargin: root.panelTop
            color: theme.background
            radius: theme.radius
            border.color: theme.border

            TextField {
                id: search
                objectName: "launcherSearch"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: theme.spacing
                height: theme.searchHeight - 2 * theme.spacing
                padding: 0
                font.family: theme.fontFamily
                font.pixelSize: theme.searchFontSize
                color: theme.text
                placeholderText: root.mode === "notifications" ? "Поиск уведомлений…" : root.mode === "audio" ? "Поиск звуковых приложений…" : "Search applications…"
                placeholderTextColor: theme.textMuted
                selectionColor: theme.accent
                selectedTextColor: theme.background
                background: Item {}
                focus: true
                selectByMouse: true
                activeFocusOnTab: root.mode !== "apps"
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.handleKey(event, true)
            }
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: theme.searchHeight
                width: parent.width
                height: 1
                color: theme.border
            }
            ListView {
                id: list
                visible: root.mode === "apps"
                opacity: root.modeReveal
                transform: Translate { y: 4 * (1 - root.modeReveal) }
                anchors.top: parent.top
                anchors.topMargin: theme.searchHeight + theme.spacing / 2
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: theme.spacing / 2
                anchors.rightMargin: theme.spacing / 2
                clip: true
                model: apps.results
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: theme.motionQuick
                highlightResizeDuration: 0
                highlight: Rectangle {
                    radius: theme.radius / 2
                    color: theme.surface
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: theme.rowHeight
                    radius: theme.radius / 2
                    color: rowMouse.containsMouse && !ListView.isCurrentItem ? theme.surface : theme.transparent
                    opacity: rowMouse.pressed ? 0.8 : 1
                    Behavior on color { ColorAnimation { duration: theme.motionQuick } }
                    Behavior on opacity { NumberAnimation { duration: theme.motionQuick } }
                    Image {
                        id: icon
                        anchors.left: parent.left
                        anchors.leftMargin: theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        width: theme.iconSize
                        height: theme.iconSize
                        sourceSize.width: width * root.devicePixelRatio
                        sourceSize.height: height * root.devicePixelRatio
                        source: Quickshell.iconPath(row.modelData.icon, true)
                            || Quickshell.iconPath("application-x-executable", true)
                        fillMode: Image.PreserveAspectFit
                        Text {
                            anchors.centerIn: parent
                            visible: icon.status !== Image.Ready
                            text: row.modelData.name.charAt(0).toUpperCase()
                            color: theme.accent
                            font.family: theme.fontFamily
                            font.pixelSize: theme.searchFontSize
                        }
                    }
                    Column {
                        anchors.left: icon.right
                        anchors.leftMargin: theme.spacing
                        anchors.right: parent.right
                        anchors.rightMargin: theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: row.modelData.name
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSize
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: row.modelData.genericName || row.modelData.comment
                            visible: text.length > 0
                            color: theme.textMuted
                            font.family: theme.fontFamily
                            font.pixelSize: theme.smallFontSize
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: rowMouse
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            list.currentIndex = row.index;
                            apps.launch(row.index);
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: search.text.trim() ? "No matching applications" : "No applications found"
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontSize
                }
            }
            AudioPane {
                id: audioPane
                objectName: "audioPane"
                visible: root.mode === "audio"
                opacity: root.modeReveal
                transform: Translate { y: 4 * (1 - root.modeReveal) }
                anchors.top: parent.top
                anchors.topMargin: theme.searchHeight + theme.spacing / 2
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: theme.spacing / 2
                anchors.rightMargin: theme.spacing / 2
                theme: theme
                audio: audio
                router: router
                query: search.text
                keyHandler: event => root.handleKey(event, false)
            }
            Loader {
                id: notificationPane
                active: root.notifications !== null
                visible: root.mode === "notifications"
                opacity: root.modeReveal
                transform: Translate { y: 4 * (1 - root.modeReveal) }
                anchors.top: parent.top; anchors.topMargin: theme.searchHeight + 8
                anchors.bottom: footer.top; anchors.bottomMargin: 8
                anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
                sourceComponent: Notifications.NotificationPane {
                    theme: theme; notifications: root.notifications; query: search.text
                    visible: root.mode === "notifications"
                    keyHandler: event => root.handleKey(event, false)
                    onSearchFocusRequested: search.forceActiveFocus()
                }
            }
            Text {
                anchors.centerIn: parent
                visible: root.mode === "notifications" && !root.notifications
                text: "Уведомления ещё не включены"
                color: theme.textMuted; font.family: theme.fontFamily; font.pixelSize: theme.fontSize
            }
            Item {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: theme.spacing
                height: theme.footerHeight - theme.spacing
                Text {
                    anchors.left: parent.left
                    anchors.right: layoutIndicator.left
                    anchors.rightMargin: theme.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "notifications" ? ((root.notifications ? root.notifications.error : "") || "↑ ↓ Выбор · Enter Открыть · Backspace Удалить")
                        : root.mode === "audio" ? (router.unavailableReason || "← → Громкость · Alt+M Mute · Alt+O Выход · Enter Потоки")
                        : apps.error || (apps.launching ? "Launching…" : "↑ ↓  Navigate     Enter: Launch     Esc: Close")
                    color: apps.error ? theme.accent : theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.smallFontSize
                    elide: Text.ElideRight
                }
                Text {
                    id: layoutIndicator
                    objectName: "keyboardLayoutIndicator"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width / 4)
                    text: root.desktop.language
                    color: theme.accent
                    font.family: theme.fontFamily
                    font.pixelSize: theme.smallFontSize
                    elide: Text.ElideRight
                    Accessible.name: "Текущая раскладка: " + text
                }
            }
        }
    }
}
```

## launcher/Theme.qml

```qml
import "../shared" as Shared

Shared.DaevoxTheme {
    readonly property int radius: 12
    readonly property int spacing: 10
    readonly property int fontSize: 13
    readonly property int smallFontSize: 11
    readonly property int searchFontSize: 16
    readonly property int windowWidth: 560
    readonly property int searchHeight: 48
    readonly property int rowHeight: 48
    readonly property int visibleRows: 6
    readonly property int footerHeight: 28
    readonly property int iconSize: 28
}
```

## launcher/audio/AudioControls.qml

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    required property var theme
    required property var keyHandler
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property real volume: 0
    property string muteState: "audible"
    property bool selected: false
    property bool expandable: false
    property bool expanded: false
    property bool available: true
    signal selectedByUser()
    signal expandClicked()
    signal volumeEdited(real value)
    signal muteClicked()
    implicitHeight: subtitle ? 54 : 36
    radius: theme.radius / 2
    color: selected ? theme.surface : theme.transparent
    border.color: activeFocus ? theme.accent : theme.transparent

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Image {
                id: appIcon
                visible: root.icon !== ""
                Layout.preferredWidth: visible ? 24 : 0
                Layout.preferredHeight: 24
                source: root.icon ? Quickshell.iconPath(root.icon, true) : ""
                fillMode: Image.PreserveAspectFit
                Text {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: root.title.charAt(0)
                    color: root.theme.accent
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize
                }
            }
            Button {
                id: titleButton
                HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.preferredHeight: 28
                text: (root.expandable ? (root.expanded ? "▾ " : "▸ ") : "") + root.title
                flat: true
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fontSize
                palette.buttonText: root.theme.text
                contentItem: Text {
                    text: titleButton.text
                    color: root.theme.text
                    font: titleButton.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    root.selectedByUser();
                    if (root.expandable) root.expandClicked();
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Accessible.name: root.title
            }
            Slider {
                id: slider
                HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                objectName: "volumeSlider"
                Layout.preferredWidth: 150
                Layout.preferredHeight: 28
                enabled: root.available
                from: 0
                to: 1
                value: Math.max(0, Math.min(1, root.volume))
                stepSize: 0
                palette.highlight: root.theme.accent
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 5
                    radius: 3
                    color: root.theme.border
                    Rectangle {
                        width: slider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: root.available ? root.theme.accent : root.theme.textMuted
                    }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    implicitWidth: 14
                    implicitHeight: 14
                    radius: 7
                    color: root.available ? root.theme.accent : root.theme.textMuted
                    border.width: slider.activeFocus ? 2 : 0
                    border.color: root.theme.text
                }
                onMoved: root.volumeEdited(value)
                onPressedChanged: if (pressed) root.selectedByUser()
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                Accessible.name: root.title + ": громкость"
            }
            Text {
                Layout.preferredWidth: 46
                text: root.available ? Math.round(root.volume * 100) + "%" : "—"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                horizontalAlignment: Text.AlignRight
            }
            Button {
                id: muteButton
                HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                Layout.preferredWidth: 42
                Layout.preferredHeight: 28
                text: root.muteState === "muted" ? "×" : root.muteState === "mixed" ? "◐" : "♪"
                enabled: root.available
                palette.button: root.theme.background
                palette.buttonText: root.theme.accent
                background: Rectangle {
                    radius: 7
                    color: muteButton.down ? root.theme.surface : root.theme.background
                    border.color: muteButton.activeFocus ? root.theme.accent : root.theme.border
                }
                onClicked: { root.selectedByUser(); root.muteClicked(); }
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                Accessible.name: root.title + (root.muteState === "muted" ? ": включить звук" : ": выключить звук")
                ToolTip.visible: hovered
                ToolTip.text: root.muteState === "mixed" ? "Частично заглушено" : root.muteState === "muted" ? "Звук выключен" : "Выключить звук"
            }
        }
        Text {
            visible: root.subtitle !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 8
            text: root.subtitle
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallFontSize
            elide: Text.ElideRight
        }
    }
}
```

## launcher/audio/AudioMath.js

```javascript
// Pure policy; values are Quickshell's visual volumes (1 == 100%).
function clamp(value) { return Math.max(0, Math.min(1, value)); }

function identity(properties, runtimeKey) {
    if (properties["application.id"]) return "app:" + properties["application.id"];
    if (properties["client.id"] !== undefined && properties["client.id"] !== "")
        return "client:" + properties["client.id"];
    return "node:" + runtimeKey;
}

function maximum(values) { return values.length ? Math.max.apply(null, values) : 0; }

function scaled(values, target, remembered) {
    target = clamp(target);
    const max = maximum(values);
    const ratios = max > 0 ? values.map(value => value / max) : remembered;
    return {
        values: ratios && ratios.length === values.length
            ? ratios.map(ratio => ratio * target) : values.map(() => target),
        ratios: ratios
    };
}

function muteState(values) {
    if (values.length && values.every(value => value)) return "muted";
    return values.some(value => value) ? "mixed" : "audible";
}
```

## launcher/audio/AudioModel.qml

```qml
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "AudioMath.js" as AudioMath

Scope {
    id: root
    readonly property bool ready: Pipewire.ready
    readonly property var nodes: Pipewire.nodes.values.filter(node => node.audio !== null)
    readonly property var streams: nodes.filter(node => node.ready && node.type === PwNodeType.AudioOutStream)
    readonly property var outputs: nodes.filter(node => node.ready && node.type === PwNodeType.AudioSink)
    readonly property var defaultOutput: Pipewire.defaultAudioSink
    readonly property var groups: buildGroups()
    // A group's state stays Unlinked until the group itself is bound in 0.3.1.
    // Binding individual links does not bind their group.
    PwObjectTracker { objects: root.nodes.concat(Array.from(Pipewire.linkGroups.values)) }
    property var proportions: ({})
    property var channelProportions: ({})
    onGroupsChanged: {
        const next = {};
        for (const group of groups) {
            const saved = proportions[group.key];
            if (saved && saved.members === membership(group.nodes)) next[group.key] = saved;
        }
        proportions = next;
        const channels = {};
        for (const node of nodes) {
            const key = nodeKey(node);
            if (channelProportions[key]) channels[key] = channelProportions[key];
        }
        channelProportions = channels;
    }

    function nodeKey(node: var): string {
        return String(node.properties["object.serial"] || node.id);
    }
    function membership(members: var): string {
        return members.map(node => nodeKey(node)).sort().join(",");
    }
    function usable(node: var): bool {
        return ready && node && nodes.includes(node) && node.ready && node.audio !== null;
    }
    function setDefaultOutput(node: var): void {
        if (!usable(node) || !outputs.includes(node)) return;
        Pipewire.preferredDefaultAudioSink = node;
    }
    function label(node: var): string {
        return node ? node.description || node.nickname || node.name || "Неизвестный выход" : "Нет выхода";
    }
    function streamLabel(node: var): string {
        return node.properties["media.name"] || node.properties["media.title"] || node.description || node.name || "Поток";
    }
    function buildGroups(): var {
        const result = [];
        for (const node of streams) {
            const props = node.properties;
            const key = AudioMath.identity(props, nodeKey(node));
            let group = result.find(item => item.key === key);
            if (!group) {
                const id = props["application.id"] || "";
                const desktop = DesktopEntries.applications.values.find(entry => entry.id === id || entry.id + ".desktop" === id);
                group = { key: key, name: desktop ? desktop.name : props["application.name"] || "Неизвестное приложение",
                    icon: desktop ? desktop.icon : props["application.icon-name"] || "application-x-executable", nodes: [] };
                result.push(group);
            }
            group.nodes.push(node);
        }
        return result.sort((a, b) => a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
    }
    function volume(members: var): real {
        return AudioMath.maximum(members.filter(node => usable(node)).map(node => node.audio.volume));
    }
    function muteState(members: var): string {
        return AudioMath.muteState(members.filter(node => usable(node)).map(node => node.audio.muted));
    }
    function setNodeVolume(node: var, value: real): void {
        if (!usable(node)) return;
        // Quickshell already converts PipeWire's linear scale. Preserve channel
        // balance through zero too; its volume setter only preserves nonzero ratios.
        const key = nodeKey(node);
        const channels = Array.from(node.audio.channels);
        const signature = channels.join(",");
        const volumes = Array.from(node.audio.volumes);
        const average = node.audio.volume;
        if (average > 0) channelProportions[key] = { signature: signature, ratios: volumes.map(v => v / average) };
        const saved = channelProportions[key];
        if (average === 0 && saved && saved.signature === signature)
            node.audio.volumes = saved.ratios.map(ratio => ratio * AudioMath.clamp(value));
        else node.audio.volume = AudioMath.clamp(value);
    }
    function setVolume(group: var, value: real): void {
        if (!group || !group.nodes.every(node => usable(node))) return;
        const saved = proportions[group.key];
        const members = membership(group.nodes);
        const result = AudioMath.scaled(group.nodes.map(node => node.audio.volume), value,
            saved && saved.members === members ? saved.ratios : null);
        if (result.ratios) proportions[group.key] = { members: members, ratios: result.ratios };
        group.nodes.forEach((node, index) => setNodeVolume(node, result.values[index]));
    }
    function toggleMute(members: var): void {
        const live = members.filter(node => usable(node));
        const mute = muteState(live) !== "muted";
        for (const node of live) node.audio.muted = mute;
    }
    function targets(node: var): var {
        return Pipewire.linkGroups.values.filter(link => link.source === node
            && (link.state === PwLinkState.Active || link.state === PwLinkState.Paused)
            && outputs.includes(link.target)).map(link => link.target);
    }
    function outputLabel(members: var): string {
        const routes = members.map(node => targets(node));
        if (routes.every(route => route.length === 0)) return "Нет выхода";
        const first = routes.length && routes[0][0];
        if (first && routes.every(route => route.length === 1 && route[0] === first)) return label(first);
        return "Разные выходы";
    }
}
```

## launcher/audio/AudioPane.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var theme
    required property AudioModel audio
    required property AudioRouter router
    required property var keyHandler
    property string query: ""
    property string selectedKey: "system"
    property var expanded: ({})
    property string pickerGroupKey: ""
    readonly property bool pickerForSystem: pickerGroupKey === ""
    readonly property bool pickerOpen: picker.visible
    readonly property var rows: buildRows()
    readonly property var selectedRow: rows.find(row => row.key === selectedKey)
    readonly property var selectedGroup: selectedRow ? selectedRow.group : null
    readonly property var pickerGroup: audio.groups.find(group => group.key === pickerGroupKey)
    onRowsChanged: {
        if (selectedKey !== "system" && !rows.some(row => row.key === selectedKey)) selectedKey = "system";
        if (picker.visible && !pickerForSystem && !pickerGroup) picker.close();
    }

    function buildRows(): var {
        const tokens = query.toLocaleLowerCase().replace(/ё/g, "е").trim().split(/\s+/).filter(Boolean);
        const result = [];
        for (const group of audio.groups) {
            const name = (group.name + " " + group.nodes.map(node => audio.streamLabel(node)).join(" "))
                .toLocaleLowerCase().replace(/ё/g, "е");
            if (!tokens.every(token => name.includes(token))) continue;
            result.push({ key: group.key, group: group, node: null });
            if (expanded[group.key]) {
                for (const node of group.nodes) result.push({ key: group.key + "/" + audio.nodeKey(node), group: group, node: node });
            }
        }
        return result;
    }
    function reset(): void {
        picker.close();
        selectedKey = "system";
        expanded = {};
        list.positionViewAtBeginning();
    }
    function moveSelection(delta: int): void {
        const index = rows.findIndex(row => row.key === selectedKey);
        const next = (index + 1 + delta + rows.length + 1) % (rows.length + 1) - 1;
        selectedKey = next < 0 ? "system" : rows[next].key;
        if (next >= 0) list.positionViewAtIndex(next, ListView.Contain);
    }
    function expand(group: var): void {
        if (!group) return;
        const next = Object.assign({}, expanded);
        next[group.key] = !next[group.key];
        expanded = next;
    }
    function changeVolume(delta: real): void {
        if (selectedKey === "system") {
            if (audio.usable(audio.defaultOutput)) audio.setNodeVolume(audio.defaultOutput, audio.defaultOutput.audio.volume + delta);
        } else if (selectedRow) {
            if (selectedRow.node) audio.setNodeVolume(selectedRow.node, selectedRow.node.audio.volume + delta);
            else audio.setVolume(selectedRow.group, audio.volume(selectedRow.group.nodes) + delta);
        }
    }
    function toggleMute(): void {
        if (selectedKey === "system") audio.toggleMute([audio.defaultOutput]);
        else if (selectedRow) audio.toggleMute(selectedRow.node ? [selectedRow.node] : selectedRow.group.nodes);
    }
    function openPicker(group: var): void {
        if (!audio.ready || !audio.outputs.length) return;
        if (group && (!router.available || router.pending)) return;
        pickerGroupKey = group ? group.key : "";
        const current = group ? audio.targets(group.nodes[0])[0] : audio.defaultOutput;
        devices.currentIndex = Math.max(0, audio.outputs.indexOf(current));
        picker.open();
        devices.forceActiveFocus();
    }
    function pickerKey(event: var): void {
        if (event.key === Qt.Key_Escape) picker.close();
        else if ([Qt.Key_Up, Qt.Key_Left, Qt.Key_Down, Qt.Key_Right].includes(event.key)) {
            const delta = event.key === Qt.Key_Up || event.key === Qt.Key_Left ? -1 : 1;
            if (devices.count) devices.currentIndex = (devices.currentIndex + delta + devices.count) % devices.count;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) chooseOutput(devices.currentIndex);
        else return;
        event.accepted = true;
    }
    function chooseOutput(index: int): void {
        if (index < 0 || index >= audio.outputs.length) return;
        if (pickerForSystem) audio.setDefaultOutput(audio.outputs[index]);
        else if (pickerGroup) router.move(pickerGroup, audio.outputs[index]);
        else return;
        picker.close();
    }

    AudioControls {
        id: system
        anchors.top: parent.top
        width: parent.width
        theme: root.theme
        keyHandler: root.keyHandler
        title: "Системная громкость"
        subtitle: "По умолчанию · " + root.audio.label(root.audio.defaultOutput)
        selected: root.selectedKey === "system"
        available: root.audio.usable(root.audio.defaultOutput)
        volume: available ? root.audio.defaultOutput.audio.volume : 0
        muteState: root.audio.muteState([root.audio.defaultOutput])
        onSelectedByUser: root.selectedKey = "system"
        onVolumeEdited: value => root.audio.setNodeVolume(root.audio.defaultOutput, value)
        onMuteClicked: root.audio.toggleMute([root.audio.defaultOutput])
    }
    Button {
        id: systemOutputButton
        HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
        objectName: "systemOutputButton"
        anchors.top: system.bottom
        width: parent.width
        height: 24
        enabled: root.audio.ready && root.audio.outputs.length > 0
        text: "Устройство по умолчанию ▾"
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallFontSize
        contentItem: Text {
            text: systemOutputButton.text
            font: systemOutputButton.font
            color: systemOutputButton.enabled ? root.theme.textMuted : root.theme.border
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
        }
        background: Rectangle {
            radius: root.theme.radius / 2
            color: systemOutputButton.down || systemOutputButton.hovered ? root.theme.surface : root.theme.transparent
            border.color: systemOutputButton.activeFocus ? root.theme.accent : root.theme.transparent
        }
        onClicked: { root.selectedKey = "system"; root.openPicker(null); }
        onActiveFocusChanged: if (activeFocus) root.selectedKey = "system"
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => root.keyHandler(event)
        Accessible.name: "Устройство вывода по умолчанию"
    }
    ListView {
        id: list
        anchors.top: systemOutputButton.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        spacing: 2
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        delegate: Column {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width
            AudioControls {
                width: parent.width - (row.modelData.node ? 18 : 0)
                x: row.modelData.node ? 18 : 0
                theme: root.theme
                keyHandler: root.keyHandler
                title: row.modelData.node ? root.audio.streamLabel(row.modelData.node) : row.modelData.group.name
                icon: row.modelData.node ? "" : row.modelData.group.icon
                selected: root.selectedKey === row.modelData.key
                expandable: !row.modelData.node
                expanded: !!root.expanded[row.modelData.group.key]
                volume: root.audio.volume(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
                muteState: root.audio.muteState(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
                subtitle: muteState === "mixed" ? "Частично заглушено" : row.modelData.node ? root.audio.outputLabel([row.modelData.node]) : ""
                onSelectedByUser: root.selectedKey = row.modelData.key
                onExpandClicked: root.expand(row.modelData.group)
                onVolumeEdited: value => {
                    if (row.modelData.node) root.audio.setNodeVolume(row.modelData.node, value);
                    else root.audio.setVolume(row.modelData.group, value);
                }
                onMuteClicked: root.audio.toggleMute(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
            }
            Button {
                id: outputButton
                HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                width: parent.width
                height: visible ? 24 : 0
                visible: !row.modelData.node
                enabled: root.router.available && !root.router.pending && root.audio.outputs.length > 0
                flat: true
                text: root.audio.outputLabel(row.modelData.group.nodes) + " ▾"
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                palette.buttonText: root.theme.textMuted
                contentItem: Text {
                    text: outputButton.text
                    font: outputButton.font
                    color: outputButton.enabled ? root.theme.textMuted : root.theme.border
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 34
                }
                onClicked: { root.selectedKey = row.modelData.key; root.openPicker(row.modelData.group); }
                onActiveFocusChanged: if (activeFocus) root.selectedKey = row.modelData.key
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                ToolTip.visible: hovered
                ToolTip.text: root.router.unavailableReason || text
                Accessible.name: row.modelData.group.name + ": устройство вывода"
            }
            Text {
                width: parent.width
                height: visible ? implicitHeight + 6 : 0
                visible: !row.modelData.node && root.router.groupKey === row.modelData.group.key && root.router.message !== ""
                text: root.router.message
                color: root.theme.accent
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                wrapMode: Text.Wrap
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: list.count === 0
            text: !root.audio.ready ? "PipeWire недоступен" : root.query.trim() ? "Ничего не найдено" : "Нет звуковых приложений"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
        }
    }
    Popup {
        id: picker
        objectName: "outputPicker"
        anchors.centerIn: parent
        width: Math.min(420, root.width - 20)
        height: Math.min(240, root.height)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: root.theme.shadow }
        background: Rectangle { color: root.theme.background; radius: 10; border.color: root.theme.accent }
        contentItem: ListView {
            id: devices
            clip: true
            model: root.audio.outputs
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => root.keyHandler(event)
            onCountChanged: currentIndex = Math.min(Math.max(0, currentIndex), count - 1)
            delegate: ItemDelegate {
                id: device
                HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                required property var modelData
                required property int index
                width: ListView.view.width
                text: root.audio.label(modelData)
                highlighted: devices.currentIndex === index
                background: Rectangle {
                    color: device.highlighted || device.hovered ? root.theme.surface : root.theme.background
                    radius: root.theme.radius / 2
                }
                contentItem: Text {
                    text: device.text
                    font: device.font
                    color: device.highlighted ? root.theme.accent : root.theme.text
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                font.family: root.theme.fontFamily
                onClicked: root.chooseOutput(index)
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
            }
            Text {
                anchors.centerIn: parent
                visible: devices.count === 0
                text: "Нет доступных выходов"
                color: root.theme.textMuted
            }
        }
    }
}
```

## launcher/audio/AudioRouter.qml

```qml
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
```

## notifications/NotificationAvatar.qml

```qml
import QtQuick
import Quickshell

Rectangle {
    id: root
    required property var notification
    required property var theme
    // image-data/image-path describe the notification (e.g. a sender avatar),
    // not an attachment in its body. Keep the existing archive field compatible.
    readonly property string avatarSource: notification.image || ""
    readonly property string appSource: !notification.icon ? ""
        : notification.icon.startsWith("/") || notification.icon.startsWith("file:")
            ? notification.icon : Quickshell.iconPath(notification.icon, true)
    implicitWidth: 30
    implicitHeight: 30
    radius: 7
    color: theme.surface
    Image {
        id: avatar
        objectName: "notificationAvatarImage"
        anchors.fill: parent
        anchors.margins: 2
        source: root.avatarSource
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }
    Image {
        id: appIcon
        anchors.fill: parent
        anchors.margins: 3
        source: avatar.status === Image.Ready ? "" : root.appSource
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }
    Text {
        anchors.centerIn: parent
        visible: avatar.status !== Image.Ready && appIcon.status !== Image.Ready
        text: (root.notification.app || "?").charAt(0).toUpperCase()
        color: root.theme.accent
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
    }
    Accessible.name: "Аватар уведомления: " + notification.app
}
```

## notifications/NotificationButton.qml

```qml
import QtQuick
import QtQuick.Controls

Button {
    id: root
    HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
    required property var theme
    font.family: theme.fontFamily
    font.pixelSize: theme.smallFontSize
    implicitHeight: 28
    leftPadding: 8
    rightPadding: 8
    palette.buttonText: theme.text
    background: Rectangle {
        radius: 6
        color: root.hovered || root.down ? root.theme.border : root.theme.surface
        border.color: root.activeFocus ? root.theme.accent : root.theme.border
    }
}
```

## notifications/NotificationCard.qml

```qml
pragma ComponentBehavior: Bound
import "../shared" as Shared
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    objectName: (popup ? "notificationPopup-" : "notificationCard-") + notification.key
    required property var notification
    required property var notifications
    required property var theme
    property bool selected: false
    property bool popup: false
    property bool expanded: false
    property bool replyOpen: false
    property var keyHandler: null
    signal replyRequested(string key)
    signal replyCancelled()
    signal selectedByMouse()
    implicitHeight: content.implicitHeight + 18
    radius: 10
    color: selected || cardHover.hovered ? theme.surface : theme.background
    border.color: selected || cardHover.hovered ? theme.accent : notification.urgency === 2 ? theme.urgent : theme.border
    Accessible.role: Accessible.Grouping
    Accessible.name: notification.app + ": " + notification.summary
    HoverHandler { id: cardHover; onHoveredChanged: root.notifications.setHovered(root.notification.key, hovered) }
    Component.onDestruction: {
        notifications.setHovered(notification.key, false);
        notifications.setReplying(notification.key, false);
    }
    function activate(): void {
        if (!notifications.invoke(notification.key, "default")) expanded = !expanded;
    }
    onReplyOpenChanged: {
        notifications.setReplying(notification.key, replyOpen);
        if (replyOpen) Qt.callLater(() => { if (root.replyOpen) replyInput.forceActiveFocus(); });
    }
    Component.onCompleted: {
        if (replyOpen) { notifications.setReplying(notification.key, true); Qt.callLater(() => { if (root.replyOpen) replyInput.forceActiveFocus(); }); }
    }
    Column {
        id: content
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 9
        spacing: 5
        Row {
            width: parent.width
            spacing: 6
            NotificationAvatar {
                width: 24; height: 24
                notification: root.notification
                theme: root.theme
            }
            Text {
                width: parent.width - 76
                anchors.verticalCenter: parent.verticalCenter
                text: (root.notification.unread ? "● " : "") + root.notification.app
                color: root.notification.unread ? root.theme.accent : root.theme.textMuted
                font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallFontSize - 1
                textFormat: Text.PlainText; elide: Text.ElideRight
            }
        }
        Button {
            HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
            width: parent.width
            padding: 0
            background: Item {}
            contentItem: Text {
                text: root.notification.summary || "Уведомление"
                textFormat: Text.PlainText
                color: root.theme.text; font.family: root.theme.fontFamily
                font.pixelSize: Math.round(root.theme.fontSize * 0.8); font.bold: true
                wrapMode: Text.Wrap; maximumLineCount: root.expanded ? 100 : 2
                elide: Text.ElideRight
            }
            onClicked: { root.selectedByMouse(); root.activate(); }
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.notification.body
            textFormat: Text.PlainText
            color: root.theme.textMuted; font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallFontSize - 1
            wrapMode: Text.Wrap; maximumLineCount: root.expanded ? 1000 : 3; elide: Text.ElideRight
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.selectedByMouse(); root.activate(); } }
        }
        Flow {
            width: parent.width; spacing: 5
            Repeater {
                model: root.notification.actions || []
                delegate: NotificationButton {
                    required property var modelData
                    theme: root.theme
                    implicitHeight: 24
                    text: modelData.text || modelData.id
                    onClicked: root.notifications.invoke(root.notification.key, modelData.id)
                }
            }
            NotificationButton {
                theme: root.theme; implicitHeight: 24; text: "Ответить"
                visible: root.notification.reply && root.notification.liveId !== null
                onClicked: root.replyRequested(root.notification.key)
            }
            NotificationButton {
                theme: root.theme; implicitHeight: 24; text: "Прочитано"
                visible: !root.popup && root.notification.unread
                onClicked: root.notifications.dismiss(root.notification.key)
            }
        }
        Row {
            width: parent.width; spacing: 5
            visible: root.replyOpen && root.notification.reply && root.notification.liveId !== null
            TextField {
                id: replyInput
                objectName: "notificationReply"
                width: parent.width - send.width - parent.spacing
                height: 32
                text: root.notifications.draft(root.notification.key)
                placeholderText: root.notification.replyPlaceholder || "Написать ответ…"
                color: root.theme.text; placeholderTextColor: root.theme.textMuted
                font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallFontSize - 1
                selectByMouse: true
                background: Rectangle { color: root.theme.surface; radius: 6; border.color: replyInput.activeFocus ? root.theme.accent : root.theme.border }
                onTextEdited: root.notifications.setDraft(root.notification.key, text)
                onAccepted: root.notifications.reply(root.notification.key, text)
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { root.replyCancelled(); event.accepted = true; }
                    // Text editing, including an empty-field Backspace, must not
                    // bubble into deletion/navigation of the containing stack.
                    else if (event.key === Qt.Key_Backspace && !text.length) event.accepted = true;
                }
            }
            NotificationButton {
                id: send; theme: root.theme; text: "Отправить"
                enabled: replyInput.text.trim().length > 0
                onClicked: root.notifications.reply(root.notification.key, replyInput.text)
            }
        }

    }
    Shared.IconButton {
        objectName: "notificationRemove-" + root.notification.key
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 9
        theme: root.theme
        iconName: root.popup ? "close" : "trash"
        label: root.popup ? "Закрыть уведомление" : "Удалить уведомление"
        onClicked: {
            if (root.popup) root.notifications.dismiss(root.notification.key);
            else root.notifications.remove(root.notification.key);
        }
    }
    Keys.onPressed: event => { if (keyHandler && !replyInput.activeFocus) keyHandler(event); }
}
```

## notifications/NotificationModel.qml

```qml
import QtQuick
import Quickshell
import Daevox.Notifications 1.0 as Native
import "NotificationState.js" as State

Scope {
    id: root
    property var records: []
    property bool dnd: false
    property string lockState: "unknown"
    property string error: ""
    property var engine: null
    readonly property bool ready: server.ready
    property bool initialized: false
    property bool storageEnabled: true
    readonly property bool blocked: lockState !== "unlocked"
    signal requestFocusReturn()
    Native.ArchiveFiles { id: files }
    Native.LockObserver { id: lock; onStateChanged: if (root.engine) root.engine.setLock(state) }
    Native.NotificationEndpoint {
        id: server
        onNotified: (id, data) => root.engine.receive(id, data)
        onClosed: (id, reason) => {
            const row = root.engine.records.find(item => item.liveId === id);
            if (row) root.engine.closed(row.key, reason === 1 || reason === 2);
        }
        onActionsUnavailable: id => {
            const row = root.engine.records.find(item => item.liveId === id);
            if (row) { row.actions = []; row.reply = false; row.replying = false; root.refresh(); }
        }
        onUnavailable: reason => root.error = reason
    }
    Component.onCompleted: {
        engine = State.create({ now: () => Date.now(), closeLive: root.closeLive, changed: root.refresh });
        if (storageEnabled) engine.restore(files.load());
        initialized = true;
        engine.setLock(lock.state);
        refresh();
    }
    Component.onDestruction: { if (initialized && storageEnabled) files.save(JSON.stringify(engine.snapshot())); }
    function refresh(): void {
        if (!engine || !initialized) return;
        records = engine.records.slice();
        dnd = engine.dnd;
        lockState = engine.lock;
        if (engine.error) error = engine.error;
        save.restart();
    }
    Timer {
        id: save; interval: 100
        onTriggered: if (root.storageEnabled && !files.save(JSON.stringify(root.engine.snapshot())))
            root.error = "Не удалось сохранить историю уведомлений"
    }
    Timer {
        interval: 100; running: root.initialized; repeat: true
        property double previous: Date.now()
        onTriggered: { const now = Date.now(); root.engine.tick(Math.max(0, now - previous)); previous = now; }
    }
    Timer { interval: 60000; repeat: true; running: root.initialized; onTriggered: root.engine.prune() }
    function closeLive(id: int, reason: string): void {
        server.close(id, reason === "expire" ? 1 : 2);
    }
    function toggleDnd(): void { engine.setDnd(!engine.dnd); }
    function remove(key: string): void { engine.remove([key]); }
    function removeGroup(group: string): void { engine.remove(engine.records.filter(row => row.group === group && !row.transient).map(row => row.key)); }
    function clear(): void { engine.remove(engine.records.filter(row => !row.transient).map(row => row.key)); }
    function dismiss(key: string): void { engine.dismiss(key, false); }
    function invoke(key: string, actionId: string): bool {
        const row = engine.find(key);
        return !!row && row.liveId !== null && server.invoke(row.liveId, actionId);
    }
    function reply(key: string, text: string): void {
        const row = engine.find(key);
        if (!row || row.liveId === null || !text.trim()) return;
        if (!server.reply(row.liveId, text)) return;
        engine.drafts[key] = "";
        if (engine.find(key)) engine.find(key).replying = false;
        refresh(); requestFocusReturn();
    }
    function draft(key: string): string { return engine.drafts[key] || ""; }
    function setDraft(key: string, text: string): void { engine.drafts[key] = text; }
    function setReplying(key: string, value: bool): void {
        const row = engine.find(key); if (row) row.replying = value;
    }
    function setHovered(key: string, value: bool): void {
        const row = engine.find(key); if (row) row.hovered = value;
    }
    function setScreens(names: var, active: string): void { if (engine) engine.setScreens(names, active); }
}
```

## notifications/NotificationPane.qml

```qml
pragma ComponentBehavior: Bound
import "../shared" as Shared
import QtQuick
import QtQuick.Controls
import "NotificationState.js" as State

Item {
    id: root
    objectName: "notificationPane"
    required property var theme
    required property var notifications
    property string query: ""
    property var keyHandler: null
    property bool unreadOnly: false
    property var expanded: ({})
    property string selected: ""
    property string replyKey: ""
    readonly property var groups: State.groups(notifications.records, query, unreadOnly)
    readonly property var rows: flatten()
    readonly property var selectedRow: rows.find(row => row.id === selected) || null
    signal searchFocusRequested()
    function flatten(): var {
        const entries = [];
        for (const group of groups) {
            if (group.rows.length > 1) {
                const open = !!expanded[group.key] || !!query.trim();
                entries.push({ id: "group:" + group.key, kind: open ? "header" : "cover", group: group, row: group.rows[0] });
                if (!open) continue;
            }
            for (const row of group.rows) entries.push({ id: row.key, kind: "card", group: group, row: row });
        }
        return entries;
    }
    onRowsChanged: {
        if (!rows.some(row => row.id === selected)) selected = rows.length ? rows[0].id : "";
        if (replyKey && !notifications.records.some(row => row.key === replyKey && row.liveId !== null && row.reply)) cancelReply();
    }
    onVisibleChanged: if (!visible) cancelReply()
    function toggle(group: string): void {
        const next = Object.assign({}, expanded); next[group] = !next[group]; expanded = next;
    }
    function moveSelection(delta: int): void {
        if (!rows.length) return;
        const index = rows.findIndex(row => row.id === selected);
        const next = (index + delta + rows.length) % rows.length;
        selected = rows[next].id; list.positionViewAtIndex(next, ListView.Contain);
        keyboardScroll.restart();
    }
    function activate(): void {
        const entry = selectedRow;
        if (!entry) return;
        if (entry.kind !== "card") toggle(entry.group.key);
        else {
            const index = rows.findIndex(row => row.id === selected);
            list.positionViewAtIndex(index, ListView.Contain);
            const loader = list.itemAtIndex(index);
            if (loader && loader.item) loader.item.activate();
        }
    }
    function removeSelected(): void {
        const entry = selectedRow;
        if (!entry) return;
        if (entry.kind === "card") notifications.remove(entry.row.key);
        else notifications.removeGroup(entry.group.key);
    }
    function cancelReply(): bool {
        if (!replyKey) return false;
        notifications.setReplying(replyKey, false);
        replyKey = ""; searchFocusRequested(); return true;
    }
    Connections { target: root.notifications; function onRequestFocusReturn() { root.cancelReply(); } }
    Row {
        id: toolbar
        anchors.left: parent.left; anchors.right: parent.right
        spacing: 5
        Shared.IconButton {
            theme: root.theme; iconName: "quiet"
            label: root.notifications.dnd ? "Выключить «Не беспокоить»" : "Включить «Не беспокоить»"
            active: root.notifications.dnd
            onClicked: root.notifications.toggleDnd()
        }
        Shared.IconButton {
            theme: root.theme; iconName: root.unreadOnly ? "filter" : "messages"
            label: root.unreadOnly ? "Показать все сообщения" : "Показать только непрочитанные"
            active: root.unreadOnly
            onClicked: root.unreadOnly = !root.unreadOnly
        }
        Shared.IconButton {
            theme: root.theme; iconName: "trash"; label: "Очистить всё"
            onClicked: root.notifications.clear()
        }
        Keys.onPressed: event => { if (root.keyHandler) root.keyHandler(event); }
    }
    Timer { id: keyboardScroll; interval: 1000 }
    ListView {
        id: list
        objectName: "notificationList"
        anchors.top: toolbar.bottom; anchors.topMargin: 10
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: scrollBar.width + 6
        clip: true; spacing: 6
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            objectName: "notificationScrollBar"
            parent: root
            anchors.top: list.top; anchors.bottom: list.bottom; anchors.right: parent.right
            width: 6
            active: hovered || pressed || list.moving || keyboardScroll.running
        }
        delegate: Loader {
            id: entryLoader
            required property var modelData
            width: list.width
            sourceComponent: modelData.kind === "card" ? cardComponent : stackComponent
            Component {
                id: cardComponent
                NotificationCard {
                    width: entryLoader.width
                    notification: entryLoader.modelData.row
                    notifications: root.notifications; theme: root.theme
                    selected: root.selected === entryLoader.modelData.id
                    keyHandler: root.keyHandler
                    replyOpen: root.replyKey === notification.key
                    onReplyRequested: key => { root.replyKey = key; root.selected = key; }
                    onReplyCancelled: root.cancelReply()
                    onSelectedByMouse: root.selected = entryLoader.modelData.id
                }
            }
            Component {
                id: stackComponent
                Item {
                    id: stack
                    readonly property bool cover: entryLoader.modelData.kind === "cover"
                    width: entryLoader.width
                    implicitHeight: cover ? coverContent.implicitHeight + 30 : 36
                    Rectangle { visible: stack.cover; x: 12; y: 12; width: parent.width - 24; height: parent.height - 12; radius: 10; color: root.theme.background; border.color: root.theme.border }
                    Rectangle { visible: stack.cover; x: 6; y: 6; width: parent.width - 12; height: parent.height - 12; radius: 10; color: root.theme.surface; border.color: root.theme.border }
                    HoverHandler { id: stackHover }
                    Button {
                        HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
                        width: parent.width; height: stack.cover ? parent.height - 12 : parent.height
                        padding: 8
                        background: Rectangle {
                            radius: 10; color: root.theme.surface
                            border.color: root.selected === entryLoader.modelData.id || parent.activeFocus || stackHover.hovered ? root.theme.accent : root.theme.border
                        }
                        contentItem: Column {
                            id: coverContent
                            spacing: 5
                            Row {
                                width: parent.width
                                spacing: 6
                                NotificationAvatar {
                                    width: 24; height: 24
                                    visible: stack.cover
                                    notification: entryLoader.modelData.row
                                    theme: root.theme
                                }
                                Text {
                                    width: parent.width - (stack.cover ? 30 : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                    rightPadding: 44
                                    text: entryLoader.modelData.group.app + " · " + entryLoader.modelData.group.rows.length + (stack.cover ? "   ▾" : "   ▴ Свернуть")
                                    textFormat: Text.PlainText; elide: Text.ElideRight
                                    color: root.theme.accent; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallFontSize - 1
                                }
                            }
                            Text {
                                visible: stack.cover; width: parent.width
                                text: (entryLoader.modelData.row.unread ? "● " : "") + entryLoader.modelData.row.summary
                                textFormat: Text.PlainText; elide: Text.ElideRight
                                color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: Math.round(root.theme.fontSize * 0.8); font.bold: true
                            }
                            Text {
                                visible: stack.cover; width: parent.width
                                text: entryLoader.modelData.row.body
                                textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallFontSize - 1
                            }
                            Text {
                                visible: stack.cover
                                text: "Ещё " + (entryLoader.modelData.group.rows.length - 1) + " · раскрыть стопку  /  "
                                    + entryLoader.modelData.group.rows.filter(row => row.unread).length + " непрочитанных"
                                color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallFontSize - 1
                            }
                        }
                        onClicked: { root.selected = entryLoader.modelData.id; root.toggle(entryLoader.modelData.group.key); }
                        Keys.onPressed: event => { if (root.keyHandler) root.keyHandler(event); }
                    }
                    Shared.IconButton {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: stack.cover ? 5 : 2
                        theme: root.theme; iconName: "trash"; label: "Удалить стопку"
                        onClicked: root.notifications.removeGroup(entryLoader.modelData.group.key)
                        Keys.onPressed: event => { if (root.keyHandler) root.keyHandler(event); }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent; visible: !list.count
            text: root.query || root.unreadOnly ? "Нет подходящих уведомлений" : "Уведомлений пока нет"
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.fontSize
        }
    }
}
```

## notifications/NotificationPopups.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var desktop
    required property var notifications
    property string replyKey: ""
    Theme { id: popupTheme }
    function syncScreens(): void {
        notifications.setScreens(Quickshell.screens.map(screen => screen.name), (desktop.screenFor(Quickshell.screens) || {}).name || "");
    }
    Component.onCompleted: Qt.callLater(syncScreens)
    Connections { target: Quickshell; function onScreensChanged() { root.syncScreens(); } }
    Connections { target: root.desktop; function onActiveMonitorChanged() { root.syncScreens(); } }
    Connections {
        target: root.notifications
        function onInitializedChanged() { root.syncScreens(); }
        function onRequestFocusReturn() { root.cancelReply(); }
        function onRecordsChanged() {
            if (root.replyKey && !root.notifications.records.some(row => row.key === root.replyKey && row.popup === "visible" && row.liveId !== null && row.reply)) root.cancelReply();
        }
        function onBlockedChanged() { if (root.notifications.blocked) root.cancelReply(); }
        function onDndChanged() { if (root.notifications.dnd) root.cancelReply(); }
    }
    function cancelReply(): void {
        if (replyKey) notifications.setReplying(replyKey, false);
        replyKey = "";
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: window
            required property var modelData
            readonly property var rows: root.notifications.records.filter(row => row.popup === "visible" && row.screen === modelData.name)
            screen: modelData
            visible: rows.length > 0 && !root.notifications.blocked && !root.notifications.dnd
            anchors { top: true; right: true }
            margins { top: 44; right: 12 }
            implicitWidth: Math.min(380, modelData.width - 24)
            implicitHeight: Math.min(column.implicitHeight, modelData.height - 60)
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "daevox-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.replyKey && rows.some(row => row.key === root.replyKey) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Flickable {
                anchors.fill: parent; clip: true
                contentHeight: column.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: column; width: parent.width; spacing: 8
                    Repeater {
                        model: window.rows
                        delegate: NotificationCard {
                            required property var modelData
                            width: column.width
                            notification: modelData; notifications: root.notifications; theme: popupTheme
                            popup: true; replyOpen: root.replyKey === notification.key
                            onReplyRequested: key => root.replyKey = key
                            onReplyCancelled: root.cancelReply()
                        }
                    }
                }
            }
        }
    }
}
```

## notifications/NotificationRuntime.qml

```qml
import Quickshell

Scope {
    id: root
    required property var desktop
    property alias model: notificationModel
    NotificationModel { id: notificationModel }
    NotificationPopups { desktop: root.desktop; notifications: notificationModel }
}
```

## notifications/NotificationState.js

```javascript
// The state machine has no Qt objects. Native notification lifetimes and disk
// writes are supplied by the controller, so timing and deletion are testable.
function create(options) {
    const state = {
        records: [], dnd: false, lock: "unknown", screens: [], activeScreen: "",
        serial: 0, epoch: String(options.now()), error: "", drafts: {},
        now: options.now, closeLive: options.closeLive,
        changed: options.changed || function() {},
        maxRecords: 500, maxAge: 7 * 86400000, maxTransient: 100
    };
    state.find = key => state.records.find(row => row.key === key);
    state.allowed = () => !state.dnd && state.lock === "unlocked";
    state.timeout = data => data.urgency === 2 || data.timeout === 0 ? -1 : data.timeout < 0 ? 5000 : data.timeout;
    state.pump = () => {
        if (!state.allowed()) return;
        let available = Math.max(0, 3 - state.records.filter(row => row.popup === "visible").length);
        if (!state.screens.length) return;
        for (const row of state.records.filter(row => row.popup === "queued").sort((a,b) => a.queuedAt - b.queuedAt)) {
            if (!available--) break;
            row.popup = "visible";
            row.screen = state.screens.includes(state.activeScreen) ? state.activeScreen : state.screens[0];
        }
    };
    state.receive = (id, data) => {
        let row = state.records.find(item => item.liveId === id);
        const isNew = !row;
        if (!row) {
            row = { key: state.epoch + "-" + (++state.serial), liveId: id, unread: true,
                popup: state.allowed() ? "queued" : "suppressed", queuedAt: state.now(),
                screen: "", hovered: false, replying: false };
            state.records.push(row);
        }
        Object.assign(row, data, { updated: state.now(), remaining: state.timeout(data) });
        // Replacement updates content but never revives a suppressed popup.
        if (row.transient && row.popup === "suppressed") state.remove([row.key]);
        else {
            state.prune();
            const temporary = state.records.filter(item => item.transient);
            if (temporary.length > state.maxTransient)
                state.remove(temporary.slice(0, temporary.length - state.maxTransient).map(item => item.key));
            state.pump(); state.changed();
        }
        return { key: row.key, isNew: isNew };
    };
    state.closed = (key, read) => {
        const row = state.find(key);
        if (!row) return;
        row.liveId = null; row.popup = "none"; row.actions = []; row.reply = false;
        row.replying = false; row.hovered = false;
        if (read) row.unread = false;
        if (row.transient) {
            state.records = state.records.filter(item => item !== row);
            delete state.drafts[key];
        }
        state.pump(); state.changed();
    };
    state.dismiss = (key, expired) => {
        const row = state.find(key);
        if (!row) return;
        const id = row.liveId;
        state.closed(key, true);
        if (id !== null) state.closeLive(id, expired ? "expire" : "dismiss");
    };
    state.remove = keys => {
        const removed = state.records.filter(row => keys.includes(row.key));
        state.records = state.records.filter(row => !keys.includes(row.key));
        for (const row of removed) {
            delete state.drafts[row.key];
            if (row.liveId !== null) state.closeLive(row.liveId, "dismiss");
        }
        state.pump(); state.changed();
    };
    state.prune = () => {
        const rows = state.records.filter(row => !row.transient).sort((a,b) => b.updated - a.updated);
        const expired = rows.filter((row, index) => index >= state.maxRecords || row.updated < state.now() - state.maxAge);
        if (expired.length) state.remove(expired.map(row => row.key));
    };
    state.suppress = () => {
        for (const row of state.records) {
            if (row.popup === "visible" || row.popup === "queued") row.popup = "suppressed";
            row.replying = false; row.hovered = false;
        }
        state.remove(state.records.filter(row => row.transient).map(row => row.key));
        state.changed();
    };
    state.setDnd = value => { state.dnd = value; if (value) state.suppress(); state.changed(); };
    state.setLock = value => { state.lock = value; if (value !== "unlocked") state.suppress(); state.changed(); };
    state.setScreens = (names, active) => {
        state.screens = names; state.activeScreen = active;
        for (const row of state.records) {
            if (row.popup === "visible" && !names.includes(row.screen)) {
                row.screen = names.includes(active) ? active : names[0] || "";
            }
        }
        state.pump(); state.changed();
    };
    state.tick = elapsed => {
        if (!state.allowed()) return;
        const expired = [];
        for (const row of state.records) {
            if (row.popup !== "visible" || !row.screen || row.hovered || row.replying || row.remaining < 0) continue;
            row.remaining -= elapsed;
            if (row.remaining <= 0) expired.push(row.key);
        }
        expired.forEach(key => state.dismiss(key, true));
    };
    state.snapshot = () => ({ version: 1, dnd: state.dnd,
        records: state.records.filter(row => !row.transient).map(row => ({
            key: row.key, app: row.app, group: row.group, icon: row.icon,
            summary: row.summary, body: row.body, image: row.image,
            updated: row.updated, unread: row.unread, urgency: row.urgency
        })) });
    state.restore = text => {
        if (!text) return;
        try {
            const saved = JSON.parse(text);
            if (saved.version !== 1 || !Array.isArray(saved.records) || typeof saved.dnd !== "boolean") throw new Error("format");
            const seen = new Set();
            state.records = saved.records.filter(row => row && typeof row.key === "string"
                && typeof row.app === "string" && typeof row.group === "string"
                && typeof row.summary === "string" && typeof row.body === "string"
                && Number.isFinite(row.updated) && !seen.has(row.key) && seen.add(row.key))
                .map(row => ({ key: row.key, app: row.app, group: row.group, summary: row.summary,
                    body: row.body, updated: row.updated, icon: typeof row.icon === "string" ? row.icon : "",
                    image: typeof row.image === "string" ? row.image : "", unread: !!row.unread,
                    urgency: row.urgency === 2 ? 2 : 1, transient: false, liveId: null,
                    popup: "none", actions: [], reply: false, remaining: -1, screen: "" }));
            state.dnd = saved.dnd;
            state.prune();
        } catch (_) { state.error = "Не удалось прочитать историю уведомлений"; }
    };
    return state;
}
function groups(records, query, unreadOnly) {
    const needle = query.trim().toLocaleLowerCase();
    const result = [];
    for (const row of records.filter(row => !row.transient).sort((a,b) => b.updated - a.updated)) {
        if (unreadOnly && !row.unread) continue;
        if (needle && !(row.app + " " + row.summary + " " + row.body).toLocaleLowerCase().includes(needle)) continue;
        let group = result.find(item => item.key === row.group);
        if (!group) { group = { key: row.group, app: row.app, rows: [] }; result.push(group); }
        group.rows.push(row);
    }
    return result;
}
if (typeof module !== "undefined") module.exports = { create, groups };
```

## notifications/Theme.qml

```qml
import "../shared" as Shared

Shared.DaevoxTheme {
    readonly property int fontSize: 13
    readonly property int smallFontSize: 11
}
```

## shared/DaevoxTheme.qml

```qml
import QtQuick

QtObject {
    readonly property int motionQuick: 100
    readonly property int motionNormal: 150
    readonly property int motionEnter: 180
    readonly property int motionExit: 120

    // Catppuccin Mocha: base, surface0, text, subtext0, mauve, surface1, crust.
    readonly property string fontFamily: "Monoid"
    readonly property color background: "#1e1e2e"
    readonly property color surface: "#313244"
    readonly property color text: "#cdd6f4"
    readonly property color textMuted: "#a6adc8"
    readonly property color accent: "#cba6f7"
    readonly property color border: "#45475a"
    readonly property color shadow: "#8011111b"
    readonly property color transparent: "transparent"
    readonly property color urgent: "#f9e2af"
}
```

## shared/Icon.qml

```qml
import QtQuick

Image {
    id: root
    required property string name
    property color color: "white"
    readonly property var paths: ({
        apps: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        volume: '<path d="M11 4 6 8H3v8h3l5 4Z"/><path d="M15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
        bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
        quiet: '<path d="M9 3a6 6 0 0 1 9 5v4M6 7c0 6-3 8-3 10h14M10 21h4M3 3l18 18"/>',
        messages: '<path d="M4 3h16v18l-4-3H4Z"/><path d="M8 7h8M8 11h8M8 15h4"/>',
        filter: '<path d="M3 4h18l-7 8v7l-4 2v-9Z"/>',
        trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
        close: '<path d="m6 6 12 12M18 6 6 18"/>'
    })
    width: 20
    height: 20
    sourceSize: Qt.size(48, 48)
    source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="'
        + color.toString() + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (paths[name] || paths.messages) + '</svg>')
    fillMode: Image.PreserveAspectFit
}
```

## shared/IconButton.qml

```qml
import QtQuick
import QtQuick.Controls

Button {
    id: root
    HoverHandler { enabled: parent.enabled; cursorShape: Qt.PointingHandCursor }
    required property var theme
    required property string iconName
    required property string label
    property bool active: false
    property int iconSize: 20
    property bool shadowEnabled: false
    implicitWidth: iconSize + leftPadding + rightPadding
    implicitHeight: iconSize + topPadding + bottomPadding
    scale: down ? 0.94 : 1
    Behavior on scale {
        NumberAnimation { duration: root.theme.motionQuick; easing.type: Easing.OutCubic }
    }
    padding: 4
    text: ""
    Accessible.name: label
    ToolTip.text: label
    ToolTip.visible: hovered
    ToolTip.delay: 500
    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            name: root.iconName
            color: root.active ? root.theme.accent : root.theme.textMuted
        }
    }
    background: Rectangle {
        Rectangle {
            z: -1
            visible: root.shadowEnabled
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: 1
            anchors.bottomMargin: -4
            radius: 10
            color: root.theme.shadow
        }
        radius: 8
        color: root.active || root.hovered || root.down ? root.theme.surface : root.theme.background
        border.color: root.activeFocus ? root.theme.accent : root.theme.border
        Behavior on color { ColorAnimation { duration: root.theme.motionQuick } }
        Behavior on border.color { ColorAnimation { duration: root.theme.motionQuick } }
    }
}
```

## shared/qmldir

```ini
DaevoxTheme 1.0 DaevoxTheme.qml
Icon 1.0 Icon.qml
IconButton 1.0 IconButton.qml
```

## Daevox/Notifications/qmldir

```ini
module Daevox.Notifications
plugin daevoxnotifications
```

## docs/examples/daevox-shell.service

```ini
[Unit]
Description=Daevox Shell (Quickshell)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=exec
TimeoutStartSec=15
TimeoutStopSec=15
Environment=DAEVOX_NOTIFICATIONS=0
Environment=QML_IMPORT_PATH=%h/.config/quickshell/daevox-shell
ExecStart=/usr/bin/env QML_IMPORT_PATH=%h/.config/quickshell/daevox-shell /usr/bin/qs --no-duplicate --log-rules quickshell.io.socket.warning=false --path %h/.config/quickshell/daevox-shell/shell.qml
Restart=on-failure
RestartSec=1
Slice=app-graphical.slice

[Install]
WantedBy=graphical-session.target
```

## docs/examples/hyprland-launcher.lua

```lua
-- Hyprland 0.56.x: add this to your Lua config after installing Daevox Shell.
-- The short-lived qs IPC client controls the existing QML process.
hl.bind("SUPER + Space", hl.dsp.exec_cmd(
    'qs ipc --path "$HOME/.config/quickshell/daevox-shell/shell.qml" call launcher toggle'
))
```
