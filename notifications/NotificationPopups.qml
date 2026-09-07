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
