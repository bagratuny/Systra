#!/usr/bin/env python3
"""Install only this project's signed app, with staging and rollback."""
from pathlib import Path
import os, plistlib, shutil, subprocess, sys, tempfile
SOURCE=Path(sys.argv[1]).resolve()
DESTINATION=Path('/Applications/Systra.app')
BUNDLE_ID='com.arsenkocharyan.systra'
def bundle_id(app):
    return plistlib.loads((app/'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')
def copy_file(source, destination):
    shutil.copyfile(source,destination)
    shutil.copymode(source,destination)
    return destination
if bundle_id(SOURCE)!=BUNDLE_ID:raise SystemExit('Отказ: исходное приложение не является Systra.')
if DESTINATION.exists() and bundle_id(DESTINATION)!=BUNDLE_ID:
    raise SystemExit('Отказ: /Applications/Systra.app занято другим приложением.')
subprocess.run(['codesign','--verify','--deep','--strict',str(SOURCE)],check=True)
staging=Path(tempfile.mkdtemp(prefix='.Systra-install-',dir=str(DESTINATION.parent)))
staged=staging/'Systra.app';previous=staging/'previous.app'
try:
    shutil.copytree(SOURCE,staged,copy_function=copy_file,symlinks=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(staged)],check=True)
    if DESTINATION.exists():os.replace(DESTINATION,previous)
    try:os.replace(staged,DESTINATION)
    except BaseException:
        if previous.exists():os.replace(previous,DESTINATION)
        raise
finally:shutil.rmtree(staging)
print(f'Установлено: {DESTINATION}')
