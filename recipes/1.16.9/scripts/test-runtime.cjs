#!/usr/bin/env node
const assert = require('node:assert/strict');
const { execFile, spawnSync } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs');
const Module = require('node:module');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const { testLoot } = require('./test-loot.cjs');

const PACKAGE_VERSION = '1.16.9';

async function testFomod(appPath, root) {
  const modulePath = path.join(appPath, 'node_modules/fomod-installer-native/dist');
  const native = require(path.join(modulePath, 'modinstaller.node'));
  assert.equal(native.ModInstaller.testSupported(['fomod/ModuleConfig.xml'], ['XmlScript']).supported, true);
  const { NativeModInstaller } = require(path.join(modulePath, 'index.js'));
  const sourcePath = path.join(root, 'fomod-source');
  fs.mkdirSync(path.join(sourcePath, 'fomod'), { recursive: true });
  fs.writeFileSync(path.join(sourcePath, 'payload.txt'), 'legacy FOMOD payload');
  fs.writeFileSync(path.join(sourcePath, 'fomod/ModuleConfig.xml'), `<?xml version="1.0" encoding="UTF-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd"><moduleName>Runtime fixture</moduleName><requiredInstallFiles><file source="payload.txt" destination="installed.txt" /></requiredInstallFiles></config>`);
  const installer = new NativeModInstaller(
    () => [], () => PACKAGE_VERSION, () => '1.10.163', () => '0.6.23',
    () => { throw new Error('The required-file FOMOD fixture must not display a dialog'); },
    () => {}, () => {},
  );
  const result = await installer.install(
    ['fomod/ModuleConfig.xml', 'payload.txt'], [], '', sourcePath, [], false,
  );
  assert.deepEqual(result?.instructions.filter((entry) => entry.type === 'copy')
    .map(({ source, destination }) => ({ source, destination })),
  [{ source: 'payload.txt', destination: 'installed.txt' }]);
  const instruction = result.instructions.find((entry) => entry.type === 'copy');
  fs.copyFileSync(path.join(sourcePath, instruction.source), path.join(root, instruction.destination));
  assert.equal(fs.readFileSync(path.join(root, 'installed.txt'), 'utf8'), 'legacy FOMOD payload');
  fs.writeFileSync(path.join(sourcePath, 'first.txt'), 'not selected');
  fs.writeFileSync(path.join(sourcePath, 'second.txt'), 'selected');
  fs.writeFileSync(path.join(sourcePath, 'fomod/ModuleConfig.xml'), `<?xml version="1.0" encoding="UTF-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd">
<moduleName>Interactive runtime fixture</moduleName><installSteps order="Explicit"><installStep name="Choose files"><optionalFileGroups order="Explicit"><group name="Variant" type="SelectExactlyOne"><plugins order="Explicit">
<plugin name="First"><description>Do not select this</description><files><file source="first.txt" destination="selected.txt"/></files><typeDescriptor><type name="Optional"/></typeDescriptor></plugin>
<plugin name="Second"><description>Select this option</description><files><file source="second.txt" destination="selected.txt"/></files><typeDescriptor><type name="Optional"/></typeDescriptor></plugin>
</plugins></group></optionalFileGroups></installStep></installSteps></config>`);
  let select;
  let next;
  let started = 0;
  let ended = 0;
  let selected = false;
  let continued = false;
  const interactive = new NativeModInstaller(
    () => [], () => PACKAGE_VERSION, () => '1.10.163', () => '0.6.23',
    (name, image, selectCallback, continueCallback) => {
      assert.equal(name, 'Interactive runtime fixture');
      select = selectCallback;
      next = continueCallback;
      started++;
    },
    () => { ended++; },
    (steps, current) => {
      if (current < 0 || !steps[current]) return;
      const step = steps[current];
      const group = step.optionalFileGroups.group[0];
      const option = group.options.find((entry) => entry.name === 'Second');
      if (!selected) {
        selected = true;
        setImmediate(() => select(step.id, group.id, [option.id]));
      } else if (option.selected && !continued) {
        continued = true;
        setImmediate(() => next(true, step.id));
      }
    },
  );
  const selectedResult = await interactive.install(
    ['fomod/ModuleConfig.xml', 'first.txt', 'second.txt'], [], '', sourcePath, null, false,
  );
  assert.equal(started, 1);
  assert.equal(ended, 1);
  assert.ok(selected && continued);
  assert.deepEqual(selectedResult.instructions.filter((entry) => entry.type === 'copy')
    .map(({ source, destination }) => ({ source, destination })),
  [{ source: 'second.txt', destination: 'selected.txt' }]);
  console.log('Native FOMOD: required files and interactive option callbacks produced correct instructions');
}

