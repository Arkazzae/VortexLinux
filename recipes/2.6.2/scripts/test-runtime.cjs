#!/usr/bin/env node
const assert = require('node:assert/strict');
const { execFile, spawnSync } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { testLoot } = require('./test-loot.cjs');

async function testRuntime(appPath) {
  await require(path.join(appPath, 'assets/linux-self-test.cjs')).runLinuxSelfTest();
  await testLoot(path.join(`${appPath}.unpacked`, 'bundledPlugins/gamebryo-plugin-management'));
  const modulePath = path.join(appPath, 'node_modules/@nexusmods/fomod-installer-native/dist');
  const native = require(path.join(modulePath, 'resolve-native.js')).addon;
  assert.equal(native.ModInstaller.testSupported(['fomod/ModuleConfig.xml'], ['XmlScript']).supported, true);
  const { NativeModInstaller } = require(path.join(modulePath, 'index.js'));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vortex-fomod-fixture-'));
  try {
    fs.mkdirSync(path.join(root, 'fomod'));
    fs.writeFileSync(path.join(root, 'payload.txt'), 'fixture');
    fs.writeFileSync(path.join(root, 'fomod/ModuleConfig.xml'), `<?xml version="1.0" encoding="UTF-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd"><moduleName>Runtime fixture</moduleName><requiredInstallFiles><file source="payload.txt" destination="installed.txt" /></requiredInstallFiles></config>`);
    const installer = new NativeModInstaller(() => [], () => '1.0.0', () => '1.0.0', () => '1.0.0', () => {}, () => {}, () => {});
    const result = await installer.install(['fomod/ModuleConfig.xml', 'payload.txt'], [], '', root, [], false, true);
    assert.ok(result?.instructions.some((entry) => entry.type === 'copy' && entry.source === 'payload.txt' && entry.destination === 'installed.txt'), JSON.stringify(result));
    console.log('Native FOMOD: XML installer produced the expected copy instruction');
    const env = { ...process.env, WINEPREFIX: path.join(root, 'wine-prefix'), WINEARCH: 'win64', WINEDEBUG: '-all', WINEDLLOVERRIDES: 'mscoree,mshtml=' };
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

  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

testRuntime(path.resolve(process.argv[2])).then(() => process.exit(0), (error) => {
  console.error(error);
  process.exit(1);
});
