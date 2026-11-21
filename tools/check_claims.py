# SPDX-License-Identifier: AGPL-3.0-only
"""说法核对：README、提交表草稿、开发者日志、AI 声明、中文说明里，每条事实性说法后面都标了〔C编号〕或〔M编号〕。
本脚本：
1. 找出这些文件里出现的全部编号，确认每个编号都在下面的 CLAIMS 里有对应检查；
2. 逐条运行检查（C 开头是自动检查，多数读取 tools/check_all.sh 本轮写下的 build/reports/*；
   M 开头是需要人在真机上确认的项目，读 docs/人工检查记录.md）；
3. 打印表格。退出码：0 全部通过（人工项可以标“跳过”并写明原因）；2 只剩人工项待确认；1 有自动检查没通过或编号没有检查。
"""
import glob
import hashlib
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
REP = os.path.join(ROOT, "build", "reports")
DOCS = ["README.md", "docs/提交表草稿.md", "docs/AI使用与素材声明.md", "docs/中文说明.md"] + \
       sorted(os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, "docs", "devlog", "*.md")))
TAG = re.compile(r"〔([CM]\d+)〕")


def read(rel):
    p = os.path.join(ROOT, rel)
    return open(p, encoding="utf-8").read() if os.path.exists(p) else ""


def status(step):
    t = read(os.path.join("build", "reports", step + ".status")).strip()
    return t.startswith("PASS"), (t.splitlines()[0] if t else "本轮没有运行 " + step)


def unit_file_ok(name):
    out = read("build/reports/unit_luajit.txt") + "\n" + read("build/reports/unit_lua55.txt")
    lj = re.search(r"^" + name + r"\s+ok$", read("build/reports/unit_luajit.txt"), re.M)
    l5 = re.search(r"^" + name + r"\s+ok$", read("build/reports/unit_lua55.txt"), re.M)
    return bool(lj and l5), f"{name}: LuaJIT {'ok' if lj else '未通过'}，Lua 5.5 {'ok' if l5 else '未通过'}" if out else "没有单元测试报告"


def tracked_files():
    try:
        r = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
        files = r.stdout.split()
        if files:
            return files
    except Exception:
        pass
    out = []
    for d, _, fs in os.walk(ROOT):
        if "/.git" in d or "/build" in d:
            continue
        out += [os.path.relpath(os.path.join(d, f), ROOT) for f in fs]
    return out


# ---------------------------------------------------------------- 各项检查
def c1():
    lic = read("LICENSE")
    if "GNU AFFERO GENERAL PUBLIC LICENSE" not in lic or "Version 3, 19 November 2007" not in lic:
        return False, "LICENSE 不是 AGPL-3.0 全文"
    bad = []
    for f in tracked_files():
        if f.endswith((".lua", ".py", ".sh")):
            head = "".join(open(os.path.join(ROOT, f), encoding="utf-8").readlines()[:3])
            if "SPDX-License-Identifier: AGPL-3.0-only" not in head:
                bad.append(f)
    return (not bad), ("所有代码文件都有 AGPL-3.0 标注" if not bad else "缺少标注：" + ", ".join(bad))


def asset_files():
    out = []
    for d, _, fs in os.walk(os.path.join(ROOT, "assets")):
        out += [os.path.relpath(os.path.join(d, f), ROOT) for f in fs]
    return sorted(out)


def c2():
    if "Attribution 4.0 International" not in read("LICENSE-ASSETS"):
        return False, "LICENSE-ASSETS 不是 CC BY 4.0 全文"
    manifest = read("ASSETS.md")
    sfx = [f for f in asset_files() if f.startswith("assets/sfx/")]
    missing = [f for f in sfx if f"`{f}`" not in manifest]
    if missing:
        return False, "ASSETS.md 没列：" + ", ".join(missing)
    # 重新生成一遍，和仓库里的文件逐字节比对，证明音频确实出自本项目脚本
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, YCW_AUDIO_OUT=tmp)
        r = subprocess.run([sys.executable, "tools/gen_audio.py"], cwd=ROOT, env=env, capture_output=True, text=True)
        if r.returncode != 0:
            return False, "重新生成音频失败：" + r.stderr[-200:]
        diff = []
        for f in sfx:
            a = open(os.path.join(ROOT, f), "rb").read()
            p = os.path.join(tmp, os.path.basename(f))
            b = open(p, "rb").read() if os.path.exists(p) else b""
            if hashlib.sha256(a).digest() != hashlib.sha256(b).digest():
                diff.append(os.path.basename(f))
    if diff:
        return False, "重新生成后不一致：" + ", ".join(diff)
    return True, f"{len(sfx)} 个音频都列在 ASSETS.md，且由 tools/gen_audio.py 逐字节重现"


