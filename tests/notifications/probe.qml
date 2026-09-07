import QtQuick
import Quickshell
import Quickshell.Io
import "../../notifications"

ShellRoot {
    NotificationModel {
        id: model
        onInitializedChanged: if (initialized) Qt.callLater(() => { engine.setLock("unlocked"); setScreens(["test"], "test"); })
    }
    IpcHandler {
        target: "test"
        function state(): string { return JSON.stringify({records:model.records,dnd:model.dnd,error:model.error}); }
        function dnd(): void { model.toggleDnd(); }
        function invoke(key: string, action: string): void { model.invoke(key, action); }
        function reply(key: string, text: string): void { model.reply(key,text); }
        function dismiss(key: string): void { model.dismiss(key); }
        function remove(key: string): void { model.remove(key); }
        function quit(): void { Qt.quit(); }
    }
}
