#!/usr/bin/env python3
from contextlib import closing
import json
import sys
import time
import urllib.request

REQUIRED_EXTENSIONS = (
    'gamebryo-plugin-management',
    'gamebryo-archive-check',
    'gamebryo-plugin-indexlock',
)

# Read the live ExtensionManager from its React context provider. An extension
# remains in getLoadedExtensions() even when initialization/dependencies fail,
# so its presence alone is insufficient. The renderer publishes those failures
# to Redux before rendering the main page.
RENDERER_STATE = r'''(() => {
    const content = document.querySelector('#content');
    const snapshot = {
        ready: !!content?.querySelector('.main-page-inner'),
        text: content?.innerText?.slice(0, 2000),
    };
    // React 18's legacy ReactDOM.render stores the FiberRoot directly here.
    const root = content?._reactRootContainer?.current;
    const pending = root ? [root] : [];
    let api;
    while (pending.length > 0) {
        const fiber = pending.pop();
        const value = fiber.memoizedProps?.value;
        if (typeof value?.getApi === 'function') {
            const candidate = value.getApi();
            if (typeof candidate?.getLoadedExtensions === 'function'
                    && typeof candidate?.getState === 'function') {
                api = candidate;
                break;
            }
        }
        if (fiber.child) pending.push(fiber.child);
        if (fiber.sibling) pending.push(fiber.sibling);
    }
    if (!api) return { ...snapshot, error: 'ExtensionManager context is not ready' };
    const state = api.getState();
    const failures = state?.session?.base?.extLoadFailures;
    const configured = state?.app?.extensions;
    if (!failures || !configured) {
        return { ...snapshot, error: 'Extension state is not ready' };
    }
    return {
        ...snapshot,
        extensions: api.getLoadedExtensions().map(extension => ({
            name: extension.name,
            enabled: configured[extension.name]?.enabled !== false,
        })),
        failures,
    };
})()'''


def readiness_error(state):
    if not state.get('ready') or not state.get('text'):
        return f'Main page is not ready: {state!r}'
    if state.get('error'):
        return state['error']
    if not isinstance(state.get('extensions'), list) or not isinstance(state.get('failures'), dict):
        return 'Renderer did not expose extension state'
    extensions = {extension['name']: extension for extension in state['extensions']}
    problems = []
    for name in REQUIRED_EXTENSIONS:
        extension = extensions.get(name)
        if extension is None:
            problems.append(f'{name}: not loaded')
        elif extension.get('enabled') is not True:
            problems.append(f'{name}: disabled')
        failures = state['failures'].get(name, [])
        if failures:
            problems.append(f'{name}: {failures!r}')
    return '; '.join(problems) if problems else None


def check_ui():
    import websocket

    deadline = time.monotonic() + 45
    last_error = 'No renderer target appeared'
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:9222/json', timeout=2) as response:
                targets = json.load(response)
            for target in targets:
                if target.get('type') != 'page' or 'index.html' not in target.get('url', ''):
                    continue
                with closing(websocket.create_connection(target['webSocketDebuggerUrl'], timeout=3, suppress_origin=True)) as connection:
                    connection.send(json.dumps({
                        'id': 1, 'method': 'Runtime.evaluate', 'params': {
                            'expression': RENDERER_STATE, 'returnByValue': True,
                        },
                    }))
                    while True:
                        result = json.loads(connection.recv())
                        if result.get('id') != 1:
                            continue
                        if 'error' in result or 'exceptionDetails' in result.get('result', {}):
                            last_error = repr(result)
                            break
                        state = result['result']['result']['value']
                        last_error = readiness_error(state)
                        if last_error is None:
                            print('Vortex renderer loaded its main page and initialized: '
                                  + ', '.join(REQUIRED_EXTENSIONS))
                            return
                        break
        except (OSError, ValueError, KeyError, websocket.WebSocketException) as error:
            last_error = str(error)
        time.sleep(1)
    sys.exit(f'Vortex interface did not become ready: {last_error}')


if __name__ == '__main__':
    check_ui()
