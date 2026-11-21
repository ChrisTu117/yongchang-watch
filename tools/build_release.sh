#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 打包发行版（在仓库根目录运行）：
#   build/YongchangWatch-<版本>.love          跨平台 LÖVE 包（装了 LÖVE 11.5 的电脑都能运行）
#   build/YongchangWatch-<版本>-win64.zip     Windows 10/11 免安装版（LÖVE 官方 11.5 win64 运行库 + 游戏，融合成一个 exe）
#   build/YongchangWatch-<版本>-dora.zip      Dora SSR 1.10 兼容版（项目目录原样打包，入口 init.lua）
# 需要：zip、python3；LÖVE Windows 运行库 love-11.5-win64.zip（官方发布页
#   https://github.com/love2d/love/releases/tag/11.5 ），用 LOVE_WIN64_ZIP 指定路径。
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^local VERSION = "\(.*\)"$/\1/p' src/version.lua)"
[ -n "$VERSION" ] || { echo "src/version.lua 里没有版本号"; exit 1; }
LOVE_WIN64_ZIP="${LOVE_WIN64_ZIP:-/var/tmp/osgj-tools/love-11.5-win64.zip}"
LOVE_WIN64_SHA256="ba6e56be2685e53c817749c4a5007f51137136fe5a3ab64920508babc2e74369"
OUT=build
NAME="YongchangWatch-$VERSION"
rm -rf "$OUT/stage" && mkdir -p "$OUT/stage"

# 运行需要的文件（不含测试和工具）
GAME_FILES=(main.lua conf.lua src assets LICENSE LICENSE-ASSETS ASSETS.md)

# 1) .love
rm -f "$OUT/$NAME.love"
zip -q -9 -X -r "$OUT/$NAME.love" "${GAME_FILES[@]}" -x '*.DS_Store'
echo "built $OUT/$NAME.love"

# 2) Windows
if [ -f "$LOVE_WIN64_ZIP" ]; then
  echo "$LOVE_WIN64_SHA256  $LOVE_WIN64_ZIP" | sha256sum -c --quiet
  W="$OUT/stage/YongchangWatch-win64"
  mkdir -p "$W"
  python3 - "$LOVE_WIN64_ZIP" "$W" <<'EOF'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1]); out = sys.argv[2]
for i in z.infolist():
    if i.is_dir(): continue
    name = os.path.basename(i.filename)
    with open(os.path.join(out, name), "wb") as f: f.write(z.read(i))
EOF
  cat "$W/love.exe" "$OUT/$NAME.love" > "$W/YongchangWatch.exe"
  rm -f "$W/love.exe" "$W/lovec.exe" "$W/readme.txt" "$W/changes.txt" "$W/love.ico"
  mv "$W/license.txt" "$W/LOVE-license.txt"
  cp LICENSE LICENSE-ASSETS ASSETS.md "$W/"
  cp assets/fonts/OFL.txt "$W/FONT-OFL.txt"
  # Windows 记事本友好的 UTF-8（带 BOM）+ CRLF
  python3 - "$W/README.txt" <<'EOF'
import sys
text = """永昌守望（Yongchang Watch）Windows 版

启动：双击 YongchangWatch.exe。不需要安装，也不需要联网。
系统：Windows 10 / 11，64 位。
如果 Windows 提示“已保护你的电脑”，点“更多信息”→“仍要运行”（本程序没有数字签名）。

操作：移动鼠标照亮黑暗；左键点敌台安排守城单位，点城门开关；
      1/2/3 切换弓手、鸟铳、烽火；F 放孔明灯；空格暂停；Esc 菜单（可退出）；M 静音。

授权：游戏代码 AGPL-3.0（LICENSE）；美术与音效 CC BY 4.0（LICENSE-ASSETS、ASSETS.md）；
      字体 SIL OFL 1.1（FONT-OFL.txt）；LÖVE 运行库 zlib 许可（LOVE-license.txt）。
源码：见提交表里的 AtomGit 仓库地址。
"""
open(sys.argv[1], "w", encoding="utf-8-sig", newline="\r\n").write(text)
EOF
  rm -f "$OUT/$NAME-win64.zip"
  (cd "$OUT/stage" && zip -q -9 -X -r "../$NAME-win64.zip" YongchangWatch-win64)
  echo "built $OUT/$NAME-win64.zip"
else
  echo "跳过 Windows 包：找不到 $LOVE_WIN64_ZIP（设置 LOVE_WIN64_ZIP 指向官方 love-11.5-win64.zip）"
fi

# 3) Dora：项目目录原样（入口 init.lua + 根目录 LÖVE 项目）
D="$OUT/stage/YongchangWatch"
mkdir -p "$D"
cp -r init.lua "${GAME_FILES[@]}" README.md "$D/"
rm -f "$D/src/autotest.lua"
rm -f "$OUT/$NAME-dora.zip"
(cd "$OUT/stage" && zip -q -9 -X -r "../$NAME-dora.zip" YongchangWatch)
echo "built $OUT/$NAME-dora.zip"

rm -rf "$OUT/stage"
(cd "$OUT" && sha256sum "$NAME".love "$NAME"-*.zip 2>/dev/null | tee SHA256SUMS.txt)
