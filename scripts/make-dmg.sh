#!/bin/sh
# Packs .build/Elemelek.app into a compressed DMG with a link to /Applications.
set -eu
OUT=${1:-.build/Elemelek.dmg}
cd "$(dirname "$0")/.."
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R .build/Elemelek.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname Elemelek -srcfolder "$STAGE" -format UDZO "$OUT"
echo "$OUT"
