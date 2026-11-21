# SPDX-License-Identifier: AGPL-3.0-only
"""检查字体：游戏源码字符串里的每个字都在 assets/fonts/ycw-serif.ttf 里；字体是 TrueType 轮廓；
名字表声明 OFL；许可证文件齐全。"""
import os
import sys

from fontTools.ttLib import TTFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luastrings import ROOT, used_chars  # noqa: E402

FONT = os.path.join(ROOT, "assets", "fonts", "ycw-serif.ttf")
LIC = os.path.join(ROOT, "assets", "fonts", "OFL.txt")


def main():
    problems = []
    f = TTFont(FONT)
    cmap = f.getBestCmap()
    missing = sorted(c for c in used_chars() if ord(c) not in cmap and c != " ")
    if missing:
        problems.append("字体缺字：" + "".join(missing))
    if os.path.getsize(FONT) >= 200 * 1024:
        problems.append("字体文件超过 200 KB")
    if "glyf" not in f:
        problems.append("字体不是 TrueType 轮廓（Dora 的 stb_truetype 读 TrueType 最稳）")
    lic = f["name"].getDebugName(13) or ""
    if "Open Font License" not in lic:
        problems.append("字体名字表没有 OFL 声明")
    text = open(LIC, encoding="utf-8").read()
    if "SIL OPEN FONT LICENSE Version 1.1" not in text or "Adobe" not in text:
        problems.append("assets/fonts/OFL.txt 不完整")
    for p in problems:
        print("FAIL", p)
    print(f"字体 {os.path.getsize(FONT)} 字节，覆盖 {len(used_chars())} 个用到的字符")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
