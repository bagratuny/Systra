#!/bin/zsh
set -eu
cd "${0:A:h}"
xcodebuild -quiet -project Systra.xcodeproj -scheme Systra -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY=- build
print "Готово: $PWD/.build/DerivedData/Build/Products/Release/Systra.app"
python3 Tools/install_app.py .build/DerivedData/Build/Products/Release/Systra.app
