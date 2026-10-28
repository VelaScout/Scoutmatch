#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Swift-Netzwerktest benötigt macOS.'; exit 1; }
mkdir -p build
fixture_dir=$(mktemp -d)
# Echtes Backend mit simuliertem Modell und temporärem Home-Ordner – keine Nutzerdaten.
python3 Tests/agent_fixture.py "$fixture_dir/port" "$fixture_dir/home" > "$fixture_dir/log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; rm -rf "$fixture_dir"' EXIT
for i in {1..50}; do [[ -s "$fixture_dir/port" ]] && break; sleep .1; done
[[ -s "$fixture_dir/port" ]] || { echo 'Testserver startet nicht:'; cat "$fixture_dir/log"; exit 1; }
xcrun swiftc -target arm64-apple-macosx14.0 -parse-as-library ATLAS/Core/AI/AIProvider.swift ATLAS/Core/AI/LocalAtlasProvider.swift ATLAS/Core/AI/LearningOverview.swift Tests/LocalProviderTests.swift -o build/provider-tests
build/provider-tests "$(cat "$fixture_dir/port")" "$(cat "$fixture_dir/home")"
xcrun swiftc -target arm64-apple-macosx14.0 -parse-as-library ATLAS/Core/Speech/LanguageSegments.swift ATLAS/Core/Speech/SpeechText.swift Tests/SpeechTextTests.swift -o build/speech-text-tests
build/speech-text-tests
xcrun swiftc -target arm64-apple-macosx14.0 -parse-as-library ATLAS/Core/Security/SecretFilter.swift Tests/SecretFilterTests.swift -o build/secret-filter-tests
build/secret-filter-tests
