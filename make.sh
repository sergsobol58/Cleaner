#!/bin/bash
# Обёртка над Tuist/xcodebuild.
# Всегда перегенерирует проект: Tuist фиксирует список файлов при генерации,
# и новый .swift без этого шага молча не попадёт в сборку — тесты тогда
# «проходят», просто не существуя.
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
  gen) gen; echo "  проект сгенерирован" ;;
  *) echo "использование: ./make.sh [test|build|run|gen]" >&2; exit 2 ;;
esac
