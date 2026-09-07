import Quickshell
import Quickshell.Io
import Daevox.Notifications 1.0
ShellRoot {
    LockObserver { id: observer }
    IpcHandler {
        target: "test"
        function state(): string { return JSON.stringify({lock: observer.state}); }
    }
}
