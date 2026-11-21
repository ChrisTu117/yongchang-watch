# SPDX-License-Identifier: AGPL-3.0-only
"""检查打好的发行包结构（不运行 Windows 程序）：
- .love：含 main.lua、conf.lua、字体、音效，不含测试和工具；
- win64.zip：融合 exe 是 64 位 PE 文件、版本信息为 LÖVE 11.5；exe = 官方 love.exe 原样 + 本次 .love 包；
  运行库 DLL 与 LÖVE 官方 11.5 Windows 包（SHA-256 固定）逐字节相同；带许可证和说明；
- dora.zip：根目录有 init.lua、main.lua、conf.lua。
"""
import glob
import hashlib
import io
import os
import struct
import sys
import zipfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DLLS = ["love.dll", "lua51.dll", "SDL2.dll", "OpenAL32.dll", "mpg123.dll", "msvcp120.dll", "msvcr120.dll"]
# LÖVE 11.5 官方发布页 https://github.com/love2d/love/releases/tag/11.5 的 love-11.5-win64.zip
LOVE_WIN64_SHA256 = "ba6e56be2685e53c817749c4a5007f51137136fe5a3ab64920508babc2e74369"


def version_string(pe_bytes, key):
    """从 PE 文件的版本资源里取一个字符串（例如 ProductVersion）。"""
    k = key.encode("utf-16-le") + b"\x00\x00"
    i = pe_bytes.find(k)
    if i < 0:
        return None
    j = i + len(k)
    while j % 4:
        j += 1
    return pe_bytes[j:j + 80].decode("utf-16-le", errors="replace").split("\x00")[0]


def version():
    for line in open(os.path.join(ROOT, "src", "version.lua"), encoding="utf-8"):
        if line.startswith("local VERSION"):
            return line.split('"')[1]


def need(cond, msg, problems):
    if not cond:
        problems.append(msg)


def main():
    v = version()
    b = os.path.join(ROOT, "build")
    problems = []
    love = os.path.join(b, f"YongchangWatch-{v}.love")
    need(os.path.exists(love), "缺少 .love 包", problems)
    if os.path.exists(love):
        names = zipfile.ZipFile(love).namelist()
        for n in ["main.lua", "conf.lua", "assets/fonts/ycw-serif.ttf", "assets/sfx/music_night.ogg", "LICENSE",
                  "LICENSE-ASSETS", "src/sim/world.lua"]:
            need(n in names, f".love 缺 {n}", problems)
        need(not any(n.startswith(("tests/", "tools/")) for n in names), ".love 里不该有测试和工具", problems)

    win = os.path.join(b, f"YongchangWatch-{v}-win64.zip")
    need(os.path.exists(win), "缺少 Windows 包", problems)
    if os.path.exists(win):
        z = zipfile.ZipFile(win)
        names = [n.split("/", 1)[1] for n in z.namelist() if "/" in n and not n.endswith("/")]
        for n in DLLS + ["YongchangWatch.exe", "README.txt", "LICENSE", "LICENSE-ASSETS", "FONT-OFL.txt",
                         "LOVE-license.txt"]:
            need(n in names, f"Windows 包缺 {n}", problems)
        exe = z.read("YongchangWatch-win64/YongchangWatch.exe")
        need(exe[:2] == b"MZ", "exe 不是 PE 文件", problems)
        pe = struct.unpack_from("<I", exe, 0x3C)[0]
        need(exe[pe:pe + 4] == b"PE\0\0", "exe 的 PE 头不对", problems)
        machine = struct.unpack_from("<H", exe, pe + 4)[0]
        need(machine == 0x8664, "exe 不是 x64", problems)
        need(version_string(exe, "ProductVersion") == "11.5", "exe 的版本信息不是 LÖVE 11.5", problems)
        try:
            inner = zipfile.ZipFile(io.BytesIO(exe))
            need("main.lua" in inner.namelist(), "融合 exe 里找不到 main.lua", problems)
        except zipfile.BadZipFile:
            problems.append("融合 exe 尾部不是 zip 游戏包")
        # 和 LÖVE 官方 Windows 包逐字节比对：exe = 官方 love.exe + 本作品 .love（与 Linux 端到端测试用的是同一份源码）；
        # 运行库 DLL 与官方包完全相同。这样不在 Windows 上运行也能确认没有拼错文件。
        official = os.environ.get("LOVE_WIN64_ZIP", "/var/tmp/osgj-tools/love-11.5-win64.zip")
        if not os.path.exists(official):
            problems.append(f"找不到官方 LÖVE 11.5 Windows 包 {official}，无法逐字节比对（设置 LOVE_WIN64_ZIP）")
        else:
            data = open(official, "rb").read()
            need(hashlib.sha256(data).hexdigest() == LOVE_WIN64_SHA256, "官方 LÖVE Windows 包的 SHA-256 不符", problems)
            oz = zipfile.ZipFile(io.BytesIO(data))
            love_exe = oz.read("love-11.5-win64/love.exe")
            need(exe[:len(love_exe)] == love_exe, "exe 开头不是官方 love.exe 原样", problems)
            if os.path.exists(love):
                need(exe[len(love_exe):] == open(love, "rb").read(), "exe 结尾不是本次打出的 .love 包", problems)
            for d in DLLS:
                need(z.read("YongchangWatch-win64/" + d) == oz.read("love-11.5-win64/" + d), f"{d} 与官方包不同", problems)
            need(version_string(love_exe, "ProductVersion") == "11.5", "官方 love.exe 版本不是 11.5", problems)
    dora = os.path.join(b, f"YongchangWatch-{v}-dora.zip")
    need(os.path.exists(dora), "缺少 Dora 包", problems)
    if os.path.exists(dora):
        names = zipfile.ZipFile(dora).namelist()
        for n in ["init.lua", "main.lua", "conf.lua", "README.md", "LICENSE", "LICENSE-ASSETS"]:
            need("YongchangWatch/" + n in names, f"Dora 包缺 {n}", problems)
    for p in problems:
        print("FAIL", p)
    for f in sorted(glob.glob(os.path.join(b, "YongchangWatch-*"))):
        print(os.path.basename(f), os.path.getsize(f))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
