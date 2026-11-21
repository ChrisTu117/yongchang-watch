# 素材清单与授权

本作品的代码（`*.lua`、`tools/` 里的脚本）以 **AGPL-3.0** 授权，全文见 `LICENSE`。
团队原创的非代码素材（音效、音乐）以 **CC BY 4.0** 授权，全文见 `LICENSE-ASSETS`，许可证链接：https://creativecommons.org/licenses/by/4.0/ 。署名方式：“《永昌守望》制作组，2026 开源游戏开发大赛”。如修改，请注明修改内容。

画面全部由代码实时绘制（`src/scenes/*.lua` 里的几何图形），仓库里没有图片素材文件。绘制画面的代码属于代码，以 AGPL-3.0 授权；游戏运行时画出来的画面图像（`docs/screenshots/` 里的截图、封面等）作为美术成果，以 CC BY 4.0 授权。

赛事官网提供的汤和信俗图片、永昌堡资料 PDF **没有放进本仓库**，游戏只依据其中文字设定剧情和地图，出处见 `docs/文化资料与出处.md`。

| 来源 | 文件 | 内容 | 制作方式 | 授权 |
|---|---|---|---|---|
| 原创 | `assets/sfx/bow.wav` | 弓弦声 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/breach.wav` | 城门被攻破 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/build.wav` | 安排/升级守城单位（木鱼两声） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/click.wav` | 按钮 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/drum.wav` | 鼓 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/farm.wav` | 屯田 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/gate.wav` | 开关城门 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/gatehit.wav` | 砸门 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/gong.wav` | 锣 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/gun.wav` | 鸟铳声 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/hit.wav` | 命中 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/lantern.wav` | 放孔明灯 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/music_festival.ogg` | 节庆（锣鼓点＋拨弦） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/music_night.ogg` | 夜曲（拨弦、五声音阶、海浪） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/music_title.ogg` | 标题（慢速琶音） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/nomoney.wav` | 民力不足 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/repel.wav` | 击退 | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/saved.wav` | 迎入百姓（铃声） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 原创 | `assets/sfx/tok.wav` | 木鱼（提示） | `tools/gen_audio.py` 合成 | CC BY 4.0 |
| 第三方 | `assets/fonts/ycw-serif.ttf` | 游戏字体：Noto Serif CJK SC Bold 的子集（只保留游戏用到的字，轮廓转为 TrueType） | `tools/build_font.py` 从 Noto Serif CJK（© 2017-2024 Adobe，https://github.com/notofonts/noto-cjk ）生成，已修改 | SIL Open Font License 1.1（https://openfontlicense.org ） |
| 第三方 | `assets/fonts/OFL.txt` | 上面字体的许可证全文与版权声明 | 原样附带 | SIL Open Font License 1.1 |

Windows 包里另有 LÖVE 11.5 官方运行库（`love.dll`、`SDL2.dll` 等，zlib 许可，许可证随包附带为 `LOVE-license.txt`），不在本仓库中。
