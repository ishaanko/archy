#!/usr/bin/env bash
# Archives a Release build and uploads it to App Store Connect, where it shows up under TestFlight.
# Usage: scripts/release.sh [--no-upload]   (--no-upload writes build/release/archy.ipa instead)
# The build number is the UTC time (YYYYMMDDHHMM), so every upload is higher than the last one.
# The version people see (1.0) is MARKETING_VERSION in project.yml.
# Needs the team's Apple ID signed in under Xcode > Settings > Accounts, and the app record in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."
destination=upload
[[ "${1:-}" == "--no-upload" ]] && destination=export
build=$(date -u +%Y%m%d%H%M)
out=build/release
rm -rf "$out" && mkdir -p "$out"
xcodebuild archive -project Archy.xcodeproj -scheme Archy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$out/archy.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build" -quiet
cat > "$out/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$destination</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>B37KYDJP8C</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$out/archy.xcarchive" -exportOptionsPlist "$out/export.plist" \
  -exportPath "$out" -allowProvisioningUpdates -quiet
if [[ $destination == upload ]]; then
  echo "Uploaded build $build. It appears in TestFlight after Apple finishes processing (about 10 to 30 minutes)."
else
  echo "Wrote $out/archy.ipa (build $build)."
fi
