#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage=$(mktemp -d /tmp/mdmini-previews.XXXXXX)
trap 'rm -rf "$stage"' EXIT
swiftc -D README_PREVIEW Sources/*.swift -o "$stage/render-previews" -framework AppKit -framework UniformTypeIdentifiers
"$stage/render-previews" --render-readme
