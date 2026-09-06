import QtQuick
import Quickshell
import "runtime"

ShellRoot {
    HyprlandState {
        id: state
        property bool sentCommand: false
        socketDirectory: Quickshell.env("BAR_TEST_SOCKET_DIR") || (Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
        timeoutMs: 350
        onErrorChanged: if (error) console.log("PROBE_ERROR", error)
        onReadyChanged: {
            console.log("PROBE_READY", ready);
            if (ready && Quickshell.env("BAR_TEST_COMMAND") && !sentCommand) {
                sentCommand = true;
                nextLayout();
            }
        }
        onDataChanged: if (data.monitors.length) console.log("PROBE_DATA", JSON.stringify({ monitors: data.monitors.length, clients: data.clients.length, language: language, title: Quickshell.env("BAR_TEST_SOCKET_DIR") ? title("DP-1") : "" }))
    }
    Timer { interval: 2500; running: true; onTriggered: { console.log("PROBE_FINAL", state.ready); if (Quickshell.env("BAR_TEST_SOCKET_DIR")) console.log("PROBE_TITLE", state.title("DP-1")); Qt.quit(); } }
}
