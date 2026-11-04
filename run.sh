#!/bin/zsh
set -eu
cd "${0:A:h}"
./build.sh
python3 Tools/launch_app.py
