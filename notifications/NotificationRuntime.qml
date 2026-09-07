import Quickshell

Scope {
    id: root
    required property var desktop
    property alias model: notificationModel
    NotificationModel { id: notificationModel }
    NotificationPopups { desktop: root.desktop; notifications: notificationModel }
}
