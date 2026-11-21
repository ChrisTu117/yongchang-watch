#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 准备 Lua 5.5（Dora SSR 1.10 的 LoveNode 用 Lua 5.5 运行游戏代码），用来在本机检查兼容性。
# 已有 lua5.5 或设置了 LUA55 就直接用；否则从 lua.org 下载 5.5.1 源码，核对 SHA-256 后编译到 build/lua55/。
# 输出：最后一行是可执行文件路径。
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${LUA55:-}" ] && [ -x "$LUA55" ]; then echo "$LUA55"; exit 0; fi
if command -v lua5.5 >/dev/null 2>&1; then command -v lua5.5; exit 0; fi
if [ -x build/lua55/lua-5.5.1/src/lua ]; then echo "$PWD/build/lua55/lua-5.5.1/src/lua"; exit 0; fi
SHA=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
mkdir -p build/lua55
cd build/lua55
curl -sSL -o lua-5.5.1.tar.gz https://www.lua.org/ftp/lua-5.5.1.tar.gz
echo "$SHA  lua-5.5.1.tar.gz" | sha256sum -c --quiet
tar xzf lua-5.5.1.tar.gz
make -C lua-5.5.1 linux >/dev/null
echo "$PWD/lua-5.5.1/src/lua"
