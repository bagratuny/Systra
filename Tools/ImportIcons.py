#!/usr/bin/env python3
"""Import Systra artwork and apply macOS tile geometry to colour app icons."""
from pathlib import Path
from zipfile import ZipFile
import sys, tempfile, subprocess, shutil
root = Path(__file__).resolve().parents[1]
resources = root / 'Resources'
output = root / '.build/SystraIcon.iconset'
with ZipFile(sys.argv[1]) as archive, tempfile.TemporaryDirectory() as temporary:
    raw = Path(temporary) / 'Systra.iconset'
    raw.mkdir()
    for points in [16, 32, 128, 256, 512]:
        for scale in ['', '@2x']:
            name = f'icon_{points}x{points}{scale}.png'
            (raw / name).write_bytes(archive.read('Systra-macOS/Systra.iconset/' + name))
    for source, target in [('Monochrome/black/Systra-mono-black-20.png', 'SystraMenu.png'), ('Monochrome/black/Systra-mono-black-40.png', 'SystraMenu@2x.png')]:
        (resources / target).write_bytes(archive.read('Systra-macOS/' + source))
    subprocess.run(['swift', str(root / 'Tools/BuildAppIcon.swift'), str(raw), str(output)], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(output), '-o', str(resources / 'Systra.icns')], check=True)
    shutil.copyfile(output / 'icon_512x512@2x.png', resources / 'Systra.png')
    shutil.copyfile(output / 'icon_32x32@2x.png', resources / 'SystraSmall.png')
