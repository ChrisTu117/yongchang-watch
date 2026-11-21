# SPDX-License-Identifier: AGPL-3.0-only
"""Dora SSR 1.10 兼容性静态检查（依据 Dora 官方文档 using-love2d 与 love-game-development 指南）。

1. 游戏代码（main.lua、conf.lua、src/）不得用 LuaJIT 专有功能（ffi、jit.*、setfenv、bit.*）、
   原生模块，也不得引用 Dora 接口（Dora、LoveNode、Director、Content……）。
2. 不用 Dora 明确不开放或未完整支持的 LÖVE 接口：love.window 的关闭/移动/最小化/最大化/恢复/
   attention/icon/message box、love.physics、love.joystick 震动、自定义着色器、多层/mipmap Canvas。
3. init.lua（Dora 入口）只用 Dora 接口，不用 love.*，并且用 LoveNode 加载根目录 main.lua。
4. 所有 .lua 都能被 Lua 5.5 编译（需要 Lua 5.5；路径由 tools/get_lua55.sh 给出）。
用法：python3 tools/check_dora_compat.py [lua5.5 路径]
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luastrings import ROOT, game_files  # noqa: E402

BANNED_GAME = [
    (r"\brequire\s*\(?\s*[\"']ffi[\"']", "LuaJIT ffi"),
    (r"\bjit\.", "LuaJIT jit 库"),
    (r"\bsetfenv\b|\bgetfenv\b", "setfenv/getfenv"),
    (r"\bbit\.", "LuaJIT bit 库"),
    (r"\bloadstring\b", "loadstring（Lua 5.5 没有）"),
    (r"\bmath\.pow\b|\btable\.getn\b|\bstring\.gfind\b", "Lua 5.1 旧函数"),
    (r"//", "整除运算符（LuaJIT 没有）"),
    (r"\bDora\b|\bLoveNode\b|\bDirector\b|\bContent\.|\bView\.size", "Dora 接口（游戏代码里不能用）"),
    (r"love\.window\.(close|setPosition|minimize|maximize|restore|requestAttention|setIcon|showMessageBox)",
     "Dora 不开放的 love.window 动作"),
    (r"love\.physics", "love.physics（Dora 仅部分兼容）"),
    (r"newShader", "自定义着色器（避免 Dora 翻译差异）"),
    (r"setVibration", "手柄震动（Dora 待设备认证）"),
    (r"newArrayImage|newVolumeImage|newCubeImage|mipmaps\s*=", "多层/mipmap 纹理"),
]


def strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


def strip_strings(src):
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
    return re.sub(r"'(\\.|[^'\\])*'", "''", src)


def main():
    problems = []
    files = game_files()
    for p in files:
        code = strip_strings(strip_comments(open(p, encoding="utf-8").read()))
        rel = os.path.relpath(p, ROOT)
        for pat, why in BANNED_GAME:
            for m in re.finditer(pat, code):
                line = code[:m.start()].count("\n") + 1
                problems.append(f"{rel}:{line}: {why}")
    init = os.path.join(ROOT, "init.lua")
    if not os.path.exists(init):
        problems.append("缺少 Dora 入口 init.lua")
    else:
        code = strip_comments(open(init, encoding="utf-8").read())
        if re.search(r"\blove\.", code):
            problems.append("init.lua 里用了 love.*（Dora 入口只能用 Dora 接口）")
        if not re.search(r'LoveNode\(\s*"main\.lua"\s*\)', code):
            problems.append('init.lua 没有用 LoveNode("main.lua") 加载根目录的 LÖVE 项目')
    conf = open(os.path.join(ROOT, "conf.lua"), encoding="utf-8").read()
    if not re.search(r't\.version\s*=\s*"11\.5"', conf):
        problems.append('conf.lua 没有声明 t.version = "11.5"')

    lua55 = sys.argv[1] if len(sys.argv) > 1 else None
    compiled = 0
    if lua55:
        luac = os.path.join(os.path.dirname(lua55), "luac")
        all_lua = files + [init] + [os.path.join(ROOT, "tests", f) for f in os.listdir(os.path.join(ROOT, "tests"))
                                    if f.endswith(".lua")]
        for p in all_lua:
            r = subprocess.run([luac, "-p", p], capture_output=True, text=True)
            if r.returncode != 0:
                problems.append(f"Lua 5.5 编译失败：{r.stderr.strip()}")
            compiled += 1
    for p in problems:
        print("FAIL", p)
    print(f"检查了 {len(files)} 个游戏文件；Lua 5.5 编译 {compiled} 个文件" + ("" if lua55 else "（未提供 Lua 5.5，跳过编译）"))
    if problems:
        sys.exit(1)
    if not lua55:
        sys.exit(2)
    print("OK")


if __name__ == "__main__":
    main()
