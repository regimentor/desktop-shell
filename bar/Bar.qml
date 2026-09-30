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
    implicitHeight: barTheme.height
    exclusiveZone: implicitHeight
    color: "transparent"
    Rectangle {
        id: surface
        anchors.fill: parent
        color: barTheme.background
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
