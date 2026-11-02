#!/usr/bin/env python3
"""Owns one isolated localhost fixture; always terminates it, including on failed tests."""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="LocalLab-AIFixture-") as temp:
    ready = Path(temp) / "ready.json"
    fixture = subprocess.Popen([sys.executable, str(root / "Tests/mock_ai.py"), "--ready", str(ready)], stdout=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 10
        while not ready.exists():
            if fixture.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("AI fixture did not start")
            time.sleep(0.025)
        env = dict(os.environ)
        env["LOCAL_LAB_TEST_AI_ENDPOINT"] = json.loads(ready.read_text())["endpoint"]
        run = subprocess.run([sys.argv[1]], env=env, timeout=90)
        status = run.returncode
    finally:
        fixture.terminate()
        try: fixture.wait(timeout=5)
        except subprocess.TimeoutExpired: fixture.kill(); fixture.wait()
sys.exit(status)
