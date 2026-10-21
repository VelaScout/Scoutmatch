#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Swift-Netzwerktest benötigt macOS.'; exit 1; }
mkdir -p build
fixture_dir=$(mktemp -d)
python3 Tests/provider_fixture.py "$fixture_dir/port" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; rm -rf "$fixture_dir"' EXIT
for i in {1..30}; do [[ -s "$fixture_dir/port" ]] && break; sleep .1; done
[[ -s "$fixture_dir/port" ]] || { echo 'Testserver startet nicht.'; exit 1; }
xcrun swiftc -target arm64-apple-macosx14.0 -parse-as-library ATLAS/Core/AI/AIProvider.swift ATLAS/Core/AI/LocalAtlasProvider.swift Tests/LocalProviderTests.swift -o build/provider-tests
build/provider-tests "$(cat "$fixture_dir/port")"
xcrun swiftc -target arm64-apple-macosx14.0 -parse-as-library ATLAS/Core/Speech/LanguageSegments.swift ATLAS/Core/Speech/SpeechText.swift Tests/SpeechTextTests.swift -o build/speech-text-tests
build/speech-text-tests
