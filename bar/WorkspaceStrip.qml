pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
    id: root
    required property var hyprland
    required property var theme
    required property var icons
    required property string output
    required property real availableWidth
    readonly property var groups: hyprland.groups(output)
    readonly property real labelsWidth: groups.reduce((sum, w) => sum + metrics.advanceWidth(w.label), 0)
    readonly property real decorationWidth: groups.reduce((sum, w) => sum + 10 + w.windows.length * 19, 0) + Math.max(0, groups.length - 1) * 2
    readonly property real naturalWidth: labelsWidth + decorationWidth
    readonly property real density: decorationWidth ? Math.max(0.01, Math.min(1, (availableWidth - labelsWidth) / decorationWidth)) : 1
    readonly property real emergencyScale: labelsWidth + decorationWidth * density > availableWidth ? Math.max(0, availableWidth / (labelsWidth + decorationWidth * density)) : 1
    implicitWidth: Math.min(naturalWidth, Math.max(0, availableWidth))
    implicitHeight: 24
    function clickPosition(item: var, event: var): var {
        const point = item.mapToItem(null, event.x, event.y);
        return hyprland.globalPosition(output, point);
    }
    FontMetrics { id: metrics; font.family: root.theme.fontFamily; font.pixelSize: root.theme.fontSize }
    Row {
        spacing: 2 * root.density
        scale: root.emergencyScale
        transformOrigin: Item.Left
        Repeater {
            model: ScriptModel { values: root.groups.map(w => w.id) }
            delegate: Rectangle {
                id: group
                required property var modelData
                readonly property var workspace: root.groups.find(w => w.id === modelData) || { active: false, label: "", windows: [] }
                width: contents.implicitWidth + 10 * root.density
                height: 24
                radius: 5
                color: workspaceHover.containsMouse ? root.theme.hover : workspace.active ? root.theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: root.theme.workspaceAnimationDuration; easing.type: Easing.InOutQuad } }
                MouseArea {
                    id: workspaceHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => root.hyprland.activateWorkspace(root.output, group.workspace, root.clickPosition(workspaceHover, event))
                    onWheel: wheel => { wheel.accepted = true; }
                }
                Row {
                    id: contents
                    anchors.centerIn: parent
                    spacing: 3 * root.density
                    Text {
                        text: group.workspace.label
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        color: group.workspace.active ? root.theme.accent : root.theme.textMuted
                        Behavior on color { ColorAnimation { duration: root.theme.workspaceAnimationDuration; easing.type: Easing.InOutQuad } }
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSize
                    }
                    Repeater {
                        model: ScriptModel { values: group.workspace.windows.map(w => w.address) }
                        delegate: Item {
                            id: windowIcon
                            required property var modelData
                            readonly property var windowData: group.workspace.windows.find(w => w.address === modelData) || { address: "", title: "" }
                            width: 16 * root.density
                            height: 24
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: hover.containsMouse ? root.theme.hover : "transparent"
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: root.theme.urgent
                                opacity: 0.3
                                visible: root.hyprland.windowUrgent(windowIcon.windowData.address) || !!windowIcon.windowData.urgent
                            }
                            Image {
                                anchors.centerIn: parent
                                width: parent.width
                                height: width
                                source: root.icons.resolve(windowIcon.windowData.class || "", windowIcon.windowData.initialClass || "")
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(8, parent.width)
                                height: 2
                                radius: 1
                                color: root.theme.accent
                                visible: root.hyprland.windowActive(windowIcon.windowData.address)
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => root.hyprland.activateWindow(windowIcon.windowData.address, root.clickPosition(hover, event))
                                onWheel: wheel => { wheel.accepted = true; }
                            }
                        }
                    }
                }
            }
        }
    }
}