function falloutPlugin(master, dependencies = []) {
  const subrecord = (name, data) => {
    const header = Buffer.alloc(6);
    header.write(name);
    header.writeUInt16LE(data.length, 4);
    return Buffer.concat([header, data]);
  };
  const hedr = Buffer.alloc(12);
  hedr.writeFloatLE(1.0, 0);
  const body = Buffer.concat([
    subrecord('HEDR', hedr),
    ...dependencies.flatMap((dependency) => [
      subrecord('MAST', Buffer.from(`${dependency}\0`)), subrecord('DATA', Buffer.alloc(8)),
    ]),
  ]);
  const header = Buffer.alloc(24);
  header.write('TES4');
  header.writeUInt32LE(body.length, 4);
  header.writeUInt32LE(master ? 1 : 0, 8);
  header.writeUInt16LE(131, 20);
  return Buffer.concat([header, body]);
}

async function testFalloutLoot(extensionPath, root) {
  const { LootAsync } = require(path.join(extensionPath, 'libloot-adapter.cjs'));
  const gamePath = path.join(root, 'Fallout4');
  const dataPath = path.join(gamePath, 'Data');
  const localPath = path.join(root, 'Fallout4-local');
  fs.mkdirSync(dataPath, { recursive: true });
  fs.mkdirSync(localPath);
  fs.writeFileSync(path.join(dataPath, 'Fallout4.esm'), falloutPlugin(true));
  fs.writeFileSync(path.join(dataPath, 'CollectionCore.esp'), falloutPlugin(false, ['Fallout4.esm']));
  fs.writeFileSync(path.join(dataPath, 'CollectionPatch.esp'), falloutPlugin(false, ['Fallout4.esm', 'CollectionCore.esp']));
  const masterlist = path.join(root, 'fallout-masterlist.yaml');
  fs.writeFileSync(masterlist, 'plugins: []\n');
  const loot = await new Promise((resolve, reject) => LootAsync.create(
    'fallout4', gamePath, localPath, 'en', () => {}, undefined,
    (error, instance) => error ? reject(error) : resolve(instance),
  ));
  const call = (method, ...args) => new Promise((resolve, reject) => {
    loot[method](...args, (error, value) => error ? reject(error) : resolve(value));
  });
  try {
    await call('loadLists', masterlist, '', '');
    await call('loadCurrentLoadOrderState');
    await call('loadPlugins', ['collectionpatch.esp', 'collectioncore.esp', 'fallout4.esm'], false);
    assert.deepEqual(await call('sortPlugins', ['collectionpatch.esp', 'collectioncore.esp', 'fallout4.esm']),
      ['Fallout4.esm', 'CollectionCore.esp', 'CollectionPatch.esp']);
    const plugin = await call('getPlugin', 'collectionpatch.esp');
    assert.deepEqual(plugin.masters, ['Fallout4.esm', 'CollectionCore.esp']);
    console.log('Native LOOT: Fallout 4 collection dependencies sorted correctly');
  } finally {
    loot.close();
  }
}

