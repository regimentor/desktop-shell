pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Services.SystemTray

Row {
    id: root
    required property var theme
    required property var panel
    spacing: 5
    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: item
            required property SystemTrayItem modelData
            width: 20
            height: 24
            Rectangle {
                anchors.fill: parent
                radius: 5
                color: mouse.containsMouse ? root.theme.hover : "transparent"
            }
            Image {
                anchors.centerIn: parent
                width: root.theme.trayIconSize
                height: width
                source: item.modelData.icon
                sourceSize.width: 28
                sourceSize.height: 28
                fillMode: Image.PreserveAspectFit
            }
            function menu(): void {
                if (!modelData.hasMenu) return;
                const point = item.mapToItem(root.panel.contentItem, 0, height);
                modelData.display(root.panel, Math.round(point.x), Math.round(point.y));
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && item.modelData.onlyMenu)) item.menu();
                    else if (event.button === Qt.MiddleButton) item.modelData.secondaryActivate();
                    else item.modelData.activate();
                }
                onWheel: event => {
                    if (event.angleDelta.y) item.modelData.scroll(event.angleDelta.y, false);
                    if (event.angleDelta.x) item.modelData.scroll(event.angleDelta.x, true);
                    event.accepted = true;
                }
            }
            ToolTip.visible: mouse.containsMouse
            ToolTip.delay: 500
            ToolTip.text: [modelData.tooltipTitle || modelData.title, modelData.tooltipDescription].filter(Boolean).join("\n")
        }
    }
}
