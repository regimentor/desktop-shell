import QtQuick
import Quickshell
import Daevox.Notifications 1.0 as Native
import "NotificationState.js" as State

Scope {
    id: root
    property var records: []
    property bool dnd: false
    property string lockState: "unknown"
    property string error: ""
    property var engine: null
    readonly property bool ready: server.ready
    property bool initialized: false
    property bool storageEnabled: true
    readonly property bool blocked: lockState !== "unlocked"
    signal requestFocusReturn()
    Native.ArchiveFiles { id: files }
    Native.LockObserver { id: lock; onStateChanged: if (root.engine) root.engine.setLock(state) }
    Native.NotificationEndpoint {
        id: server
        onNotified: (id, data) => root.engine.receive(id, data)
        onClosed: (id, reason) => {
            const row = root.engine.records.find(item => item.liveId === id);
            if (row) root.engine.closed(row.key, reason === 1 || reason === 2);
        }
        onActionsUnavailable: id => {
            const row = root.engine.records.find(item => item.liveId === id);
            if (row) { row.actions = []; row.reply = false; row.replying = false; root.refresh(); }
        }
        onUnavailable: reason => root.error = reason
    }
    Component.onCompleted: {
        engine = State.create({ now: () => Date.now(), closeLive: root.closeLive, changed: root.refresh });
        if (storageEnabled) engine.restore(files.load());
        initialized = true;
        engine.setLock(lock.state);
        refresh();
    }
    Component.onDestruction: { if (initialized && storageEnabled) files.save(JSON.stringify(engine.snapshot())); }
    function refresh(): void {
        if (!engine || !initialized) return;
        records = engine.records.slice();
        dnd = engine.dnd;
        lockState = engine.lock;
        if (engine.error) error = engine.error;
        save.restart();
    }
    Timer {
        id: save; interval: 100
        onTriggered: if (root.storageEnabled && !files.save(JSON.stringify(root.engine.snapshot())))
            root.error = "Не удалось сохранить историю уведомлений"
    }
    Timer {
        interval: 100; running: root.initialized; repeat: true
        property double previous: Date.now()
        onTriggered: { const now = Date.now(); root.engine.tick(Math.max(0, now - previous)); previous = now; }
    }
    Timer { interval: 60000; repeat: true; running: root.initialized; onTriggered: root.engine.prune() }
    function closeLive(id: int, reason: string): void {
        server.close(id, reason === "expire" ? 1 : 2);
    }
    function toggleDnd(): void { engine.setDnd(!engine.dnd); }
    function remove(key: string): void { engine.remove([key]); }
    function removeGroup(group: string): void { engine.remove(engine.records.filter(row => row.group === group && !row.transient).map(row => row.key)); }
    function clear(): void { engine.remove(engine.records.filter(row => !row.transient).map(row => row.key)); }
    function dismiss(key: string): void { engine.dismiss(key, false); }
    function invoke(key: string, actionId: string): bool {
        const row = engine.find(key);
        return !!row && row.liveId !== null && server.invoke(row.liveId, actionId);
    }
    function reply(key: string, text: string): void {
        const row = engine.find(key);
        if (!row || row.liveId === null || !text.trim()) return;
        if (!server.reply(row.liveId, text)) return;
        engine.drafts[key] = "";
        if (engine.find(key)) engine.find(key).replying = false;
        refresh(); requestFocusReturn();
    }
    function draft(key: string): string { return engine.drafts[key] || ""; }
    function setDraft(key: string, text: string): void { engine.drafts[key] = text; }
    function setReplying(key: string, value: bool): void {
        const row = engine.find(key); if (row) row.replying = value;
    }
    function setHovered(key: string, value: bool): void {
        const row = engine.find(key); if (row) row.hovered = value;
    }
    function setScreens(names: var, active: string): void { if (engine) engine.setScreens(names, active); }
}
