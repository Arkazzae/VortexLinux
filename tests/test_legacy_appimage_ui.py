"""Exercise the CDP probe and readiness gate without Electron or websocket-client."""

import importlib.util
import json
from pathlib import Path
import subprocess
import unittest


CHECK_PATH = Path(__file__).resolve().parents[1] / 'recipes/2.6.2/scripts/check-appimage-ui.py'
SPEC = importlib.util.spec_from_file_location('legacy_appimage_ui', CHECK_PATH)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

# The probe must inspect the actual provider API and Redux failure map. Keep the
# fixture's extra providers/siblings so a check of just the root cannot pass.
RENDERER_FIXTURE = r'''
const fs = require('node:fs');
const vm = require('node:vm');
const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));
const state = {
    app: { extensions: fixture.configured ?? {} },
    session: { base: { extLoadFailures: fixture.failures ?? {} } },
};
if (fixture.missingState) delete state.session.base.extLoadFailures;
const api = {
    getLoadedExtensions: () => fixture.loaded.map(name => ({ name })),
    getState: () => state,
};
const provider = { memoizedProps: { value: { getApi: () => api } } };
const root = {
    child: {
        memoizedProps: { value: { getApi: () => ({}) } },
        sibling: { child: provider },
    },
};
if (fixture.missingContext) delete provider.memoizedProps;
const content = {
    innerText: 'Dashboard',
    querySelector: selector => selector === '.main-page-inner' && fixture.ready ? {} : null,
    _reactRootContainer: { current: root },
};
const document = { querySelector: selector => selector === '#content' ? content : null };
process.stdout.write(JSON.stringify(vm.runInNewContext(fixture.expression, { document })));
'''


class LegacyAppImageUiTests(unittest.TestCase):
    def probe(self, **changes):
        fixture = {
            'expression': CHECK.RENDERER_STATE,
            'loaded': list(CHECK.REQUIRED_EXTENSIONS),
            'ready': True,
            **changes,
        }
        result = subprocess.run(
            ['node', '-e', RENDERER_FIXTURE], input=json.dumps(fixture),
            text=True, capture_output=True, check=True,
        )
        return CHECK.readiness_error(json.loads(result.stdout))

    def test_initialized_extensions_pass_without_persisted_entries(self):
        # Bundled extensions are not persisted on a clean profile.
        self.assertIsNone(self.probe())

    def test_missing_plugin_management_fails_even_when_main_page_rendered(self):
        error = self.probe(loaded=list(CHECK.REQUIRED_EXTENSIONS[1:]))
        self.assertIn('gamebryo-plugin-management: not loaded', error)

    def test_each_required_extension_must_be_present(self):
        for missing in CHECK.REQUIRED_EXTENSIONS:
            with self.subTest(missing=missing):
                error = self.probe(loaded=[name for name in CHECK.REQUIRED_EXTENSIONS if name != missing])
                self.assertIn(f'{missing}: not loaded', error)

    def test_registered_extensions_with_dependency_failures_do_not_pass(self):
        error = self.probe(failures={
            'gamebryo-archive-check': [{
                'id': 'dependency',
                'args': {'dependencyId': 'gamebryo-plugin-management'},
            }],
        })
        self.assertIn('gamebryo-archive-check', error)
        self.assertIn('dependency', error)
        self.assertIn('gamebryo-plugin-management', error)

    def test_native_module_initialization_exception_does_not_pass(self):
        error = self.probe(failures={
            'gamebryo-plugin-management': [{
                'id': 'exception', 'args': {'message': 'Could not load native LOOT'},
            }],
        })
        self.assertIn('Could not load native LOOT', error)

    def test_persisted_disabled_state_does_not_pass(self):
        error = self.probe(configured={'gamebryo-plugin-indexlock': {'enabled': False}})
        self.assertIn('gamebryo-plugin-indexlock: disabled', error)

    def test_waits_for_main_page(self):
        self.assertIn('Main page is not ready', self.probe(ready=False))

    def test_waits_for_provider(self):
        self.assertIn('ExtensionManager context is not ready', self.probe(missingContext=True))

    def test_waits_for_failure_state_instead_of_assuming_success(self):
        self.assertIn('Extension state is not ready', self.probe(missingState=True))


if __name__ == '__main__':
    unittest.main()
