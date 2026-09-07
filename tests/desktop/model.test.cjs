const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync('desktop/StateModel.js', 'utf8').replace('.pragma library', ''), model);
const copy = x => JSON.parse(JSON.stringify(x));
const snapshot = {
    version: { version: '0.56.2' },
    monitors: [{ name: 'DP-1', activeWorkspace: { id: 1 }, specialWorkspace: { id: 0 } },
        { name: 'DP-2', activeWorkspace: { id: 2 }, specialWorkspace: { id: 0 } }],
    workspaces: [{ id: 1, name: '1', monitor: 'DP-1', lastwindow: '0xb' }, { id: 2, name: '2', monitor: 'DP-2' },
        { id: -2, name: 'special:scratch', monitor: 'DP-1' }],
    clients: [{ address: '0xa', workspace: { id: 1 }, class: 'app', title: 'First' },
        { address: '0xb', workspace: { id: 1 }, class: 'app', title: 'Second' }],
    activewindow: { address: '0xa' }, devices: { keyboards: [{ main: true, name: 'kbd', layout: 'us,ru,de', active_layout_index: 2 }] }
};
let state = model.reconcile(model.empty(), snapshot, []);
assert.equal(model.title(state, 'DP-1'), 'First');
assert.equal(model.title(state, 'DP-2'), '');
assert.equal(model.groups(state, 'DP-1')[0].windows.length, 2);
assert.equal(model.groups(state, 'DP-1').length, 1);
assert.equal(model.groups(state, 'missing').length, 0);
assert.equal(model.language(state.keyboard), 'DE');
const next = copy(snapshot);
next.activewindow.address = '0xb';
next.clients.reverse();
state = model.reconcile(state, next, []);
assert.deepEqual(copy(state.clients.map(c => c.address)), ['0xa', '0xb']);
assert.equal(model.title(state, 'DP-1'), 'Second');
next.clients = next.clients.filter(c => c.address !== '0xb');
state = model.reconcile(state, next, []);
assert.equal(model.title(state, 'DP-1'), 'First');
next.clients[0].workspace.id = 2;
state = model.reconcile(state, next, [{ name: 'urgent', address: '0xa' }]);
assert.equal(model.title(state, 'DP-1'), '');
assert.equal(model.title(state, 'DP-2'), 'First');
assert.equal(state.urgent['0xa'], true);
next.activewindow.address = '0xa';
state = model.reconcile(state, next, []);
assert.equal(state.urgent['0xa'], undefined);
next.monitors[0].specialWorkspace.id = -2;
state = model.reconcile(state, next, []);
assert.equal(model.groups(state, 'DP-1')[1].label, 'S');
assert.equal(model.title(state, 'DP-1'), '');
assert.throws(() => model.reconcile(state, { ...next, clients: {} }, []));
assert.throws(() => model.reconcile(state, { ...next, version: { version: '9.0' } }, []));
const unplugged = copy(next);
unplugged.monitors = [];
const disconnected = model.reconcile(state, unplugged, []);
assert.equal(model.groups(disconnected, 'DP-1').length, 0);
assert.equal(model.title(disconnected, 'DP-2'), '');
assert.equal(model.quote('a"\\\nb'), '"a\\034\\092\\010b"');
console.log('PASS model: ordering, focus history, close/move, monitors, special, urgency, layouts, invalid schema, quoting');

const click = model.atCursor([model.focusMonitor('DP-2'), model.workspaceCommand({ id: 3, special: false })], {x: -2410, y: 21});
assert.ok(click.startsWith('[[BATCH]]'));
assert.ok(click.endsWith('/dispatch hl.dsp.cursor.move({ x = -2410, y = 21 })'));
assert.equal(model.commandSucceeded('ok\n\n\nok\n\n\nok'), true);
assert.equal(model.commandSucceeded('ok\nerror'), false);
assert.equal(model.commandSucceeded(''), false);
const special = model.workspaceCommand({ special: true, name: 'special:a;[b]' });
assert.ok(!special.includes(';') && !special.includes('[') && !special.includes(']'));
console.log('PASS click batch: pointer coordinates, escaping and command acknowledgements');