async function testCollectionPatching(extensionPath, root) {
  assert.ok(fs.existsSync(path.join(extensionPath, 'index.js')), 'Bundled collections extension is missing');
  const bsdiff = require(path.join(extensionPath, 'bsdiff.node'));
  assert.equal(typeof bsdiff.diff, 'function');
  assert.equal(typeof bsdiff.patch, 'function');
  const originalPath = path.join(root, 'collection-original.bin');
  const modifiedPath = path.join(root, 'collection-modified.bin');
  const patchPath = path.join(root, 'collection.diff');
  const resultPath = path.join(root, 'collection-patched.bin');
  const original = Buffer.from('collection source data\0'.repeat(128));
  const modified = Buffer.from(original);
  modified.write('changed collection data', 200);
  fs.writeFileSync(originalPath, original);
  fs.writeFileSync(modifiedPath, modified);
  // The bundled native addon reports progress; its JS package wraps 100 as completion.
  const run = (method, ...args) => new Promise((resolve, reject) => {
    bsdiff[method](...args, (progress, error) => {
      if (error) reject(new Error(error));
      else if (progress >= 100) resolve();
    });
  });
  await run('diff', originalPath, modifiedPath, patchPath);
  assert.ok(fs.statSync(patchPath).size > 0);
  await run('patch', originalPath, resultPath, patchPath);
  assert.deepEqual(fs.readFileSync(resultPath), modified);
  assert.deepEqual(fs.readFileSync(originalPath), original);
  console.log('Collections: native binary diff and patch round trip passed');
}

function archiveFactory(extensionPath, expectedType, appPath) {
  let factory;
  const originalLoad = Module._load;
  const appRequire = appPath ? Module.createRequire(path.join(appPath, 'package.json')) : undefined;
  try {
    // Supply only Vortex's extension registration interface; archive parsing stays real.
    Module._load = function load(request, parent, isMain) {
      if (request === 'vortex-api') {
        return { fs, util: { NotSupportedError: class NotSupportedError extends Error {} } };
      }
      // Unpacked extensions share app.asar dependencies through Vortex's extension loader.
      if (appRequire && ['bluebird', 'minimatch'].includes(request)) {
        return originalLoad.call(this, appRequire.resolve(request), parent, isMain);
      }
      return originalLoad.call(this, request, parent, isMain);
    };
    const extension = require(path.join(extensionPath, 'index.js'));
    const init = extension.default ?? extension;
    assert.equal(init({ registerArchiveType: (type, handler) => {
      assert.equal(type, expectedType);
      factory = handler;
    } }), true);
  } finally {
    Module._load = originalLoad;
  }
  assert.equal(typeof factory, 'function');
  return factory;
}

async function testArchives(bundledPlugins, root, appPath) {
  const bsa = archiveFactory(path.join(bundledPlugins, 'gamebryo-bsa-support'), 'bsa', appPath);
  const source = path.join(root, 'archive-payload.txt');
  fs.writeFileSync(source, 'collection archive payload');
  for (const version of ['103', '104', '105']) {
    const archivePath = path.join(root, `collection-${version}.bsa`);
    const outputPath = path.join(root, `bsa-${version}`);
    const writer = await bsa(archivePath, { create: true, version });
    await writer.addFile('Meshes/Fixture/payload.nif', source);
    await writer.write();
    const reader = await bsa(archivePath, { verify: true });
    await reader.extractAll(outputPath);
    assert.equal(fs.readFileSync(path.join(outputPath, 'Meshes/Fixture/payload.nif'), 'utf8'),
      'collection archive payload');
  }
  const ba2 = archiveFactory(path.join(bundledPlugins, 'gamebryo-ba2-support'), 'ba2', appPath);
  const payload = Buffer.from('Fallout 4 collection archive payload '.repeat(32));
  const compressed = zlib.deflateSync(payload);
  const name = Buffer.from('Scripts\\Collection.pex');
  const nameEntry = Buffer.alloc(2 + name.length);
  nameEntry.writeUInt16LE(name.length);
  name.copy(nameEntry, 2);
  const header = Buffer.alloc(24);
  header.write('BTDX');
  header.writeUInt32LE(1, 4);
  header.write('GNRL', 8);
  header.writeUInt32LE(1, 12);
  header.writeBigUInt64LE(BigInt(60 + compressed.length), 16);
  const record = Buffer.alloc(36);
  record.write('pex', 4);
  record.writeBigUInt64LE(60n, 16);
  record.writeUInt32LE(compressed.length, 24);
  record.writeUInt32LE(payload.length, 28);
  const archivePath = path.join(root, 'collection.ba2');
  fs.writeFileSync(archivePath, Buffer.concat([header, record, compressed, nameEntry]));
  const outputPath = path.join(root, 'ba2');
  const reader = await ba2(archivePath, {});
  await reader.extractAll(outputPath);
  assert.deepEqual(fs.readFileSync(path.join(outputPath, 'Scripts/Collection.pex')), payload);
  console.log('Archives: BSA 103/104/105 and compressed Fallout 4 BA2 fixtures extracted');
}

