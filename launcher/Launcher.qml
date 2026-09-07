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
    visible: false
    color: theme.transparent
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.min(theme.windowWidth, screen.width - 2 * theme.spacing)
    implicitHeight: Math.min(panelTop + theme.searchHeight + theme.rowHeight * theme.visibleRows
        + theme.footerHeight + 2.5 * theme.spacing, screen.height - 2 * theme.spacing)
    WlrLayershell.namespace: "daevox-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
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
        function onBlockedChanged() { if (root.notifications.blocked) root.close(); }
    }
    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.close()
    }

    function open(): void { openMode("apps"); }

    function openMode(value: string): void {
        if (notifications && notifications.blocked) return;
        const target = desktop.screenFor(Quickshell.screens);
        if (!target) return;
        screen = target;
        search.text = "";
        mode = ["apps", "audio", "notifications"].includes(value) ? value : "apps";
        if (notificationPane.item) notificationPane.item.cancelReply();
        if (mode === "audio") router.check();
        audioPane.reset();
        apps.error = "";
        resetSelection();
        visible = true;
        search.forceActiveFocus();
        grab.active = true;
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!Quickshell.screens.includes(root.screen)) {
                root.close();
                root.screen = root.desktop.screenFor(Quickshell.screens);
            }
        }
    }

    function close(): void {
        if (notificationPane.item) notificationPane.item.cancelReply();
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
        if (notificationPane.item) notificationPane.item.cancelReply();
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
            keyHandler: event => root.handleKey(event, false)
        }
        Loader {
            id: notificationPane
            active: root.notifications !== null
            visible: root.mode === "notifications"
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