def c4():
    manifest = read("ASSETS.md")
    files = asset_files()
    missing = [f for f in files if f"`{f}`" not in manifest]
    third = re.findall(r"^\| 第三方 \|", manifest, re.M)
    if missing:
        return False, "assets/ 里有未登记文件：" + ", ".join(missing)
    if len(third) != 2:
        return False, "ASSETS.md 第三方条目应只有字体文件和它的许可证两行"
    return True, f"assets/ 共 {len(files)} 个文件全部登记；第三方只有字体"


def c5():
    t = read("build/reports/autotest-result.txt")
    ok = "love_version=LOVE 11.5" in t and "exit_code=0" in t and "AUTOTEST PASS" in t
    m = re.search(r"checks (\d+)/(\d+) passed", t)
    return ok, (f"LÖVE 11.5 端到端测试通过（{m.group(0) if m else ''}）" if ok else "端到端测试未通过或不是 LÖVE 11.5")


def c6():
    a, da = status("unit_lua55")
    b, db = status("dora_lint")
    c, dc = status("cross_lua")
    return a and b and c, f"Lua 5.5 单元测试：{da}；Dora 静态检查：{db}；LuaJIT 与 Lua 5.5 同局结果一致：{dc}"


def c7():
    return status("release")


def c8():
    t = read("build/reports/autotest-result.txt")
    ok = "exit_via=menu" in t and "exit_code=0" in t
    return ok, "从标题菜单“退出游戏”正常退出，退出码 0" if ok else "没有走菜单正常退出"


def c9():
    t = read("build/reports/autotest-result.txt")
    need = ["教学 1：移动鼠标照向海面", "教学 2：点击敌台安排弓手", "教学 3：点击城门打开", "教学 3：迎入百姓",
            "空格暂停", "Esc 打开菜单"]
    miss = [n for n in need if ("PASS " + n) not in t]
    return (not miss), ("教学四步和暂停/菜单都用模拟输入走通" if not miss else "没通过：" + "，".join(miss))


def c13():
    logs = sorted(glob.glob(os.path.join(ROOT, "docs", "devlog", "*.md")))
    texts = [re.sub(r"\s+", "", open(p, encoding="utf-8").read()) for p in logs]
    if len(logs) < 3:
        return False, f"只有 {len(logs)} 篇开发者日志"
    short = [os.path.basename(p) for p, t in zip(logs, texts) if len(t) < 400]
    if short:
        return False, "太短：" + ", ".join(short)

    def grams(t):
        return {t[i:i + 2] for i in range(len(t) - 1)}

    worst = 0.0
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            a, b = grams(texts[i]), grams(texts[j])
            worst = max(worst, len(a & b) / max(1, len(a | b)))
    return worst < 0.35, f"{len(logs)} 篇，两两最高相似度 {worst:.2f}（阈值 0.35）"


def c14():
    t = read("docs/AI使用与素材声明.md")
    need = ["## 使用的 AI 工具", "## 用途", "## AI 生成的内容", "## 人工修改与把关", "## 赛前已有的代码、工具与素材",
            "## 第三方素材"]
    miss = [n for n in need if n not in t]
    return (not miss), ("六个部分齐全" if not miss else "缺：" + "，".join(miss))


def c15():
    try:
        r = subprocess.run(["git", "log", "--reverse", "--format=%cI"], cwd=ROOT, capture_output=True, text=True,
                           check=True)
        first = r.stdout.split()[0]
    except Exception:
        return False, "没有 git 历史"
    from datetime import datetime, timezone, timedelta
    t = datetime.fromisoformat(first)
    start = datetime(2026, 11, 21, 9, 30, tzinfo=timezone(timedelta(hours=8)))
    return t >= start, f"第一次提交 {first}（主题公布 2026-11-21 09:30 北京时间）"


def c17():
    """中文说明里引用的数值要和代码一致。"""
    units = read("src/data/units.lua")
    dragon = read("src/scenes/dragon.lua")
    stroke = read("src/sim/stroke.lua")
    bad = []
    expect = [
        (r"D\.beam = \{ len = 430, half = math\.rad\(16\) \}", units, "光束半径 430、半角 16°"),
        (r"D\.wengchengBonus = 1\.6\b", units, "瓮城 1.6 倍"),
        (r"D\.repairCost = 4\b", units, "修门 4 民力"),
        (r"D\.repairTo = 0\.5\b", units, "修好恢复一半"),
        (r"D\.refugee = \{ speed = \d+, patience = 14, reward = 2 \}", units, "百姓等 14 秒、+2 民力"),
        (r"D\.farmEvery = 12\b", units, "屯田 12 秒"),
        (r"local SEGMENTS = 9\b", dragon, "龙九节"),
        (r"Stroke\.N = 16\b", stroke, "取 16 个点"),
    ]
    bad += [label for pat, text, label in expect if not re.search(pat, text)]
    levels = read("src/data/levels.lua")
    durs = [int(x) for x in re.findall(r"duration = (\d+)", levels)]
    if not (len(durs) == 3 and all(100 <= d <= 180 for d in durs)):
        bad.append(f"每夜时长 {durs} 不在约 2～3 分钟范围")
    if len(re.findall(r"^  (archer|gunner|beacon) = \{", units, re.M)) != 3:
        bad.append("守城单位不是三种")
    if len(re.findall(r"^  (raider|runner|brute) +=", units, re.M)) != 3:
        bad.append("来犯者不是三种")
    ending = read("src/scenes/ending.lua")
    if len(re.findall(r"\{ [\d.]+, [\d.]+, [\d.]+ \}", ending.split("local CHARS")[0])) != 5:
        bad.append("终章不是五条龙")
    return (not bad), ("中文说明里的数值与代码一致" if not bad else "不一致：" + "，".join(bad))


