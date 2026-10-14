#!/usr/bin/env python3
from contextlib import closing
import json
import sys
import time
import urllib.request

import websocket


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
                    connection.send(json.dumps({
                        'id': 1, 'method': 'Runtime.evaluate', 'params': {
                            'expression': '''JSON.stringify({
                                ready: !!document.querySelector('#content .main-page-inner'),
                                text: document.querySelector('#content')?.innerText?.slice(0, 2000)
                            })''', 'returnByValue': True,
                        },
                    }))
                    while True:
                        result = json.loads(connection.recv())
                        if result.get('id') != 1:
                            continue
                        state = json.loads(result['result']['result']['value'])
                        if state.get('ready') and state.get('text'):
                            print('Vortex renderer loaded its main page')
                            return
                        last_error = repr(state)
                        break
        except (OSError, ValueError, KeyError, websocket.WebSocketException) as error:
            last_error = str(error)
        time.sleep(1)
    sys.exit(f'Vortex interface did not become ready: {last_error}')


if __name__ == '__main__':
    check_ui()
