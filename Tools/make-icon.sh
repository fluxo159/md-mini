#!/bin/zsh
set -eu
cd "${0:A:h}/.."
swift Tools/make-icon.swift Assets/AppIcon.png
stage=$(mktemp -d /tmp/mdmini-icon.XXXXXX)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/AppIcon.png --out "$stage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Assets/AppIcon.png --out "$stage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/AppIcon.iconset" -o Assets/AppIcon.icns
