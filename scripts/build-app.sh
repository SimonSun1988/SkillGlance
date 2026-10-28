#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift scripts/generate-icon.swift .build/SkillGlance.iconset Sources/SkillsUsageApp/Resources Assets/Brand/skillglance-b-source.png
swift build -c release --arch arm64 -Xswiftc -file-prefix-map -Xswiftc "$PWD=." -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
binary_dir="$(swift build -c release --arch arm64 --show-bin-path)"
mkdir -p .build dist
stage_root="$(mktemp -d "$PWD/.build/app-stage.XXXXXX")"
trap 'rm -rf -- "$stage_root"' EXIT
app_dir="$stage_root/SkillGlance.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SkillsUsage" "$app_dir/Contents/MacOS/SkillsUsage"
strip -S "$app_dir/Contents/MacOS/SkillsUsage"
[[ "$(lipo -archs "$app_dir/Contents/MacOS/SkillsUsage")" == arm64 ]]
cp Sources/SkillsUsageApp/Resources/*.png "$app_dir/Contents/Resources/"
for localization in Sources/SkillsUsageApp/Resources/*.lproj; do
  plutil -lint "$localization/Localizable.strings"
  ditto "$localization" "$app_dir/Contents/Resources/${localization:t}"
done
iconutil -c icns .build/SkillGlance.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>SkillsUsage</string>
<key>CFBundleIdentifier</key><string>local.simonsun.skills-usage</string>
<key>CFBundleName</key><string>SkillGlance</string>
<key>CFBundleDisplayName</key><string>SkillGlance</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
if [[ -e "$PWD/dist/SkillGlance.app" ]]; then
  previous="$(mktemp -d "$PWD/.build/previous-app.XXXXXX")"
  mv "$PWD/dist/SkillGlance.app" "$previous/"
fi
mv "$app_dir" "$PWD/dist/SkillGlance.app"
printf 'Built %s\n' "$PWD/dist/SkillGlance.app"
