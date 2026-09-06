import Quickshell
import Quickshell.Io

ShellRoot {
    Launcher { id: launcher }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle(); }
        function open(): void { launcher.open(); }
        function close(): void { launcher.close(); }
        function status(): string { return launcher.status(); }
    }
}
