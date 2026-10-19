#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function plugin(master = false, dependencies = []) {
  const subrecord = (type, data) => {
    const header = Buffer.alloc(6);
    header.write(type);
    header.writeUInt16LE(data.length, 4);
    return Buffer.concat([header, data]);
  };
  const hedr = Buffer.alloc(12);
  hedr.writeFloatLE(1.7);
  const records = [subrecord('HEDR', hedr)];
  for (const dependency of dependencies) {
    records.push(subrecord('MAST', Buffer.from(`${dependency}\0`)), subrecord('DATA', Buffer.alloc(8)));
  }
  const body = Buffer.concat(records);
  const header = Buffer.alloc(24);
  header.write('TES4');
  header.writeUInt32LE(body.length, 4);
  header.writeUInt32LE(master ? 1 : 0, 8);
  header.writeUInt16LE(44, 20);
  return Buffer.concat([header, body]);
}

// lootPath is a node-loot package: the one in the renderer's dependencies or assets/loot of a
// packaged Vortex. Plugins are loaded by absolute path, as Vortex resolves them on Linux.
async function testLoot(lootPath) {
  const { LootAsync } = require(path.join(lootPath, 'index.js'));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vortex-loot-test-'));
  const data = path.join(root, 'Game', 'data');
  const local = path.join(root, 'Local');
  fs.mkdirSync(data, { recursive: true });
  fs.mkdirSync(local);
  let loot;
  const call = (method, ...args) => loot[method](...args);
  const plugins = (...names) => names.map((name) => path.join(data, name));
  try {
    for (const name of ['Skyrim.esm', 'Alpha.esp', 'Beta.esp']) {
      fs.writeFileSync(path.join(data, name), plugin(name.endsWith('.esm'), name.endsWith('.esp') ? ['Skyrim.esm'] : []));
    }
    loot = await LootAsync.create('skyrimse', path.join(root, 'Game'), local, 'en', () => {});
    const masterlist = path.join(root, 'masterlist.yaml');
    const userlist = path.join(root, 'userlist.yaml');
    fs.writeFileSync(masterlist, `groups:
  - name: default
  - name: late
    after: [default]
plugins:
  - name: Alpha.esp
    group: late
    after: [Beta.esp]
    req: [Skyrim.esm]
    tag: [Relev]
    msg:
      - type: say
        content: 'Zażółć — metadata from native LOOT'
`);
    await call('loadLists', masterlist, '', '');
    await call('loadCurrentLoadOrderState');
    await call('loadPlugins', plugins('Alpha.esp', 'Beta.esp', 'Skyrim.esm'), false);
    assert.deepEqual(await call('sortPlugins', ['alpha.esp', 'beta.esp', 'skyrim.esm']), ['Skyrim.esm', 'Beta.esp', 'Alpha.esp']);
    const info = await call('getPlugin', 'alpha.esp');
    assert.equal(info.name, 'Alpha.esp');
    assert.deepEqual(info.masters, ['Skyrim.esm']);
    assert.equal(typeof info.isEmpty, 'boolean');
    const metadata = await call('getPluginMetadata', 'Alpha.esp');
    assert.equal(metadata.group, 'late');
    assert.equal(metadata.messages[0].content[0].text, 'Zażółć — metadata from native LOOT');
    assert.equal(metadata.requirements[0].name, 'Skyrim.esm');
    assert.equal(metadata.tags[0].name, 'Relev');
    assert.deepEqual((await call('getGroupsPath', 'default', 'late')).map((entry) => entry.name), ['default', 'late']);
    fs.writeFileSync(userlist, 'plugins:\n  - name: Alpha.esp\n    group: default\n');
    await call('loadLists', masterlist, userlist, '');
    assert.equal((await call('getPluginMetadata', 'Alpha.esp')).group, 'default');
    fs.writeFileSync(userlist, 'plugins: []\n');
    await call('loadLists', masterlist, userlist, '');
    assert.equal((await call('getPluginMetadata', 'Alpha.esp')).group, 'late');
    fs.writeFileSync(userlist, 'plugins:\n  - name: Beta.esp\n    after: [Alpha.esp]\n');
    await call('loadLists', masterlist, userlist, '');
    const cycleError = await call('sortPlugins', ['alpha.esp', 'beta.esp', 'skyrim.esm']).then(
      () => assert.fail('A cyclic load order was sorted'), (error) => error);
    assert.match(cycleError.message, /^Cyclic interaction/);
    assert.deepEqual(new Set(cycleError.cycle.map((vertex) => vertex.name)), new Set(['Alpha.esp', 'Beta.esp']));
    assert.ok(cycleError.cycle.some((vertex) => vertex.typeOfEdgeToNextVertex === 'userlistLoadAfter'), JSON.stringify(cycleError.cycle));
    fs.writeFileSync(userlist, 'plugins: []\n');
    await call('loadLists', masterlist, userlist, '');
    fs.writeFileSync(path.join(data, 'New.esp.ghost'), plugin());
    await call('loadPlugins', plugins('New.esp.ghost'), true);
    assert.equal((await call('getPlugin', 'new.esp')).name, 'New.esp');
    await assert.rejects(call('loadPlugins', plugins('Missing.esp'), true));
    loot.close();
    assert.equal(loot.isClosed(), true);
    await assert.rejects(call('clearConditionCache'), /closed/);
    console.log('Native LOOT: sorting, metadata, cycles, ghost plugins and worker shutdown passed');
  } finally {
    loot?.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

module.exports = { testLoot };
if (require.main === module) {
  testLoot(path.resolve(process.argv[2])).catch((error) => { console.error(error); process.exitCode = 1; });
}
