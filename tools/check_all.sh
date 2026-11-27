#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 一键检查（仓库根目录运行）：bash tools/check_all.sh
# 依次：LuaJIT 单元测试 → Lua 5.5 单元测试 → Dora 兼容静态检查 → 字体 → LÖVE 端到端试玩 →
#       Dora 实机运行（有 Dora 时）→ 打包与包结构 → 开发者日志发布版 → 说法核对
# 需要：luajit、love 11.5、xvfb-run、python3（含 fontTools）、ffmpeg、zip；Lua 5.5 由 tools/get_lua55.sh 准备。
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/reports
rm -f build/reports/*.status

run() {  # run <步骤名> <命令...>
  local name="$1"; shift
  echo "== $name"
  "$@" > "build/reports/$name.txt" 2>&1
  local code=$?
  if [ $code -eq 0 ]; then echo "PASS" > "build/reports/$name.status"; else echo "FAIL (exit $code)" > "build/reports/$name.status"; fi
  tail -n 4 "build/reports/$name.txt"
  cat "build/reports/$name.status"
}

LUA55="$(bash tools/get_lua55.sh | tail -1)"
run unit_luajit luajit tests/run.lua
run unit_lua55 "$LUA55" tests/run.lua
run cross_lua bash -c "diff <(luajit tools/sim_signature.lua) <(\"$LUA55\" tools/sim_signature.lua) && luajit tools/sim_signature.lua"
run dora_lint python3 tools/check_dora_compat.py "$LUA55"
run font python3 tools/check_font.py
run autotest bash tools/run_autotest.sh
if [ -x "${DORA_BIN:-/var/tmp/osgj-tools/dora-ssr-v1.10.2-linux-x86_64.AppImage}" ]; then
  run dora_runtime bash tools/check_dora_runtime.sh
else
  echo "== dora_runtime"; echo "SKIP 没有 Dora 可执行文件（设置 DORA_BIN）" | tee build/reports/dora_runtime.status
fi
run release bash -c 'bash tools/build_release.sh && python3 tools/check_release.py'
run devlog_export python3 tools/export_devlogs.py
echo "== claims"
python3 tools/check_claims.py | tee build/reports/claims.txt
exit "${PIPESTATUS[0]}"
