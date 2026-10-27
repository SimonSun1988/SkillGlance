#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

./scripts/build-app.sh
app_dir="$PWD/dist/SkillGlance.app"
version="$(plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist")"
image_name="SkillGlance-${version}-arm64.dmg"
image_path="$PWD/dist/$image_name"
if [[ -e "$image_path" ]]; then
  print -u2 "Already exists: $image_path. Move the previous DMG before building again."
  exit 1
fi

stage_dir="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
trap 'rm -rf -- "$stage_dir"' EXIT
ditto "$app_dir" "$stage_dir/SkillGlance.app"
ln -s /Applications "$stage_dir/Applications"

hdiutil create -volname SkillGlance -srcfolder "$stage_dir" -fs HFS+ -format UDZO "$image_path"
hdiutil verify "$image_path"
(cd dist && shasum -a 256 "$image_name" > "${image_name}.sha256")
print "Built $image_path"
print "Test distribution: ad-hoc signed; not Developer ID signed or notarized."
