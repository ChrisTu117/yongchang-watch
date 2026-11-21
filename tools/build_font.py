# SPDX-License-Identifier: AGPL-3.0-only
"""生成游戏用的中文字体子集 assets/fonts/ycw-serif.ttf。

来源：Noto Serif CJK SC Bold（SIL Open Font License 1.1，© Adobe）。本机路径默认取 Debian 的
fonts-noto-cjk 包；也可以用 --source 指定从 https://github.com/notofonts/noto-cjk 下载的同名字体。
处理：只保留游戏文字用到的字符（tools/luastrings.py 从源码字符串里收集），CFF 轮廓转成 TrueType
二次曲线（Dora SSR 用 stb_truetype 读字体，TrueType 轮廓兼容性最好），字体改名以示这是修改版。
用法：python3 tools/build_font.py [--source 路径]
"""
import argparse
import os
import sys

from fontTools import subset
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont, newTable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luastrings import ROOT, used_chars  # noqa: E402

DEFAULT_SRC = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"
OUT = os.path.join(ROOT, "assets", "fonts", "ycw-serif.ttf")
FAMILY = "YCW Serif SC Subset"


def load_sc(path):
    if path.lower().endswith(".ttc"):
        col = TTCollection(path)
        for f in col.fonts:
            if f["name"].getDebugName(1) == "Noto Serif CJK SC":
                return f
        raise SystemExit("TTC 里没有 Noto Serif CJK SC")
    return TTFont(path)


def otf_to_ttf(font, max_err=1.0):
    order = font.getGlyphOrder()
    font["loca"] = newTable("loca")
    font["glyf"] = glyf = newTable("glyf")
    glyf.glyphOrder = order
    glyf.glyphs = {}
    gs = font.getGlyphSet()
    for name in order:
        pen = TTGlyphPen(gs)
        gs[name].draw(Cu2QuPen(pen, max_err, reverse_direction=True))
        glyf[name] = pen.glyph()
    font["maxp"] = maxp = newTable("maxp")
    maxp.tableVersion = 0x00010000
    for attr in ("maxZones", "maxTwilightPoints", "maxStorage", "maxFunctionDefs", "maxInstructionDefs",
                 "maxStackElements", "maxSizeOfInstructions", "maxComponentElements"):
        setattr(maxp, attr, 1 if attr == "maxZones" else 0)
    post = font["post"]
    post.formatType = 3.0
    font["head"].glyphDataFormat = 0
    del font["CFF "]
    for t in ("VORG", "VVAR"):
        if t in font:
            del font[t]
    font.sfntVersion = "\x00\x01\x00\x00"


def rename(font):
    name = font["name"]
    desc = ("Subset of Noto Serif CJK SC Bold made for the game Yongchang Watch: only the characters the game "
            "uses, outlines converted to TrueType. Licensed under the SIL Open Font License 1.1.")
    for rec in list(name.names):
        if rec.nameID in (1, 16):
            rec.string = FAMILY
        elif rec.nameID in (2, 17):
            rec.string = "Bold"
        elif rec.nameID == 4:
            rec.string = FAMILY + " Bold"
        elif rec.nameID == 6:
            rec.string = "YCWSerifSCSubset-Bold"
        elif rec.nameID == 3:
            rec.string = "YCWSerifSCSubset-Bold;subset"
    name.setName(desc, 10, 3, 1, 0x409)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=DEFAULT_SRC)
    args = ap.parse_args()
    font = load_sc(args.source)
    chars = used_chars()
    opts = subset.Options()
    opts.layout_features = []
    opts.hinting = False
    opts.desubroutinize = True
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=[ord(c) for c in chars])
    sub.subset(font)
    otf_to_ttf(font)
    rename(font)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    font.save(OUT)
    cmap = TTFont(OUT).getBestCmap()
    missing = sorted(c for c in chars if ord(c) not in cmap)
    print(f"{OUT}: {os.path.getsize(OUT)} bytes, {len(chars)} chars, missing in source: {''.join(missing)!r}")


if __name__ == "__main__":
    main()
