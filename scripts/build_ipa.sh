#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export EXPECTED_IOS_SDK=27.2

actual_sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "$actual_sdk" != "$EXPECTED_IOS_SDK" && "$actual_sdk" != "$EXPECTED_IOS_SDK.0" ]]; then
  echo "Expected iOS SDK $EXPECTED_IOS_SDK, found $actual_sdk. Select the matching Xcode." >&2
  exit 1
fi
xcodebuild -version
mkdir -p build dist
python3 -B -m unittest discover -s scripts/tests -v
plist_before="$(shasum -a 256 Resources/Info.plist)"
xcodegen generate
[[ "$(shasum -a 256 Resources/Info.plist)" == "$plist_before" ]] || {
  echo "XcodeGen unexpectedly modified Info.plist" >&2
  exit 1
}
device="$(python3 scripts/select_simulator.py)"
xcodebuild -project NotesApp.xcodeproj -scheme NotesApp \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath build/DerivedData \
  test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

xcodebuild -project NotesApp.xcodeproj -scheme NotesApp \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath build/NotesApp.xcarchive \
  archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# A fresh directory prevents leftover files from entering the new archive.
package_dir="$(mktemp -d "$ROOT/build/package.XXXXXX")"
mkdir "$package_dir/Payload"
ditto build/NotesApp.xcarchive/Products/Applications/NotesApp.app "$package_dir/Payload/NotesApp.app"
(
  cd "$package_dir"
  zip -q -r -y NotesApp-unsigned.ipa Payload
)
python3 scripts/validate_ipa.py "$package_dir/NotesApp-unsigned.ipa" \
  --expected-sdk "$EXPECTED_IOS_SDK" --require-metadata > "$package_dir/ipa-validation.json"
mv "$package_dir/NotesApp-unsigned.ipa" dist/NotesApp-1.0.1-unsigned.ipa
mv "$package_dir/ipa-validation.json" dist/ipa-validation.json
{
  xcodebuild -version
  printf 'iOS SDK: %s\n' "$actual_sdk"
  printf 'Simulator iOS: %s\n' "$EXPECTED_IOS_SDK"
  printf 'Source commit: '
  git rev-parse HEAD
  printf '\nThis IPA is unsigned. Sign it before installing. Physical-device acceptance is still required.\n'
} > dist/build-info.txt
shasum -a 256 dist/NotesApp-1.0.1-unsigned.ipa > dist/SHA256SUMS.txt
echo "Prepared dist/NotesApp-1.0.1-unsigned.ipa"