def c18():
    t = read("build/reports/dora_runtime.status").strip()
    if t.startswith("SKIP"):
        return "skip", t
    r = read("build/reports/dora_runtime-result.txt")
    m = re.search(r"dora_version=(.*)", r)
    n = len(re.findall(r"^PASS ", r, re.M))
    ok = t.startswith("PASS") and "DORA RUNTIME PASS" in r
    return ok, f"Dora {m.group(1) if m else '?'}：{n} 项通过" if ok else (t or "本轮没有运行")


def manual(mid):
    def f():
        t = read("docs/人工检查记录.md")
        m = re.search(r"^\|\s*" + mid + r"\s*\|[^\n]*", t, re.M)
        if not m:
            return None, "人工检查记录里没有这一项"
        row = m.group(0)
        result = row.rstrip("|").split("|")[-1].strip()
        if "通过" in result and re.search(r"20\d\d-\d\d-\d\d", result):
            return True, row.strip()
        if result.startswith("跳过"):
            return "skip", result
        return None, "待人工确认"
    return f


CLAIMS = {
    "C1": ("代码按 AGPL-3.0 授权", c1),
    "C2": ("自创音频按 CC BY 4.0 授权，可由脚本重现", c2),
    "C3": ("字体是 SIL OFL 1.1 的 Noto Serif CJK 子集，覆盖全部文字", lambda: status("font")),
    "C4": ("除字体外没有第三方素材", c4),
    "C5": ("标准 LÖVE 11.5 项目，能从标题玩到终章", c5),
    "C6": ("Dora 兼容：Lua 5.5 可运行逻辑、静态检查通过、带 init.lua 入口", c6),
    "C7": ("提供 Windows 64 位免安装包（结构检查，并与 LÖVE 官方 11.5 Windows 包逐字节比对）", c7),
    "C8": ("能正常退出", c8),
    "C9": ("有新手引导和操作反馈", c9),
    "C10": ("会玩能赢、不玩必输，“望”和“迎百姓”都有用", lambda: unit_file_ok("test_balance")),
    "C11": ("史实条目都有出处，关卡与剧情说法一致", lambda: unit_file_ok("test_content")),
    "C12": ("“天下太平”笔顺与汉典一致", lambda: unit_file_ok("test_stroke")),
    "C13": ("至少 3 篇内容不重复的开发者日志", c13),
    "C14": ("《AI 使用与素材声明》各部分齐全", c14),
    "C15": ("代码从主题公布后开始写", c15),
    "C16": ("规则与地图：四门、四水门、十二敌台、东门瓮城；民力只来自百姓和屯田", lambda: unit_file_ok("test_world")),
    "C17": ("中文说明里的数值与代码一致", c17),
    "C18": ("在 Dora SSR 1.10 Linux 版实际运行：载入、鼠标键盘操作、菜单退出，日志无报错", c18),
    "M1": ("Windows 10/11 真机运行", manual("M1")),
    "M2": ("Windows 上的 Dora SSR 1.10 运行", manual("M2")),
    "M3": ("演示视频不超过 5 分钟，B 站带「2026 开源游戏开发大赛」标签", manual("M3")),
}


def main():
    used = {}
    for d in DOCS:
        for m in TAG.finditer(read(d)):
            used.setdefault(m.group(1), set()).add(d)
    unknown = sorted(k for k in used if k not in CLAIMS)
    failed, pending = 0, 0
    for k in unknown:
        print(f"FAIL {k}: 文档里出现了这个编号，但没有对应的检查（{', '.join(sorted(used[k]))}）")
        failed += 1
    for k, (desc, fn) in CLAIMS.items():
        try:
            ok, detail = fn()
        except Exception as e:  # noqa: BLE001
            ok, detail = False, f"检查出错：{e}"
        where = "、".join(sorted(used.get(k, []))) or "（文档未引用）"
        tag = "SKIP" if ok == "skip" else ("PASS" if ok else ("PEND" if ok is None else "FAIL"))
        if ok is None:
            pending += 1
        elif ok is False:
            failed += 1
        print(f"{tag} {k} {desc} —— {detail}  [引用：{where}]")
    print(f"自动检查失败 {failed} 项，人工待确认 {pending} 项")
    sys.exit(1 if failed else (2 if pending else 0))


if __name__ == "__main__":
    main()
