import QtQuick
import QtTest
import Quickshell
import "../../launcher"

ShellRoot {
    id: root
    property int tick: 0
    property bool failed: false
    QtObject {
        id: desktop
        property string language: "EN"
        function screenFor(screens) { return screens[0] || null; }
    }
    Launcher { id: launcher; desktop: desktop }
    TestCase { id: tester; name: "LauncherMotion"; when: false }
    function check(condition, message) {
        if (!condition) {
            failed = true;
            console.error("MOTION_FAIL", message);
        }
    }
    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            root.tick++;
            if (root.tick === 1) launcher.open();
            if (root.tick === 3) {
                root.check(launcher.visible && launcher.opened, "opening is visible");
                root.check(launcher.reveal > 0, "entry advances");
                const grab = tester.findChild(launcher, "launcherFocusGrab");
                root.check(grab !== null, "outside-click grab exists during entry");
                if (grab) {
                    root.check(grab.active, "outside-click grab is active during entry");
                    // Exercise the compositor's outside-click notification boundary.
                    grab.cleared();
                }
                root.check(!launcher.opened, "outside click closes during entry");
                root.check(launcher.visible, "exit keeps the surface alive");
            }
            if (root.tick === 4) launcher.toggle();
            if (root.tick === 12) {
                root.check(launcher.opened && launcher.visible && launcher.reveal === 1, "toggle reverses closing");
                launcher.close();
            }
            if (root.tick === 13) launcher.toggle();
            if (root.tick === 21) {
                root.check(launcher.opened && launcher.reveal === 1, "reopen after an established focus grab");
                launcher.switchMode("audio");
            }
            if (root.tick === 23) {
                launcher.switchMode("apps");
            }
            if (root.tick === 30) {
                root.check(launcher.mode === "apps" && launcher.modeReveal === 1, "rapid mode changes settle");
                tester.findChild(launcher, "launcherFocusGrab").cleared();
                root.check(!launcher.opened, "outside click closes after mode changes");
            }
            if (root.tick === 36) {
                root.check(!launcher.visible && launcher.reveal === 0, "normal exit unmaps the window");
                launcher.open();
            }
            if (root.tick === 39) {
                launcher.closeImmediately();
                root.check(!launcher.visible && !launcher.opened && launcher.reveal === 0, "immediate close skips animation");
                if (!root.failed) console.log("MOTION_PASS");
                Qt.quit();
            }
        }
    }
}
