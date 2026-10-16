#!/bin/zsh
# Archive a Release build and upload it to App Store Connect, where it lands in TestFlight.
#
# The version comes from MARKETING_VERSION in project.yml (e.g. 1.0.0). The build number is
# assigned by Xcode at upload time: it asks App Store Connect for the next one (1, 2, 3, ...),
# so nothing needs committing after an upload.
#
# Usage:
#   scripts/testflight.sh              archive and upload
#   scripts/testflight.sh --no-upload  archive only
#
# Uploading uses the Apple account signed in to Xcode (Settings > Accounts). To use an
# App Store Connect API key instead (as CI does), set ASC_KEY_PATH (the .p8 file),
# ASC_KEY_ID and ASC_ISSUER_ID.

set -euo pipefail

cd "$(dirname "$0")/.."

upload=true
if [[ "${1:-}" == "--no-upload" ]]; then
  upload=false
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--no-upload]" >&2
  exit 64
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "warning: working tree has uncommitted changes; they will be in this build." >&2
fi

# Tidy xcodebuild's output when xcbeautify is installed (brew install xcbeautify).
pretty() {
  if command -v xcbeautify > /dev/null; then xcbeautify; else cat; fi
}

auth=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  auth=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "${ASC_KEY_ID:?ASC_KEY_ID must be set with ASC_KEY_PATH}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID must be set with ASC_KEY_PATH}"
  )
fi

build_dir="build/testflight/$(date '+%Y%m%d-%H%M%S')"
archive_path="$build_dir/Mettiti.xcarchive"
export_options="$build_dir/ExportOptions.plist"
mkdir -p "$build_dir"

echo "==> Archiving Mettiti"
xcodebuild archive \
  -project Mettiti.xcodeproj \
  -scheme Mettiti \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  "${auth[@]}" \
  | pretty

version=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive_path/Info.plist")

if ! $upload; then
  echo "==> Archived version $version to $archive_path (not uploaded)"
  exit 0
fi

# manageAppVersionAndBuildNumber lets Xcode replace the archive's build number with the
# next one App Store Connect will accept.
cat > "$export_options" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>TYXC29FT67</string>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Uploading version $version to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$build_dir/export" \
  -allowProvisioningUpdates \
  "${auth[@]}" \
  | pretty

echo "==> Uploaded version $version. It appears in TestFlight once App Store Connect finishes processing (usually 5-30 minutes)."
