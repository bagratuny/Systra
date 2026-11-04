#!/usr/bin/env python3
from pathlib import Path
import os, signal, subprocess, time
APP=Path('/Applications/Systra.app')
EXECUTABLE=str(APP/'Contents/MacOS/SystraMac')
for line in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
    fields=line.strip().split(None,1)
    if len(fields)==2 and (fields[1]==EXECUTABLE or (
        fields[1].startswith('/Applications/.Systra-install-') and fields[1].endswith('/previous.app/Contents/MacOS/SystraMac')
    )):
        pid=int(fields[0])
        try:os.kill(pid,signal.SIGTERM)
        except ProcessLookupError:continue
        for _ in range(60):
            try:os.kill(pid,0)
            except ProcessLookupError:break
            time.sleep(.05)
subprocess.run(['open','-n',str(APP)],check=True)
