// Read-only, windowless probe. No dispatch, focus changes, or full window titles in logs.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root
    Component.onCompleted: {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }
    function typeName(object) {
        return object ? String(object).split("(")[0] : null;
    }
    function describe(window) {
        const ipc = window.lastIpcObject || {};
        const wayland = window.wayland;
        return {
            type: typeName(window),
            isHyprlandToplevel: window instanceof HyprlandToplevel,
            addressPresent: typeof window.address === "string" && window.address.length > 0,
            titleType: typeof window.title,
            workspaceType: typeName(window.workspace),
            monitorType: typeName(window.monitor),
            directAppIdType: typeof window.appId,
            ipcClass: ipc["class"] || null,
            ipcInitialClass: ipc.initialClass || null,
            waylandType: typeName(wayland),
            waylandAppId: wayland ? wayland.appId : null,
            attachedMatches: wayland ? wayland.HyprlandToplevel.handle === window : null,
            presentInWorkspace: window.workspace
                ? window.workspace.toplevels.values.indexOf(window) >= 0 : false
        };
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            Hyprland.refreshMonitors();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
        }
    }
    Timer {
        interval: 4000
        running: true
        onTriggered: {
            const windows = Hyprland.toplevels.values;
            const workspaces = Hyprland.workspaces.values;
            const monitors = Hyprland.monitors.values;
            const result = {
                usingLua: Hyprland.usingLua,
                requestSocketPresent: Hyprland.requestSocketPath.length > 0,
                eventSocketPresent: Hyprland.eventSocketPath.length > 0,
                count: windows.length,
                workspaceCount: workspaces.length,
                monitorCount: monitors.length,
                activeType: root.typeName(Hyprland.activeToplevel),
                activeInModel: windows.indexOf(Hyprland.activeToplevel) >= 0,
                screenMappings: Quickshell.screens.map(screen => ({
                    mapped: Hyprland.monitorFor(screen) !== null,
                    activeWorkspacePresent: Hyprland.monitorFor(screen)
                        ? Hyprland.monitorFor(screen).activeWorkspace !== null : false
                })),
                windows: windows.map(window => root.describe(window))
            };
            console.log("BAR_MODEL_PROBE " + JSON.stringify(result));
            Qt.quit();
        }
    }
    Timer { interval: 6000; running: true; onTriggered: Qt.quit() }
}
