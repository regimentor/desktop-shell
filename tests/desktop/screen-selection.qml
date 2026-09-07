import QtQuick
import Quickshell
import "runtime"

ShellRoot {
    DesktopState { id: desktop; socketDirectory: "/tmp/daevox-screen-test-no-peer" }
    Component.onCompleted: {
        const screens = [{name: "DP-3"}, {name: "DP-2"}];
        function check(value, label) { if (!value) throw new Error("SCREEN_FAIL " + label); }
        check(desktop.screenFor([]) === null, "no screens");
        check(desktop.screenFor(screens) === screens[1], "deterministic disconnected fallback");
        desktop.data = {monitors: [{name: "DP-3", focused: true}], keyboard: null};
        desktop.ready = true;
        check(desktop.activeMonitor === "DP-3", "focused monitor interface");
        check(desktop.screenFor(screens) === screens[0], "active monitor selected");
        check(desktop.screenFor([screens[1]]) === screens[1], "removed monitor excluded");
        desktop.ready = false;
        check(desktop.activeMonitor === "", "unavailable monitor cleared");
        check(desktop.screenFor(screens) === screens[1], "fallback after disconnect");
        console.log("SCREEN_PASS focus, disconnect, removed monitor, deterministic fallback, no screens");
        Qt.callLater(Qt.quit);
    }
}
