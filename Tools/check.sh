#!/bin/zsh
set -eu
cd "${0:A:h}/.."
./build.sh
"output/MD Mini.app/Contents/MacOS/MD Mini" --self-test
stage=$(mktemp -d /tmp/mdmini-check.XXXXXX)
trap 'rm -rf "$stage"' EXIT
swiftc -D FEATURE_TEST Sources/*.swift -o "$stage/feature-check" -framework AppKit -framework UniformTypeIdentifiers
"$stage/feature-check" --feature-test
codesign --verify --verbose=2 "output/MD Mini.app"
