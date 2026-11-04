#!/usr/bin/env python3
from pathlib import Path
import os, signal, subprocess, time, plistlib
APP = Path('/Applications/Systra.app')
BUNDLE_ID = 'com.arsenkocharyan.systra'
EXECUTABLE = str(APP / 'Contents/MacOS/Systra')

def ours(app):
    try: return plistlib.loads((app / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') == BUNDLE_ID
    except (OSError, ValueError): return False

if not ours(APP): raise SystemExit('Установленная Systra не прошла проверку идентификатора.')
for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) != 2: continue
    path = fields[1]
    current = path == EXECUTABLE or (path.startswith('/Applications/.Systra-install-') and path.endswith('/previous.app/Contents/MacOS/Systra'))
    if current:
        pid = int(fields[0])
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: continue
        for _ in range(60):
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(.05)
subprocess.run(['open', '-n', str(APP)], check=True)
