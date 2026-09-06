# Полный код launcher

Снимок реализации и готовых интеграционных примеров. Инструкция: [launcher.md](launcher.md).

## launcher/shell.qml

```qml
import Quickshell
import Quickshell.Io

ShellRoot {
    Launcher { id: launcher }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle(); }
        function open(): void { launcher.open(); }
        function close(): void { launcher.close(); }
        function status(): string { return launcher.status(); }
    }
}
```

## launcher/Launcher.qml

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    property string mode: "apps"
    visible: false
    color: theme.transparent
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.min(theme.windowWidth, screen.width - 2 * theme.spacing)
    implicitHeight: Math.min(82 + (mode === "audio" ? 130 : 0) + theme.searchHeight + theme.rowHeight * theme.visibleRows
        + theme.footerHeight + 2.5 * theme.spacing, screen.height - 2 * theme.spacing)
    WlrLayershell.namespace: "daevox-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        item: panel
        Region { item: modes }
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
    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.close()
    }

    function open(): void {
        const monitor = Hyprland.focusedMonitor;
        const target = Quickshell.screens.find(candidate => monitor && candidate.name === monitor.name);
        if (target) screen = target;
        search.text = "";
        mode = "apps";
        audioPane.reset();
        apps.error = "";
        resetSelection();
        visible = true;
        search.forceActiveFocus();
        grab.active = true;
    }

    function close(): void {
        audioPane.reset();
        grab.active = false;
        visible = false;
    }

    function toggle(): void {
        if (visible) close();
        else open();
    }

    function status(): string {
        return JSON.stringify({ visible: visible, applications: apps.catalogue.length,
            mode: mode, audioApplications: audio.groups.length, audioReady: audio.ready,
            routingAvailable: router.available, routingMessage: router.message,
            results: apps.results.length, selected: list.currentIndex,
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

    function handleKey(event: var): void {
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        if (alt && (event.key === Qt.Key_1 || event.key === Qt.Key_2)) {
            switchMode(event.key === Qt.Key_1 ? "apps" : "audio");
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
            if (search.text) search.text = "";
            else close();
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
        mode = value;
        search.text = "";
        audioPane.reset();
        resetSelection();
        search.forceActiveFocus();
        if (value === "audio") router.check();
    }

    Row {
        id: modes
        anchors.top: parent.top
        anchors.topMargin: theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16
        Repeater {
            model: [{ mode: "apps", title: "▦  Apps", hint: "Alt+1" },
                { mode: "audio", title: "♪  Звук", hint: "Alt+2" }]
            delegate: Column {
                id: modeButton
                required property var modelData
                spacing: 4
                Button {
                    objectName: "mode-" + modeButton.modelData.mode
                    width: 112
                    height: 42
                    text: modeButton.modelData.title
                    font.family: theme.fontFamily
                    palette.buttonText: theme.text
                    background: Rectangle {
                        color: root.mode === modeButton.modelData.mode ? theme.surface : theme.background
                        border.color: parent.activeFocus ? theme.accent : theme.border
                        radius: 18
                    }
                    onClicked: root.switchMode(modeButton.modelData.mode)
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => root.handleKey(event)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modeButton.modelData.hint
                    color: theme.textMuted
                    font.family: theme.fontFamily
                    font.pixelSize: theme.smallFontSize
                }
            }
        }
    }

    // A small static shadow keeps the MVP free of shader effects and animation.
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
        anchors.topMargin: 82
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
            placeholderText: root.mode === "audio" ? "Поиск звуковых приложений…" : "Search applications…"
            placeholderTextColor: theme.textMuted
            selectionColor: theme.accent
            selectedTextColor: theme.background
            background: Item {}
            focus: true
            selectByMouse: true
            activeFocusOnTab: root.mode === "audio"
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => root.handleKey(event)
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
            highlightMoveDuration: 0
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: theme.rowHeight
                radius: theme.radius / 2
                color: ListView.isCurrentItem ? theme.surface : theme.transparent
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
                    anchors.fill: parent
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
            keyHandler: root.handleKey
        }
        Text {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: theme.spacing
            height: theme.footerHeight - theme.spacing
            text: root.mode === "audio" ? (router.unavailableReason || "← → Громкость · Alt+M Mute · Alt+O Выход · Enter Потоки")
                : apps.error || (apps.launching ? "Launching…" : "↑ ↓  Navigate     Enter: Launch     Esc: Close")
            color: apps.error ? theme.accent : theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.smallFontSize
            elide: Text.ElideRight
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

## launcher/AudioMath.js

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

## launcher/AudioModel.qml

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

## launcher/AudioRouter.qml

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

## launcher/AudioControls.qml

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    required property Theme theme
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
    implicitHeight: subtitle ? 74 : 50
    radius: theme.radius / 2
    color: selected ? theme.surface : theme.transparent
    border.color: activeFocus ? theme.accent : theme.transparent

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
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
                Layout.fillWidth: true
                Layout.minimumWidth: 60
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
                objectName: "volumeSlider"
                Layout.preferredWidth: 150
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
                Layout.preferredWidth: 42
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

## launcher/AudioPane.qml

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property Theme theme
    required property AudioModel audio
    required property AudioRouter router
    required property var keyHandler
    property string query: ""
    property string selectedKey: "system"
    property var expanded: ({})
    property string pickerGroupKey: ""
    readonly property bool pickerOpen: picker.visible
    readonly property var rows: buildRows()
    readonly property var selectedRow: rows.find(row => row.key === selectedKey)
    readonly property var selectedGroup: selectedRow ? selectedRow.group : null
    readonly property var pickerGroup: audio.groups.find(group => group.key === pickerGroupKey)
    onRowsChanged: {
        if (selectedKey !== "system" && !rows.some(row => row.key === selectedKey)) selectedKey = "system";
        if (picker.visible && !pickerGroup) picker.close();
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
        if (!group || !router.available || router.pending) return;
        pickerGroupKey = group.key;
        devices.currentIndex = 0;
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
        if (index < 0 || index >= audio.outputs.length || !pickerGroup) return;
        router.move(pickerGroup, audio.outputs[index]);
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
    ListView {
        id: list
        anchors.top: system.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        spacing: 4
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
                width: parent.width
                height: visible ? 30 : 0
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
        anchors.centerIn: parent
        width: Math.min(420, root.width - 20)
        height: Math.min(240, root.height)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
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
                required property var modelData
                required property int index
                width: ListView.view.width
                text: root.audio.label(modelData)
                highlighted: devices.currentIndex === index
                palette.text: root.theme.text
                palette.highlight: root.theme.surface
                palette.highlightedText: root.theme.accent
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

## launcher/Theme.qml

```qml
import "shared" as Shared

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

## shared/DaevoxTheme.qml

`launcher/shared` — символическая ссылка на `../shared`.

```qml
import QtQuick

QtObject {
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

## launcher/.qmlls.ini

```ini
[General]
buildDir=/usr/lib/qt6/qml
importPaths=/usr/lib/qt6/qml
```

## docs/examples/daevox-launcher.service

```ini
[Unit]
Description=Daevox application launcher (Quickshell)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=exec
ExecStart=/usr/bin/qs --no-duplicate --path %h/.config/quickshell/daevox-launcher/shell.qml
Restart=on-failure
RestartSec=1
Slice=app-graphical.slice

[Install]
WantedBy=graphical-session.target
```

## docs/examples/hyprland-launcher.lua

```lua
-- Hyprland 0.56.x: add this to your Lua config after installing the launcher.
-- The short-lived qs IPC client controls the existing QML process.
hl.bind("SUPER + Space", hl.dsp.exec_cmd(
    'qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher toggle'
))
```
