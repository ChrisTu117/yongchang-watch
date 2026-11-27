# SPDX-License-Identifier: AGPL-3.0-only
"""把 docs/devlog/ 里的开发者日志导出成公开发布用的版本（大赛要求在公开社交媒体发布至少 3 篇，提交时填链接）。

和仓库里的原文相比只做三件事：
1. 去掉〔C编号〕〔M编号〕。这些编号是给 tools/check_claims.py 用的，对读者没有意义；
2. 标题前加上作品名，正文末尾加一段固定的署名和链接；
3. 另存一份 HTML（只用 h2、p、ul、strong、code、a），方便粘贴到富文本编辑器。
正文的句子一个字都不改，所以仓库原文通过的说法核对（check_claims）对发布版同样成立。
本脚本最后会逐段核对：去掉编号后的原文正文，必须原样出现在发布版里。

输出：build/devlog-public/NN.md、NN.html、NN.title.txt
用法：python3 tools/export_devlogs.py
"""
import glob
import html
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "build", "devlog-public")
TAG = re.compile(r"〔[CM]\d+〕")
FOOTER = [
    "《永昌守望》是队伍“什么都不会”（ChrisTu117）的 2026 开源游戏开发大赛参赛作品，主题「守·望」。"
    "LÖVE 11.5 开发，同一份代码可在 Dora SSR 1.10 中运行；代码 AGPL-3.0，原创音乐音效 CC BY 4.0。",
    "源码：https://atomgit.com/ChrisTu117/yongchang-watch",
    "演示视频：https://www.bilibili.com/video/BV1ap1tzcEEo",
    "开发中使用了 AI 辅助，详见仓库里的《AI 使用与素材声明》。",
]


def inline(text):
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"(https?://[^\s<，。；）]+)", r'<a href="\1">\1</a>', out)
    return out


def to_html(blocks):
    parts = []
    for kind, text in blocks:
        if kind == "h2":
            parts.append(f"<h2>{inline(text)}</h2>")
        elif kind == "ul":
            parts.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in text) + "</ul>")
        else:
            parts.append(f"<p>{inline(text)}</p>")
    return "\n".join(parts) + "\n"


def parse(body):
    blocks = []
    for chunk in re.split(r"\n\s*\n", body.strip()):
        lines = [ln.rstrip() for ln in chunk.splitlines() if ln.strip()]
        if not lines:
            continue
        if len(lines) == 1 and lines[0].startswith("## "):
            blocks.append(("h2", lines[0][3:].strip()))
        elif all(ln.startswith("- ") for ln in lines):
            blocks.append(("ul", [ln[2:].strip() for ln in lines]))
        else:
            blocks.append(("p", "".join(lines)))
    return blocks


def main():
    os.makedirs(OUT, exist_ok=True)
    logs = sorted(glob.glob(os.path.join(ROOT, "docs", "devlog", "*.md")))
    problems = []
    for path in logs:
        num = os.path.basename(path)[:2]
        src = open(path, encoding="utf-8").read()
        head, _, rest = src.partition("\n")
        m = re.match(r"# 开发者日志 (\d+)：(.+)", head)
        if not m:
            problems.append(f"{path}: 第一行不是“# 开发者日志 NN：标题”")
            continue
        title = f"《永昌守望》开发日志{m.group(1)}：{m.group(2).strip()}"
        body = TAG.sub("", rest)
        blocks = parse(body)
        md = "\n\n".join(
            ("## " + t) if k == "h2" else ("\n".join("- " + i for i in t) if k == "ul" else t) for k, t in blocks)
        md += "\n\n---\n\n" + "\n\n".join(FOOTER) + "\n"
        blocks_all = blocks + [("p", f) for f in FOOTER]
        with open(os.path.join(OUT, num + ".md"), "w", encoding="utf-8") as f:
            f.write(md)
        with open(os.path.join(OUT, num + ".html"), "w", encoding="utf-8") as f:
            f.write(to_html(blocks_all))
        with open(os.path.join(OUT, num + ".title.txt"), "w", encoding="utf-8") as f:
            f.write(title + "\n")
        # 核对：原文每一段（去掉编号、合并换行后）都原样在发布版里；发布版里没有残留编号
        flat_md = re.sub(r"\s+", "", md)
        for kind, text in parse(body):
            pieces = text if kind == "ul" else [text]
            for p in pieces:
                if re.sub(r"\s+", "", p) not in flat_md:
                    problems.append(f"{num}: 有一段没有原样出现在发布版里：{p[:30]}…")
        if TAG.search(md) or re.search(r"〔|〕", md):
            problems.append(f"{num}: 发布版里还有编号")
        if len(title) > 40:
            problems.append(f"{num}: 标题 {len(title)} 字，超过 40 字（B 站专栏标题上限）")
        print(f"{num}  {title}  正文 {len(re.sub(chr(92) + 's+', '', md))} 字")
    for p in problems:
        print("FAIL " + p)
    print("DEVLOG EXPORT PASS" if not problems and logs else "DEVLOG EXPORT FAIL")
    return 0 if not problems and logs else 1


if __name__ == "__main__":
    sys.exit(main())
