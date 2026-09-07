pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var theme
    required property AudioModel audio
    required property AudioRouter router
    required property var keyHandler
    property string query: ""
    property string selectedKey: "system"
    property var expanded: ({})
    property string pickerGroupKey: ""
    readonly property bool pickerForSystem: pickerGroupKey === ""
    readonly property bool pickerOpen: picker.visible
    readonly property var rows: buildRows()
    readonly property var selectedRow: rows.find(row => row.key === selectedKey)
    readonly property var selectedGroup: selectedRow ? selectedRow.group : null
    readonly property var pickerGroup: audio.groups.find(group => group.key === pickerGroupKey)
    onRowsChanged: {
        if (selectedKey !== "system" && !rows.some(row => row.key === selectedKey)) selectedKey = "system";
        if (picker.visible && !pickerForSystem && !pickerGroup) picker.close();
    }

    function buildRows(): var {
        const tokens = query.toLocaleLowerCase().replace(/ё/g, "е").trim().split(/\s+/).filter(Boolean);
        const result = [];
        for (const group of audio.groups) {
            const name = (group.name + " " + group.nodes.map(node => audio.streamLabel(node)).join(" "))
                .toLocaleLowerCase().replace(/ё/g, "е");
            if (!tokens.every(token => name.includes(token))) continue;
            result.push({ key: group.key, group: group, node: null });
            if (expanded[group.key]) {
                for (const node of group.nodes) result.push({ key: group.key + "/" + audio.nodeKey(node), group: group, node: node });
            }
        }
        return result;
    }
    function reset(): void {
        picker.close();
        selectedKey = "system";
        expanded = {};
        list.positionViewAtBeginning();
    }
    function moveSelection(delta: int): void {
        const index = rows.findIndex(row => row.key === selectedKey);
        const next = (index + 1 + delta + rows.length + 1) % (rows.length + 1) - 1;
        selectedKey = next < 0 ? "system" : rows[next].key;
        if (next >= 0) list.positionViewAtIndex(next, ListView.Contain);
    }
    function expand(group: var): void {
        if (!group) return;
        const next = Object.assign({}, expanded);
        next[group.key] = !next[group.key];
        expanded = next;
    }
    function changeVolume(delta: real): void {
        if (selectedKey === "system") {
            if (audio.usable(audio.defaultOutput)) audio.setNodeVolume(audio.defaultOutput, audio.defaultOutput.audio.volume + delta);
        } else if (selectedRow) {
            if (selectedRow.node) audio.setNodeVolume(selectedRow.node, selectedRow.node.audio.volume + delta);
            else audio.setVolume(selectedRow.group, audio.volume(selectedRow.group.nodes) + delta);
        }
    }
    function toggleMute(): void {
        if (selectedKey === "system") audio.toggleMute([audio.defaultOutput]);
        else if (selectedRow) audio.toggleMute(selectedRow.node ? [selectedRow.node] : selectedRow.group.nodes);
    }
    function openPicker(group: var): void {
        if (!audio.ready || !audio.outputs.length) return;
        if (group && (!router.available || router.pending)) return;
        pickerGroupKey = group ? group.key : "";
        const current = group ? audio.targets(group.nodes[0])[0] : audio.defaultOutput;
        devices.currentIndex = Math.max(0, audio.outputs.indexOf(current));
        picker.open();
        devices.forceActiveFocus();
    }
    function pickerKey(event: var): void {
        if (event.key === Qt.Key_Escape) picker.close();
        else if ([Qt.Key_Up, Qt.Key_Left, Qt.Key_Down, Qt.Key_Right].includes(event.key)) {
            const delta = event.key === Qt.Key_Up || event.key === Qt.Key_Left ? -1 : 1;
            if (devices.count) devices.currentIndex = (devices.currentIndex + delta + devices.count) % devices.count;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) chooseOutput(devices.currentIndex);
        else return;
        event.accepted = true;
    }
    function chooseOutput(index: int): void {
        if (index < 0 || index >= audio.outputs.length) return;
        if (pickerForSystem) audio.setDefaultOutput(audio.outputs[index]);
        else if (pickerGroup) router.move(pickerGroup, audio.outputs[index]);
        else return;
        picker.close();
    }

    AudioControls {
        id: system
        anchors.top: parent.top
        width: parent.width
        theme: root.theme
        keyHandler: root.keyHandler
        title: "Системная громкость"
        subtitle: "По умолчанию · " + root.audio.label(root.audio.defaultOutput)
        selected: root.selectedKey === "system"
        available: root.audio.usable(root.audio.defaultOutput)
        volume: available ? root.audio.defaultOutput.audio.volume : 0
        muteState: root.audio.muteState([root.audio.defaultOutput])
        onSelectedByUser: root.selectedKey = "system"
        onVolumeEdited: value => root.audio.setNodeVolume(root.audio.defaultOutput, value)
        onMuteClicked: root.audio.toggleMute([root.audio.defaultOutput])
    }
    Button {
        id: systemOutputButton
        objectName: "systemOutputButton"
        anchors.top: system.bottom
        width: parent.width
        height: 24
        enabled: root.audio.ready && root.audio.outputs.length > 0
        text: "Устройство по умолчанию ▾"
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallFontSize
        contentItem: Text {
            text: systemOutputButton.text
            font: systemOutputButton.font
            color: systemOutputButton.enabled ? root.theme.textMuted : root.theme.border
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
        }
        background: Rectangle {
            radius: root.theme.radius / 2
            color: systemOutputButton.down || systemOutputButton.hovered ? root.theme.surface : root.theme.transparent
            border.color: systemOutputButton.activeFocus ? root.theme.accent : root.theme.transparent
        }
        onClicked: { root.selectedKey = "system"; root.openPicker(null); }
        onActiveFocusChanged: if (activeFocus) root.selectedKey = "system"
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => root.keyHandler(event)
        Accessible.name: "Устройство вывода по умолчанию"
    }
    ListView {
        id: list
        anchors.top: systemOutputButton.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        spacing: 2
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        delegate: Column {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width
            AudioControls {
                width: parent.width - (row.modelData.node ? 18 : 0)
                x: row.modelData.node ? 18 : 0
                theme: root.theme
                keyHandler: root.keyHandler
                title: row.modelData.node ? root.audio.streamLabel(row.modelData.node) : row.modelData.group.name
                icon: row.modelData.node ? "" : row.modelData.group.icon
                selected: root.selectedKey === row.modelData.key
                expandable: !row.modelData.node
                expanded: !!root.expanded[row.modelData.group.key]
                volume: root.audio.volume(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
                muteState: root.audio.muteState(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
                subtitle: muteState === "mixed" ? "Частично заглушено" : row.modelData.node ? root.audio.outputLabel([row.modelData.node]) : ""
                onSelectedByUser: root.selectedKey = row.modelData.key
                onExpandClicked: root.expand(row.modelData.group)
                onVolumeEdited: value => {
                    if (row.modelData.node) root.audio.setNodeVolume(row.modelData.node, value);
                    else root.audio.setVolume(row.modelData.group, value);
                }
                onMuteClicked: root.audio.toggleMute(row.modelData.node ? [row.modelData.node] : row.modelData.group.nodes)
            }
            Button {
                id: outputButton
                width: parent.width
                height: visible ? 24 : 0
                visible: !row.modelData.node
                enabled: root.router.available && !root.router.pending && root.audio.outputs.length > 0
                flat: true
                text: root.audio.outputLabel(row.modelData.group.nodes) + " ▾"
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                palette.buttonText: root.theme.textMuted
                contentItem: Text {
                    text: outputButton.text
                    font: outputButton.font
                    color: outputButton.enabled ? root.theme.textMuted : root.theme.border
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 34
                }
                onClicked: { root.selectedKey = row.modelData.key; root.openPicker(row.modelData.group); }
                onActiveFocusChanged: if (activeFocus) root.selectedKey = row.modelData.key
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
                ToolTip.visible: hovered
                ToolTip.text: root.router.unavailableReason || text
                Accessible.name: row.modelData.group.name + ": устройство вывода"
            }
            Text {
                width: parent.width
                height: visible ? implicitHeight + 6 : 0
                visible: !row.modelData.node && root.router.groupKey === row.modelData.group.key && root.router.message !== ""
                text: root.router.message
                color: root.theme.accent
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallFontSize
                wrapMode: Text.Wrap
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: list.count === 0
            text: !root.audio.ready ? "PipeWire недоступен" : root.query.trim() ? "Ничего не найдено" : "Нет звуковых приложений"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSize
        }
    }
    Popup {
        id: picker
        objectName: "outputPicker"
        anchors.centerIn: parent
        width: Math.min(420, root.width - 20)
        height: Math.min(240, root.height)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: root.theme.shadow }
        background: Rectangle { color: root.theme.background; radius: 10; border.color: root.theme.accent }
        contentItem: ListView {
            id: devices
            clip: true
            model: root.audio.outputs
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => root.keyHandler(event)
            onCountChanged: currentIndex = Math.min(Math.max(0, currentIndex), count - 1)
            delegate: ItemDelegate {
                id: device
                required property var modelData
                required property int index
                width: ListView.view.width
                text: root.audio.label(modelData)
                highlighted: devices.currentIndex === index
                background: Rectangle {
                    color: device.highlighted || device.hovered ? root.theme.surface : root.theme.background
                    radius: root.theme.radius / 2
                }
                contentItem: Text {
                    text: device.text
                    font: device.font
                    color: device.highlighted ? root.theme.accent : root.theme.text
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                font.family: root.theme.fontFamily
                onClicked: root.chooseOutput(index)
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.keyHandler(event)
            }
            Text {
                anchors.centerIn: parent
                visible: devices.count === 0
                text: "Нет доступных выходов"
                color: root.theme.textMuted
            }
        }
    }
}
