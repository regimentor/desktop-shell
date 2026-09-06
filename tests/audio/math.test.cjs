const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const math = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../../launcher/AudioMath.js`, 'utf8'), math);
const plain = value => JSON.parse(JSON.stringify(value));

test('group volume preserves proportions and restores known ratios through zero', () => {
    assert.deepEqual(plain(math.scaled([0.8, 0.4], 0.6).values), [0.6, 0.3]);
    const zero = math.scaled([0.8, 0.4], 0);
    assert.deepEqual(plain(zero.values), [0, 0]);
    assert.deepEqual(plain(math.scaled(zero.values, 0.6, zero.ratios).values), [0.6, 0.3]);
    assert.deepEqual(plain(math.scaled([0, 0], 0.3).values), [0.3, 0.3]);
});
test('external levels are read honestly; only user writes are clamped', () => {
    assert.equal(math.maximum([1.6, 0.4]), 1.6);
    assert.deepEqual(plain(math.scaled([1.6, 0.4], 2).values), [1, 0.25]);
    assert.deepEqual(plain(math.scaled([0.8, 0.4], -1).values), [0, 0]);
});
test('same names do not group unrelated clients or unknown nodes', () => {
    assert.equal(math.identity({'application.id': 'browser', 'client.id': '1'}, 'a'),
        math.identity({'application.id': 'browser', 'client.id': '2'}, 'b'));
    assert.notEqual(math.identity({'application.name': 'Same', 'client.id': '1'}, 'a'),
        math.identity({'application.name': 'Same', 'client.id': '2'}, 'b'));
    assert.notEqual(math.identity({'application.name': 'Same'}, 'a'),
        math.identity({'application.name': 'Same'}, 'b'));
    assert.equal(math.identity({'client.id': '0'}, 'a'), 'client:0');
});
test('partial mute toggles toward muting all, without changing numeric levels', () => {
    assert.equal(math.muteState([true, false]), 'mixed');
    assert.equal(math.muteState([true, true]), 'muted');
    assert.equal(math.muteState([false, false]), 'audible');
    assert.equal(math.maximum([0.8, 0.4]), 0.8);
});
