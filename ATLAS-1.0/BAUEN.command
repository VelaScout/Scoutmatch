#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Dieser Build benötigt einen Apple-Silicon-Mac.'; exit 1; }
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcodebuild -version || { echo 'Bitte die vollständige Xcode-App installieren und einmal öffnen. Command Line Tools allein reichen nicht.'; exit 1; }
mkdir -p build
exec > >(tee build/BUILD-LOG.txt) 2>&1
bash Tests/test_provider_mac.sh
xcodebuild -project ATLAS.xcodeproj -scheme ATLAS -configuration Release \
  -sdk macosx -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
app_path="$PWD/build/DerivedData/Build/Products/Release/ATLAS.app"
[[ -d "$app_path" ]] || { echo 'Xcode hat keine App erzeugt.'; exit 1; }
codesign --force --sign - --entitlements Config/ATLAS-macOS.entitlements "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
echo "Build und lokale Signatur geprüft: $app_path"
