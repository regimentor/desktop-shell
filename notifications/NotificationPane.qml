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