async function testWindowsDotnet(root) {
  const env = { ...process.env, WINEPREFIX: path.join(root, 'wine-prefix'), WINEARCH: 'win64', WINEDEBUG: '-all', WINEDLLOVERRIDES: 'mscoree,mshtml=' };
  // Ubuntu 24.04's Wine 9 aborts during initialization whenever TMPDIR is set,
  // even to /tmp. Keep its prefix isolated while using Wine's default temp path.
  delete env.TMPDIR;
  try {
    assert.ok(process.env.VORTEX_DOTNET_WIN_ROOT, 'Bundled Windows .NET path is missing');
    const { stdout } = await promisify(execFile)('wine', [path.join(process.env.VORTEX_DOTNET_WIN_ROOT, 'dotnet.exe'), '--list-runtimes'], { env, timeout: 60_000 });
    for (const framework of ['Microsoft.NETCore.App', 'Microsoft.WindowsDesktop.App']) {
      for (const major of [6, 8, 10]) {
        assert.ok(stdout.includes(`${framework} ${major}.`), `Missing ${framework} ${major}: ${stdout}`);
      }
    }
    console.log('Wine loaded the bundled .NET 6, 8 and 10 runtime inventory');
  } finally {
    spawnSync('wineserver', ['-k'], { env, timeout: 10_000, stdio: 'ignore' });
  }
}

async function testRuntime(appPath) {
  assert.equal(require(path.join(appPath, 'package.json')).version, PACKAGE_VERSION,
    'The legacy self-test must run against the collection-compatible Vortex version');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vortex-legacy-runtime-'));
  const unpackedPath = appPath.endsWith('.asar') ? `${appPath}.unpacked` : appPath;
  const bundledPlugins = path.join(unpackedPath, 'bundledPlugins');
  try {
    await require(path.join(appPath, 'assets/linux-self-test.cjs')).runLinuxSelfTest();
    await testLoot(path.join(bundledPlugins, 'gamebryo-plugin-management'));
    await testFalloutLoot(path.join(bundledPlugins, 'gamebryo-plugin-management'), root);
    await testFomod(appPath, root);
    await testCollectionPatching(path.join(bundledPlugins, 'collections'), root);
    await testArchives(bundledPlugins, root, appPath);
    await testWindowsDotnet(root);
    console.log(`Vortex ${PACKAGE_VERSION}: packaged Linux runtime fixtures passed`);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

module.exports = { testRuntime, testFomod, testFalloutLoot, testCollectionPatching, testArchives };

if (require.main === module) {
  if (!process.argv[2]) {
    console.error('Usage: test-runtime.cjs /path/to/resources/app.asar');
    process.exit(2);
  }
  setTimeout(() => {
    console.error('Runtime self-test timed out after 180 seconds');
    process.exit(1);
  }, 180_000).unref();
  testRuntime(path.resolve(process.argv[2])).then(() => process.exit(0), (error) => {
    console.error(error);
    process.exit(1);
  });
}
