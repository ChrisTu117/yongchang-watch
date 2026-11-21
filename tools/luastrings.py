# SPDX-License-Identifier: AGPL-3.0-only
"""从 Lua 源码里取出所有字符串字面量（跳过注释）。字体子集化和字体覆盖检查共用。"""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GAME_FILES = ["main.lua", "conf.lua"] + sorted(glob.glob(os.path.join(ROOT, "src", "**", "*.lua"), recursive=True))


def game_files():
    out = []
    for f in GAME_FILES:
        p = f if os.path.isabs(f) else os.path.join(ROOT, f)
        if os.path.exists(p):
            out.append(p)
    return out


def strings_in(src):
    """一个够用的 Lua 词法扫描：识别 --注释、--[[长注释]]、"..."、'...'、[[...]]、[==[...]==]。"""
    i, n, out = 0, len(src), []
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + len(m.group(0)))
                i = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j + 1
            continue
        if c in "\"'":
            j, buf = i + 1, []
            while j < n and src[j] != c:
                if src[j] == "\\" and j + 1 < n:
                    buf.append(src[j:j + 2])
                    j += 2
                    continue
                buf.append(src[j])
                j += 1
            out.append("".join(buf))
            i = j + 1
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            out.append(src[i + len(m.group(0)):(n if j < 0 else j)])
            i = n if j < 0 else j + len(close)
            continue
        i += 1
    return out


def used_chars():
    chars = set()
    for p in game_files():
        with open(p, encoding="utf-8") as f:
            for s in strings_in(f.read()):
                chars.update(s)
    # 界面里会用到的 ASCII 与数字（拼出来的数字、字母按键提示等）
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update("★☆·「」…—×％＋－")
    return {c for c in chars if c not in "\n\r\t"}
