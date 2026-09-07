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
