.pragma library

function empty() {
    return { monitors: [], workspaces: [], clients: [], active: "", keyboard: null, history: {}, urgent: {} };
}
function validate(s) {
    if (!s.version || typeof s.version.version !== "string" || !/^0\.56\.2(?:$|[-+])/.test(s.version.version))
        throw new Error("Requires Hyprland 0.56.2");
    if (!Array.isArray(s.monitors) || !Array.isArray(s.workspaces) || !Array.isArray(s.clients)
        || !s.devices || !Array.isArray(s.devices.keyboards) || !s.activewindow || typeof s.activewindow !== "object" || Array.isArray(s.activewindow))
        throw new Error("Invalid snapshot schema");
    if (s.monitors.some(m => typeof m.name !== "string" || !m.activeWorkspace || !m.specialWorkspace
            || typeof m.activeWorkspace.id !== "number" || typeof m.specialWorkspace.id !== "number")
        || s.workspaces.some(w => typeof w.id !== "number" || typeof w.monitor !== "string" || typeof w.name !== "string")
        || s.clients.some(c => typeof c.address !== "string" || !c.workspace || typeof c.workspace.id !== "number" || typeof c.title !== "string"))
        throw new Error("Invalid monitor/workspace/window schema");
    if (s.devices.keyboards.some(k => !k || typeof k.name !== "string"))
        throw new Error("Invalid keyboard schema");
}
function focus(history, workspace, address) {
    history[workspace] = (history[workspace] || []).filter(a => a !== address).concat(address);
}
function reconcile(previous, s, events) {
    validate(s);
    const addresses = s.clients.map(c => c.address);
    const order = previous.clients.map(c => c.address).filter(a => addresses.includes(a));
    for (const event of events) {
        if (event.name === "openwindow" && addresses.includes(event.address) && !order.includes(event.address)) order.push(event.address);
    }
    for (const a of addresses) if (!order.includes(a)) order.push(a);
    const clients = order.map(a => s.clients.find(c => c.address === a));
    const history = {}, urgent = {};
    for (const w of s.workspaces) {
        const own = clients.filter(c => c.workspace.id === w.id).map(c => c.address);
        history[w.id] = (previous.history[w.id] || []).filter(a => own.includes(a));
        if (!history[w.id].length && own.includes(w.lastwindow)) focus(history, w.id, w.lastwindow);
    }
    for (const a of Object.keys(previous.urgent)) if (addresses.includes(a)) urgent[a] = true;
    for (const event of events) {
        const c = clients.find(c => c.address === event.address);
        if (event.name === "urgent" && c) urgent[c.address] = true;
        if (event.name === "activewindowv2" && c) { focus(history, c.workspace.id, c.address); delete urgent[c.address]; }
    }
    const active = clients.find(c => c.address === s.activewindow.address);
    if (active) { focus(history, active.workspace.id, active.address); delete urgent[active.address]; }
    return { monitors: s.monitors, workspaces: s.workspaces, clients: clients,
        active: active ? active.address : "", keyboard: s.devices.keyboards.find(k => k.main) || s.devices.keyboards[0] || null,
        history: history, urgent: urgent };
}
function groups(state, output) {
    const monitor = state.monitors.find(m => m.name === output);
    if (!monitor) return [];
    const workspaces = state.workspaces.filter(w => w.monitor === output).slice();
    if (!workspaces.some(w => w.id === monitor.activeWorkspace.id))
        workspaces.push({ id: monitor.activeWorkspace.id, name: monitor.activeWorkspace.name, monitor: output });
    const result = workspaces.map(w => ({ id: w.id, name: w.name, special: w.id < 0,
        active: w.id === monitor.activeWorkspace.id || w.id === monitor.specialWorkspace.id,
        windows: state.clients.filter(c => c.workspace.id === w.id) }))
        .filter(w => !w.special || w.active || w.windows.length)
        .sort((a, b) => Number(a.special) - Number(b.special) || a.id - b.id);
    const specialCount = result.filter(w => w.special).length;
    return result.map(w => Object.assign({}, w, { label: w.special ? (specialCount === 1 ? "S" : w.name.replace(/^special:/, "")) : String(w.id) }));
}
function title(state, output) {
    const monitor = state.monitors.find(m => m.name === output);
    if (!monitor) return "";
    const workspace = monitor.specialWorkspace.id || monitor.activeWorkspace.id;
    const clients = state.clients.filter(c => c.workspace.id === workspace);
    const history = state.history[workspace] || [];
    const last = clients.find(c => c.address === history[history.length - 1]) || clients[0];
    return last ? last.title : "";
}
function language(keyboard) {
    if (!keyboard) return "—";
    const layout = (keyboard.layout || "").split(",")[keyboard.active_layout_index];
    if (layout) return layout.trim() === "us" ? "EN" : layout.trim().toUpperCase();
    const name = keyboard.active_keymap || "";
    const known = { "English (US)": "EN", "Russian": "RU" };
    return known[name] || name.slice(0, 3).toUpperCase() || "—";
}
// Lua quoted strings: do not interpolate window/workspace metadata as executable code.
function quote(value) {
    return '"' + String(value).replace(/[\\";\[\]\x00-\x1f\x7f]/g, c => "\\" + c.charCodeAt(0).toString().padStart(3, "0")) + '"';
}
function focusWindow(address) { return "/dispatch hl.dsp.focus({ window = " + quote("address:" + address) + " })"; }
function focusMonitor(output) { return "/dispatch hl.dsp.focus({ monitor = " + quote(output) + " })"; }
function workspaceCommand(group) {
    return group.special ? "/dispatch hl.dsp.workspace.toggle_special(" + quote(group.name.replace(/^special:/, "")) + ")"
        : "/dispatch hl.dsp.focus({ workspace = " + quote(String(group.id)) + " })";
}

// Hyprland executes a batch synchronously, before painting the next frame.
// Restore the click position in that same request, including monitor/window warps.
function atCursor(commands, cursor) {
    if (!cursor || !Number.isFinite(cursor.x) || !Number.isFinite(cursor.y))
        return "[[BATCH]]" + commands.join(";");
    return "[[BATCH]]" + commands.concat("/dispatch hl.dsp.cursor.move({ x = "
        + Math.round(cursor.x) + ", y = " + Math.round(cursor.y) + " })").join(";");
}
function commandSucceeded(body) {
    return body.trim().split(/\s+/).every(part => part === "ok");
}
