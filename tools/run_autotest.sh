#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 在虚拟显示器里用 LÖVE 11.5 从头玩到尾（src/autotest.lua），并保存截图和结果。
# 需要：love（11.5）、xvfb-run。输出：build/reports/autotest.txt、build/screenshots/*.png
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/reports build/screenshots
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOVE_VERSION="$(love --version 2>/dev/null | head -1)"
echo "$LOVE_VERSION" > build/reports/love-version.txt
XDG_DATA_HOME="$TMP" timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" love . --autotest > "$TMP/stdout.txt" 2>&1
CODE=$?
SAVE="$TMP/love/yongchang-watch/autotest"
{
  echo "love_version=$LOVE_VERSION"
  echo "exit_code=$CODE"
  grep -E '^\[(PASS|FAIL)\]|^AUTOTEST' "$TMP/stdout.txt"
  [ -f "$SAVE/result.txt" ] && cat "$SAVE/result.txt"
} > build/reports/autotest.txt
cp "$SAVE"/*.png build/screenshots/ 2>/dev/null || true
grep -E '^\[FAIL\]|^AUTOTEST' "$TMP/stdout.txt"
echo "exit_code=$CODE"
exit $CODE
