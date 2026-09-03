#!/bin/bash
# A wrapper around Tuist/xcodebuild.
# It always regenerates the project: Tuist freezes the file list at generation
# time, so without this step a new .swift silently stays out of the build —
# and the tests then "pass" simply by not existing.
set -euo pipefail
cd "$(dirname "$0")"

WS=Cleaner.xcworkspace
DEST='platform=macOS'

gen() { tuist generate --no-open >/dev/null; }

case "${1:-test}" in
  test)
    gen
    xcodebuild -workspace "$WS" -scheme CleanerKit -destination "$DEST" test 2>&1 \
      | grep -E "error:|failed|Executed .* test|\*\* TEST" | sed 's/^/  /'
    ;;
  build)
    gen
    xcodebuild -workspace "$WS" -scheme Cleaner -destination "$DEST" build 2>&1 \
      | grep -E "error:|\*\* BUILD" | sed 's/^/  /'
    ;;
  run)
    gen
    xcodebuild -workspace "$WS" -scheme Cleaner -destination "$DEST" build 2>&1 \
      | grep -E "error:|\*\* BUILD" | sed 's/^/  /'
    open "$(xcodebuild -workspace "$WS" -scheme Cleaner -destination "$DEST" \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Cleaner.app"
    ;;
  loc)
    gen
    python3 tools/check-localization.py
    ;;
  gen) gen; echo "  project generated" ;;
  *) echo "usage: ./make.sh [test|build|run|loc|gen]" >&2; exit 2 ;;
esac
