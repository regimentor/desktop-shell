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
