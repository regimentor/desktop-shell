import QtQuick
import QtTest
import Quickshell
import "../../launcher"
import "../../desktop"

ShellRoot {
    id: root
    DesktopState { id: desktopState }
    Launcher { desktop: desktopState; id: launcher }
    TestCase { id: tester; name: "Audio UI"; parent: launcher.contentItem; when: false }
    property int stage: 0
    property int ticks: 0
    property var pane: null
    property var search: null
    property var slider: null
    property real oldVolume: 0
    property var chosenOutput: null
    property size initialSize: Qt.size(0, 0)
    function check(condition: bool, label: string): void {
        if (!condition) throw new Error("FAIL " + label);
    }
    Component.onCompleted: launcher.open()
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            try {
                root.check(++root.ticks < 100, "UI timeout at stage " + root.stage);
                if (root.stage > 0 && launcher.visible)
                    root.check(launcher.width === root.initialSize.width && launcher.height === root.initialSize.height,
                        "window size stays unchanged across tabs, search, expansion and reopening");
                if (root.stage === 0) {
                    root.pane = tester.findChild(launcher.contentItem, "audioPane");
                    root.search = tester.findChild(launcher.contentItem, "launcherSearch");
                    if (!root.pane || !root.pane.audio.groups.length) return;
                    root.check(launcher.mode === "apps" && root.search.text === "", "open Apps and empty search");
                    root.initialSize = Qt.size(launcher.width, launcher.height);
                    tester.keyClick(Qt.Key_2, Qt.AltModifier);
                } else if (root.stage === 1) {
                    root.check(launcher.mode === "audio" && root.pane.selectedKey === "system", "Alt+2");
                    const layout = tester.findChild(launcher.contentItem, "keyboardLayoutIndicator");
                    root.check(layout && layout.text !== "—" && layout.text.length > 0, "current keyboard layout is displayed");
                    const appsTab = tester.findChild(launcher.contentItem, "mode-apps");
                    const volumeTab = tester.findChild(launcher.contentItem, "mode-audio");
                    const panel = tester.findChild(launcher.contentItem, "launcherPanel");
                    root.check(appsTab.mapToItem(launcher.contentItem, 0, 0).x === panel.x, "tabs align with panel left edge");
                    root.check(volumeTab.text === "" && volumeTab.label === "Звук", "icon-only Volume tab with accessible label");
                    tester.keyClick(Qt.Key_O, Qt.AltModifier);
                    root.check(root.pane.pickerOpen, "system output picker opens");
                    root.chosenOutput = root.pane.audio.outputs.find(output => output !== root.pane.audio.defaultOutput);
                    root.pane.chooseOutput(root.pane.audio.outputs.indexOf(root.chosenOutput));
                    root.check(!root.pane.pickerOpen, "system picker closes after choice");
                } else if (root.stage === 2) {
                    root.check(root.pane.audio.defaultOutput === root.chosenOutput, "system picker changes default output");
                    tester.mouseClick(tester.findChild(root.pane, "systemOutputButton"));
                    root.check(root.pane.pickerOpen, "system output button opens picker");
                    const picker = tester.findChild(root.pane, "outputPicker");
                    root.check(picker.contentItem.currentIndex === root.pane.audio.outputs.indexOf(root.chosenOutput), "picker selects current default");
                    tester.keyClick(Qt.Key_Escape);
                    root.search.forceActiveFocus();
                    root.oldVolume = root.pane.audio.defaultOutput.audio.volume;
                    tester.keyClick(Qt.Key_Left);
                } else if (root.stage === 3) {
                    root.check(Math.abs(root.pane.audio.defaultOutput.audio.volume - Math.max(0, root.oldVolume - 0.05)) < 0.002, "arrow from search changes default volume");
                    root.search.forceActiveFocus();
                    tester.keyClick(Qt.Key_Z);
                    tester.keyClick(Qt.Key_Z);
                } else if (root.stage === 4) {
                    root.check(root.search.text === "zz" && root.pane.rows.length === 0, "search empty results");
                    tester.keyClick(Qt.Key_Escape);
                } else if (root.stage === 5) {
                    root.check(launcher.visible && root.search.text === "", "Escape clears query");
                    tester.keyClick(Qt.Key_Down);
                    tester.keyClick(Qt.Key_Return);
                } else if (root.stage === 6) {
                    root.check(root.pane.rows.length === 3, "Enter expands two streams");
                    tester.keyClick(Qt.Key_O, Qt.AltModifier);
                } else if (root.stage === 7) {
                    root.check(root.pane.pickerOpen, "output picker opens");
                    const picker = tester.findChild(root.pane, "outputPicker");
                    root.check(picker.background.color.toString() === root.pane.theme.background.toString(), "picker uses application background");
                    const item = picker.contentItem.itemAtIndex(1 - picker.contentItem.currentIndex);
                    root.check(item && item.background.color.toString() === root.pane.theme.background.toString(), "unselected output uses application background");
                    root.oldVolume = root.pane.audio.volume(root.pane.selectedGroup.nodes);
                    tester.keyClick(Qt.Key_Left);
                    tester.keyClick(Qt.Key_Escape);
                } else if (root.stage === 8) {
                    root.check(!root.pane.pickerOpen && launcher.visible, "Escape closes only picker");
                    root.check(root.oldVolume === root.pane.audio.volume(root.pane.selectedGroup.nodes), "picker arrows do not change volume");
                    root.slider = tester.findChild(root.pane, "volumeSlider");
                    root.slider.forceActiveFocus();
                    tester.keyClick(Qt.Key_1, Qt.AltModifier);
                } else if (root.stage === 9) {
                    root.check(launcher.mode === "apps", "Alt+1 from slider focus");
                    tester.mouseClick(tester.findChild(launcher.contentItem, "mode-audio"));
                } else if (root.stage === 10) {
                    root.check(launcher.mode === "audio", "cloud click");
                    root.slider = tester.findChild(root.pane, "volumeSlider");
                    tester.mousePress(root.slider, root.slider.width * 0.25, root.slider.height / 2);
                    tester.mouseMove(root.slider, root.slider.width * 0.6, root.slider.height / 2, 50);
                    tester.mouseRelease(root.slider, root.slider.width * 0.6, root.slider.height / 2);
                } else if (root.stage === 11) {
                    const volume = root.pane.audio.defaultOutput.audio.volume;
                    root.check(volume > 0.5 && volume < 0.7, "mouse slider drag");
                    root.search.forceActiveFocus();
                    tester.keyClick(Qt.Key_Tab);
                    root.check(!root.search.activeFocus, "Tab visits controls");
                    tester.keyClick(Qt.Key_Escape);
                } else if (root.stage === 12) {
                    root.check(!launcher.visible, "Escape closes empty launcher");
                    launcher.open();
                } else if (root.stage === 13) {
                    root.check(launcher.mode === "apps" && root.search.text === "", "reopen resets mode");
                    launcher.switchMode("audio");
                    root.pane.expand(root.pane.audio.groups[0]);
                } else if (root.stage === 14) {
                    tester.findChild(launcher.contentItem, "launcherPanel").grabToImage(result => {
                        result.saveToFile(Quickshell.env("DAEVOX_AUDIO_TEST_DIR") + "/audio-ui.png");
                        console.log("AUDIO UI PASS: focus, mode shortcuts, search, Escape, tree, picker, cloud click, slider drag, Tab");
                        launcher.close();
                        Qt.quit();
                    });
                }
                root.stage++;
            } catch (error) {
                console.error(String(error));
                launcher.close();
                Qt.quit();
            }
        }
    }
}
