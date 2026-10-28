#!/usr/bin/env python3
from contextlib import closing
import json
import sys
import time
import urllib.request

import websocket


MAIN_PAGE = '''JSON.stringify({
    ready: !!document.querySelector('#content .main-page-inner'),
    text: document.querySelector('#content')?.innerText?.slice(0, 2000)
})'''

# Vortex reports a missing .NET in its interface, not on stdout. Run its probe
# from the renderer, as Vortex does at startup, so the check sees the
# environment the launcher gave the app.
DOTNET_PROBE = '''(() => {
    const { execFileSync } = require('child_process');
    const probe = require('path').join(process.resourcesPath, 'app.asar.unpacked', 'assets', 'dotnetprobe');
    try {
        return JSON.stringify({ ok: true, output: execFileSync(probe, ['9'], { encoding: 'utf8', timeout: 30000 }) });
    } catch (error) {
        return JSON.stringify({ ok: false, output: String(error.stderr || error.message) });
    }
})()'''


def evaluate(connection, request_id, expression):
    connection.send(json.dumps({
        'id': request_id, 'method': 'Runtime.evaluate',
        'params': {'expression': expression, 'returnByValue': True},
    }))
    while True:
        result = json.loads(connection.recv())
        if result.get('id') == request_id:
            return json.loads(result['result']['result']['value'])


def check_ui():
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
                    state = evaluate(connection, 1, MAIN_PAGE)
                    if not (state.get('ready') and state.get('text')):
                        last_error = repr(state)
                        continue
                    print('Vortex renderer loaded its main page')
                    connection.settimeout(40)
                    probe = evaluate(connection, 2, DOTNET_PROBE)
                    if not probe['ok']:
                        sys.exit(f'Vortex cannot run its .NET 9 probe: {probe["output"]}')
                    print(f'Vortex found .NET from its renderer: {probe["output"].strip()}')
                    return
        except (OSError, ValueError, KeyError, websocket.WebSocketException) as error:
            last_error = str(error)
        time.sleep(1)
    sys.exit(f'Vortex interface did not become ready: {last_error}')


if __name__ == '__main__':
    check_ui()
