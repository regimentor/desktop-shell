const {test} = require('node:test');
const assert = require('node:assert/strict');
const {create, groups} = require('../../notifications/NotificationState.js');
function setup() {
    let now = 1000000000;
    const calls = [];
    const state = create({now: () => now, closeLive: (id, reason) => calls.push([id, reason])});
    state.setScreens(['A', 'B'], 'A'); state.setLock('unlocked');
    const data = {app: 'Test', group: 'test', icon: '', summary: 'Hello', body: 'World',
        timeout: -1, urgency: 1, transient: false, image: '', actions: [{id:'default',text:'Open'}], reply: true};
    return {state, calls, add: (id, overrides={}) => state.receive(id, {...data,...overrides}).key, advance: ms => {now+=ms;state.tick(ms);}};
}
test('queued messages receive a full duration and replacements do not duplicate', () => {
    const {state:s, add, advance, calls} = setup();
    const keys = [1,2,3,4].map(id=>add(id));
    assert.equal(s.find(keys[3]).popup, 'queued');
    advance(4500); add(1, {body:'Updated'});
    advance(500);
    assert.equal(s.records.length,4);
    assert.equal(s.find(keys[0]).remaining,4500);
    assert.equal(s.find(keys[3]).remaining,5000);
    assert.equal(s.find(keys[3]).popup,'visible');
    assert.deepEqual(calls,[[2,'expire'],[3,'expire']]);
});
test('DND, unknown lock and unlock retain unread live history without replay', () => {
    const {state:s,add,advance} = setup();
    const key = add(1); s.setDnd(true); advance(10000);
    assert.equal(s.find(key).liveId,1); assert.equal(s.find(key).unread,true);
    s.setDnd(false); add(1,{body:'Replacement'});
    assert.equal(s.find(key).popup,'suppressed');
    s.setLock('unknown'); const second=add(2); s.setLock('unlocked');
    assert.equal(s.find(second).popup,'suppressed');
    assert.equal(s.find(add(3)).popup,'visible');
});
test('hover, reply, critical and zero timeout pause automatic closure',()=>{
    const {state:s,add,advance,calls}=setup();
    const key=add(1); s.find(key).hovered=true; advance(6000);
    s.find(key).hovered=false; s.find(key).replying=true; advance(6000);
    assert.equal(s.find(key).remaining,5000);
    add(2,{urgency:2}); add(3,{timeout:0}); advance(60000);
    assert.deepEqual(calls,[]);
});
test('deleting a group also closes queued/live rows and removes drafts',()=>{
    const {state:s,add,calls}=setup(); const keys=[1,2,3,4].map(id=>add(id));
    s.drafts[keys[0]]='draft'; s.remove(keys);
    assert.equal(s.records.length,0); assert.deepEqual(s.drafts,{});
    assert.equal(calls.length,4);
});
test('transient never enters disk snapshot, and suppression releases it',()=>{
    const {state:s,add,calls}=setup(); add(1,{transient:true});
    assert.equal(s.snapshot().records.length,0); s.setDnd(true);
    add(2,{transient:true}); assert.equal(s.records.length,0);
    assert.equal(calls.length,2);
});
test('archive restart strips live actions and drafts but preserves unread and DND',()=>{
    const {state:s,add}=setup(); const key=add(1); s.drafts[key]='secret'; s.setDnd(true);
    const other=setup().state; other.restore(JSON.stringify(s.snapshot()));
    assert.equal(other.dnd,true); assert.equal(other.find(key).unread,true);
    assert.equal(other.find(key).liveId,null); assert.equal(other.find(key).popup,'none');
    assert.deepEqual(other.find(key).actions,[]); assert.deepEqual(other.drafts,{});
});
test('archive limits remove oldest live entries; malformed data does not throw',()=>{
    const {state:s,add,advance,calls}=setup(); s.maxRecords=2;
    add(1); advance(1); add(2); advance(1); add(3);
    assert.equal(s.records.length,2); assert.deepEqual(calls,[[1,'dismiss']]);
    advance(s.maxAge+1); s.prune(); assert.equal(s.records.length,0);
    s.restore('broken'); assert.match(s.error,/историю/);
});
test('shown cards stay on their monitor, new cards use focused monitor and hotplug migrates',()=>{
    const {state:s,add}=setup(); const first=add(1);
    s.setScreens(['A','B'],'B'); const second=add(2);
    assert.equal(s.find(first).screen,'A'); assert.equal(s.find(second).screen,'B');
    s.setScreens(['B'],'B'); assert.equal(s.find(first).screen,'B');
});
test('search groups only matching records and unread filter does not mutate read state',()=>{
    const {state:s,add}=setup(); add(1); add(2,{body:'Needle'}); add(3,{group:'other',app:'Other'});
    const filtered=groups(s.records,'needle',true);
    assert.equal(filtered.length,1); assert.equal(filtered[0].rows.length,1);
    assert.equal(s.records.every(row=>row.unread),true);
});
