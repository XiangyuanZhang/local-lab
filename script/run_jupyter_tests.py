#!/usr/bin/env python3
"""Run the real Swift transport against an owned, isolated local Jupyter fixture."""
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
root = Path(__file__).resolve().parent.parent
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
env = dict(os.environ, LOCAL_LAB_TEST_MOCK_PORT=str(port), LOCAL_LAB_TEST_API=f'http://127.0.0.1:{port}/api')
fixture = subprocess.Popen([sys.executable, str(root / 'Tests/mock_jupyter.py')], env=env, stdout=subprocess.DEVNULL)
try:
    deadline = time.monotonic() + 10
    while True:
        if fixture.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError('Jupyter fixture failed to start')
        with socket.socket() as probe:
            if probe.connect_ex(('127.0.0.1', port)) == 0:
                break
        time.sleep(0.025)
    run = subprocess.run([str(root / '.build/LocalLabChecks')], env=env, timeout=90)
    status = run.returncode
finally:
    fixture.terminate()
    try:
        fixture.wait(timeout=5)
    except subprocess.TimeoutExpired:
        fixture.kill()
        fixture.wait()
sys.exit(status)
