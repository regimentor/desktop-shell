//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
import QtQuick
import Quickshell
import Quickshell.Io
import "desktop" as Desktop
import "bar" as Bar
import "launcher" as Launcher

ShellRoot {
    id: root
    Desktop.DesktopState { id: desktopState }
    Bar.BarRuntime { desktop: desktopState }
    Loader {
        id: notificationRuntime
        active: Quickshell.env("DAEVOX_NOTIFICATIONS") === "1"
        Component.onCompleted: if (active) setSource(Qt.resolvedUrl("notifications/NotificationRuntime.qml"), {desktop: desktopState})
    }
    Launcher.Launcher {
        id: launcher
        desktop: desktopState
        notifications: notificationRuntime.item ? notificationRuntime.item.model : null
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle(); }
        function open(): void { launcher.open(); }
        function close(): void { launcher.close(); }
        function notifications(): void { launcher.openMode("notifications"); }
        function status(): string { return launcher.status(); }
    }
}
