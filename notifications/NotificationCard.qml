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
