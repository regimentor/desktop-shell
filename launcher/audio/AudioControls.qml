import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    required property var theme
    required property var keyHandler
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property real volume: 0
    property string muteState: "audible"
    property bool selected: false
    property bool expandable: false
    property bool expanded: false
    property bool available: true
    signal selectedByUser()
    signal expandClicked()
    signal volumeEdited(real value)
    signal muteClicked()
    implicitHeight: subtitle ? 54 : 36
    radius: theme.radius / 2
    color: selected ? theme.surface : theme.transparent
    border.color: activeFocus ? theme.accent : theme.transparent

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Image {
                id: appIcon
                visible: root.icon !== ""
                Layout.preferredWidth: visible ? 24 : 0
                Layout.preferredHeight: 24
                source: root.icon ? Quickshell.iconPath(root.icon, true) : ""
                fillMode: Image.PreserveAspectFit
                Text {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: root.title.charAt(0)
                    color: root.theme.accent
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize
                }
            }
            Button {
                id: titleButton
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.preferredHeight: 28
                text: (root.expandable ? (root.expanded ? "▾ " : "▸ ") : "") + root.title
                flat: true
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fontSize
                palette.buttonText: root.theme.text
                contentItem: Text {
                    text: titleButton.text
                    color: root.theme.text
                    font: titleButton.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    root.selectedByUser();
                    if (root.expandable) root.expandClicked();
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Accessible.name: root.title
            }
            Slider {
                id: slider
                objectName: "volumeSlider"
                Layout.preferredWidth: 150
                Layout.preferredHeight: 28
                enabled: root.available
                from: 0
                to: 1
                value: Math.max(0, Math.min(1, root.volume))
                stepSize: 0
                palette.highlight: root.theme.accent
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 5
                    radius: 3
                    color: root.theme.border
                    Rectangle {
                        width: slider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: root.available ? root.theme.accent : root.theme.textMuted
                    }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    implicitWidth: 14
                    implicitHeight: 14
                    radius: 7
                    color: root.available ? root.theme.accent : root.theme.textMuted
                    border.width: slider.activeFocus ? 2 : 0
                    border.color: root.theme.text
                }
                onMoved: root.volumeEdited(value)
                onPressedChanged: if (pressed) root.selectedByUser()
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                Accessible.name: root.title + ": громкость"
            }
            Text {
                Layout.preferredWidth: 46
                text: root.available ? Math.round(root.volume * 100) + "%" : "—"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                horizontalAlignment: Text.AlignRight
            }
            Button {
                id: muteButton
                Layout.preferredWidth: 42
                Layout.preferredHeight: 28
                text: root.muteState === "muted" ? "×" : root.muteState === "mixed" ? "◐" : "♪"
                enabled: root.available
                palette.button: root.theme.background
                palette.buttonText: root.theme.accent
                background: Rectangle {
                    radius: 7
                    color: muteButton.down ? root.theme.surface : root.theme.background
                    border.color: muteButton.activeFocus ? root.theme.accent : root.theme.border
                }
                onClicked: { root.selectedByUser(); root.muteClicked(); }
                onActiveFocusChanged: if (activeFocus) root.selectedByUser()
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                Accessible.name: root.title + (root.muteState === "muted" ? ": включить звук" : ": выключить звук")
                ToolTip.visible: hovered
                ToolTip.text: root.muteState === "mixed" ? "Частично заглушено" : root.muteState === "muted" ? "Звук выключен" : "Выключить звук"
            }
        }
        Text {
            visible: root.subtitle !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 8
            text: root.subtitle
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallFontSize
            elide: Text.ElideRight
        }
    }
}
