#!/usr/bin/env python3
"""Package a verified macOS app and validate the extracted release before publishing."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = 'com.arsenkocharyan.systra'

def validate(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise SystemExit('The selected app is not Systra.')
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise SystemExit('Unexpected app version.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    architecture = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
    if architecture != 'arm64':
        raise SystemExit('This release package expects an arm64 app.')
    return version, str(info['CFBundleVersion']), architecture

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('/Applications/Systra.app'))
    parser.add_argument('--output', type=Path, default=ROOT / '.build/releases')
    args = parser.parse_args()
    app = args.app.resolve()
    version, build, architecture = validate(app)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    filename = f'Systra-{version}-build{build}-macOS-{architecture}.zip'
    archive = output / filename
    with tempfile.TemporaryDirectory(prefix='systra-release-') as temporary:
        temporary = Path(temporary)
        packed = temporary / filename
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(packed)], check=True)
        unpacked = temporary / 'verify'
        subprocess.run(['ditto', '-x', '-k', str(packed), str(unpacked)], check=True)
        if validate(unpacked / app.name) != (version, build, architecture):
            raise SystemExit('The extracted app does not match the release.')
        digest = hashlib.sha256(packed.read_bytes()).hexdigest()
        # Stage beside the destination so replacing an existing artifact is atomic.
        staged = output / (filename + '.partial')
        staged.write_bytes(packed.read_bytes())
        os.replace(staged, archive)
    (output / f'SHA256SUMS-build{build}.txt').write_text(f'{digest}  {filename}\n')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    manifest = dict(version=version, build=build, architecture=architecture, archive=filename, sha256=digest, source_commit=commit)
    (output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))
    print(archive)

if __name__ == '__main__':
    main()
