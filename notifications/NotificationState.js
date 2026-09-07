// The state machine has no Qt objects. Native notification lifetimes and disk
// writes are supplied by the controller, so timing and deletion are testable.
function create(options) {
    const state = {
        records: [], dnd: false, lock: "unknown", screens: [], activeScreen: "",
        serial: 0, epoch: String(options.now()), error: "", drafts: {},
        now: options.now, closeLive: options.closeLive,
        changed: options.changed || function() {},
        maxRecords: 500, maxAge: 7 * 86400000, maxTransient: 100
    };
    state.find = key => state.records.find(row => row.key === key);
    state.allowed = () => !state.dnd && state.lock === "unlocked";
    state.timeout = data => data.urgency === 2 || data.timeout === 0 ? -1 : data.timeout < 0 ? 5000 : data.timeout;
    state.pump = () => {
        if (!state.allowed()) return;
        let available = Math.max(0, 3 - state.records.filter(row => row.popup === "visible").length);
        if (!state.screens.length) return;
        for (const row of state.records.filter(row => row.popup === "queued").sort((a,b) => a.queuedAt - b.queuedAt)) {
            if (!available--) break;
            row.popup = "visible";
            row.screen = state.screens.includes(state.activeScreen) ? state.activeScreen : state.screens[0];
        }
    };
    state.receive = (id, data) => {
        let row = state.records.find(item => item.liveId === id);
        const isNew = !row;
        if (!row) {
            row = { key: state.epoch + "-" + (++state.serial), liveId: id, unread: true,
                popup: state.allowed() ? "queued" : "suppressed", queuedAt: state.now(),
                screen: "", hovered: false, replying: false };
            state.records.push(row);
        }
        Object.assign(row, data, { updated: state.now(), remaining: state.timeout(data) });
        // Replacement updates content but never revives a suppressed popup.
        if (row.transient && row.popup === "suppressed") state.remove([row.key]);
        else {
            state.prune();
            const temporary = state.records.filter(item => item.transient);
            if (temporary.length > state.maxTransient)
                state.remove(temporary.slice(0, temporary.length - state.maxTransient).map(item => item.key));
            state.pump(); state.changed();
        }
        return { key: row.key, isNew: isNew };
    };
    state.closed = (key, read) => {
        const row = state.find(key);
        if (!row) return;
        row.liveId = null; row.popup = "none"; row.actions = []; row.reply = false;
        row.replying = false; row.hovered = false;
        if (read) row.unread = false;
        if (row.transient) {
            state.records = state.records.filter(item => item !== row);
            delete state.drafts[key];
        }
        state.pump(); state.changed();
    };
    state.dismiss = (key, expired) => {
        const row = state.find(key);
        if (!row) return;
        const id = row.liveId;
        state.closed(key, true);
        if (id !== null) state.closeLive(id, expired ? "expire" : "dismiss");
    };
    state.remove = keys => {
        const removed = state.records.filter(row => keys.includes(row.key));
        state.records = state.records.filter(row => !keys.includes(row.key));
        for (const row of removed) {
            delete state.drafts[row.key];
            if (row.liveId !== null) state.closeLive(row.liveId, "dismiss");
        }
        state.pump(); state.changed();
    };
    state.prune = () => {
        const rows = state.records.filter(row => !row.transient).sort((a,b) => b.updated - a.updated);
        const expired = rows.filter((row, index) => index >= state.maxRecords || row.updated < state.now() - state.maxAge);
        if (expired.length) state.remove(expired.map(row => row.key));
    };
    state.suppress = () => {
        for (const row of state.records) {
            if (row.popup === "visible" || row.popup === "queued") row.popup = "suppressed";
            row.replying = false; row.hovered = false;
        }
        state.remove(state.records.filter(row => row.transient).map(row => row.key));
        state.changed();
    };
    state.setDnd = value => { state.dnd = value; if (value) state.suppress(); state.changed(); };
    state.setLock = value => { state.lock = value; if (value !== "unlocked") state.suppress(); state.changed(); };
    state.setScreens = (names, active) => {
        state.screens = names; state.activeScreen = active;
        for (const row of state.records) {
            if (row.popup === "visible" && !names.includes(row.screen)) {
                row.screen = names.includes(active) ? active : names[0] || "";
            }
        }
        state.pump(); state.changed();
    };
    state.tick = elapsed => {
        if (!state.allowed()) return;
        const expired = [];
        for (const row of state.records) {
            if (row.popup !== "visible" || !row.screen || row.hovered || row.replying || row.remaining < 0) continue;
            row.remaining -= elapsed;
            if (row.remaining <= 0) expired.push(row.key);
        }
        expired.forEach(key => state.dismiss(key, true));
    };
    state.snapshot = () => ({ version: 1, dnd: state.dnd,
        records: state.records.filter(row => !row.transient).map(row => ({
            key: row.key, app: row.app, group: row.group, icon: row.icon,
            summary: row.summary, body: row.body, image: row.image,
            updated: row.updated, unread: row.unread, urgency: row.urgency
        })) });
    state.restore = text => {
        if (!text) return;
        try {
            const saved = JSON.parse(text);
            if (saved.version !== 1 || !Array.isArray(saved.records) || typeof saved.dnd !== "boolean") throw new Error("format");
            const seen = new Set();
            state.records = saved.records.filter(row => row && typeof row.key === "string"
                && typeof row.app === "string" && typeof row.group === "string"
                && typeof row.summary === "string" && typeof row.body === "string"
                && Number.isFinite(row.updated) && !seen.has(row.key) && seen.add(row.key))
                .map(row => ({ key: row.key, app: row.app, group: row.group, summary: row.summary,
                    body: row.body, updated: row.updated, icon: typeof row.icon === "string" ? row.icon : "",
                    image: typeof row.image === "string" ? row.image : "", unread: !!row.unread,
                    urgency: row.urgency === 2 ? 2 : 1, transient: false, liveId: null,
                    popup: "none", actions: [], reply: false, remaining: -1, screen: "" }));
            state.dnd = saved.dnd;
            state.prune();
        } catch (_) { state.error = "Не удалось прочитать историю уведомлений"; }
    };
    return state;
}
function groups(records, query, unreadOnly) {
    const needle = query.trim().toLocaleLowerCase();
    const result = [];
    for (const row of records.filter(row => !row.transient).sort((a,b) => b.updated - a.updated)) {
        if (unreadOnly && !row.unread) continue;
        if (needle && !(row.app + " " + row.summary + " " + row.body).toLocaleLowerCase().includes(needle)) continue;
        let group = result.find(item => item.key === row.group);
        if (!group) { group = { key: row.group, app: row.app, rows: [] }; result.push(group); }
        group.rows.push(row);
    }
    return result;
}
if (typeof module !== "undefined") module.exports = { create, groups };
