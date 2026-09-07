import QtQuick
import QtQuick.Controls

Button {
    id: root
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
