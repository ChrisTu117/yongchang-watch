#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 在 Dora SSR 1.10 的 Linux 版里实际运行本项目（根目录 init.lua → LoveNode("main.lua")），并用真实鼠标键盘事件操作：
#   标题点“从第一夜开始” → 空格翻完剧情 → 教学：望向海面、点敌台、开西门迎百姓 → Esc 菜单“返回标题” → “退出游戏”。
# 每一步都从 Dora 日志里核对游戏打出的进度行（[永昌守望] scene / tutorial step），最后确认日志里没有 Lua 报错。
# 需要：DORA_BIN 指向 Dora 可执行文件或官方 AppImage；Xvfb、xdotool、ffmpeg。用临时 HOME，不碰你自己的 Dora 设置。
# 输出：build/reports/dora_runtime-result.txt、build/dora/*.png
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
DORA_BIN="${DORA_BIN:-/var/tmp/osgj-tools/dora-ssr-v1.10.2-linux-x86_64.AppImage}"
[ -x "$DORA_BIN" ] || { echo "SKIP 找不到 Dora（设置 DORA_BIN）"; exit 3; }
OUT=build/dora; mkdir -p "$OUT" build/reports; rm -f "$OUT"/*.png
TMPH="$(mktemp -d)"; DISP=":58"
RESULT=build/reports/dora_runtime-result.txt; : > "$RESULT"
cleanup() {
  [ -n "${CLI:-}" ] && HOME="$TMPH" timeout 20 "$CLI" --asset "$ASSET" cli stop >/dev/null 2>&1
  [ -n "${DPID:-}" ] && kill "$DPID" 2>/dev/null
  [ -n "${XPID:-}" ] && kill "$XPID" 2>/dev/null
  wait 2>/dev/null; rm -rf "$TMPH"
}
trap cleanup EXIT
pause() { timeout "$1" tail -f /dev/null; }
log() { echo "$*" | tee -a "$RESULT"; }
FAIL=0
ok() { if eval "$2"; then log "PASS $1"; else log "FAIL $1"; FAIL=1; fi; }

Xvfb "$DISP" -screen 0 1280x720x24 -nolisten tcp >/dev/null 2>&1 & XPID=$!
pause 1
HOME="$TMPH" DISPLAY="$DISP" "$DORA_BIN" > "$TMPH/dora-stdout.txt" 2>&1 & DPID=$!
for _ in $(seq 1 60); do grep -q "is ready" "$TMPH/dora-stdout.txt" 2>/dev/null && break; pause 1; done
# AppImage 挂载后的真实可执行文件和资源目录
for _ in $(seq 1 10); do
  PID="$(pgrep -n -f -- '--asset .*Assets' || true)"; [ -n "$PID" ] && break; pause 1
done
CLI="$(readlink -f /proc/$PID/exe 2>/dev/null)"; ASSET="$(tr '\0' '\n' < /proc/$PID/cmdline 2>/dev/null | sed -n '3p')"
[ -n "$CLI" ] && [ -d "$ASSET" ] || { log "FAIL Dora 没有启动"; tail -20 "$TMPH/dora-stdout.txt"; exit 1; }
dora() { HOME="$TMPH" timeout 60 "$CLI" --asset "$ASSET" cli "$@" 2>&1 | grep -v -E '^ALSA|^\[ALSOFT\]'; }
VERSION="$(dora status | sed -n 's/^Dora SSR: //p')"
log "dora_version=$VERSION"
export DISPLAY="$DISP"
shot() { ffmpeg -loglevel error -y -f x11grab -video_size 1280x720 -i "$DISP" -frames:v 1 "$OUT/$1.png"; }
# 逻辑坐标（960x540）→ 屏幕坐标：与 init.lua 的适配一致（游戏放在 Dora 底部 50 高工具栏上方）
K=$(python3 -c "print((720-50)/540)")
to() { python3 -c "k=$K; print(round((1280-960*k)/2+$1*k), round($2*k))"; }
click() { read -r X Y < <(to "$1" "$2"); xdotool mousemove "$X" "$Y"; pause 0.2; xdotool mousedown 1; pause 0.12; xdotool mouseup 1; pause 0.4; }
move() { read -r X Y < <(to "$1" "$2"); xdotool mousemove "$X" "$Y"; }
waitlog() { # waitlog <文本> <秒>
  for _ in $(seq 1 "$2"); do dora log -n 300 | grep -q -- "$1" && return 0; pause 1; done; return 1; }

dora run -p "$REPO" >/dev/null
ok "Dora 载入根目录 main.lua（LoveNode）" 'waitlog "resolved boot: main.lua" 15'
ok "游戏画出第一帧" 'waitlog "first render submitted" 15'
ok "进入标题" 'waitlog "scene: title" 10'
pause 1; shot 01-title
click 480 320
ok "鼠标点击“从第一夜开始”进入剧情" 'waitlog "scene: story" 10'
for _ in 1 2 3; do xdotool key space; pause 0.5; done
ok "空格翻完剧情进入第一夜" 'waitlog "scene: battle" 10'
move 880 270
ok "教学 1：鼠标望向海面" 'waitlog "tutorial step 2" 10'
shot 02-tutorial
click 560 175
ok "教学 2：点击敌台安排弓手" 'waitlog "tutorial step 3" 10'
click 300 270
ok "教学 3：点击西门迎入百姓" 'waitlog "tutorial step 4" 60'
shot 03-tutorial-done
xdotool key Escape; pause 0.8; shot 04-menu
click 480 290
ok "Esc 菜单“返回标题”" '[ "$(dora log -n 300 | grep -c "scene: title")" -ge 2 ]'
click 480 420
pause 2; shot 05-quit
LOG="$(dora log -n 400)"
echo "$LOG" > build/reports/dora_runtime-log.txt
ok "日志里没有 Lua 报错" '! echo "$LOG" | grep -i -E "error|traceback|stack" | grep -v -i -E "DoraSchemaMeta|audio|SoLoud" | grep -q .'
[ $FAIL -eq 0 ] && log "DORA RUNTIME PASS" || log "DORA RUNTIME FAIL"
exit $FAIL
