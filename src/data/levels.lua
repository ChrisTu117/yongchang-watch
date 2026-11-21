-- SPDX-License-Identifier: AGPL-3.0-only
-- 三个夜晚。波次格式：
--   { t = 秒, kind = 敌人种类或 "refugee", path = 路线名, n = 数量, gap = 间隔秒, boat = 是否乘船 }
-- 史实依据见 docs/文化资料与出处.md。
local L = {}

L[1] = {
  id = 1,
  title = "第一夜 · 筑堡",
  era = "嘉靖三十八年（1559）",
  foe = "倭寇",
  duration = 110,
  minli = 6,
  tutorial = true,
  char = "天",
  waves = {
    { t = 6,  kind = "refugee", path = "ref_SW", n = 3, gap = 1.4 },
    { t = 12, kind = "raider",  path = "mid_E",  n = 3, gap = 1.6, boat = true },
    { t = 26, kind = "refugee", path = "ref_NW", n = 3, gap = 1.4 },
    { t = 34, kind = "raider",  path = "north_E", n = 4, gap = 1.4, boat = true },
    { t = 48, kind = "runner",  path = "south_E", n = 3, gap = 1.0, boat = true },
    { t = 58, kind = "refugee", path = "ref_W",  n = 4, gap = 1.2 },
    { t = 66, kind = "raider",  path = "mid_E",  n = 5, gap = 1.2, boat = true },
    { t = 80, kind = "raider",  path = "north_N", n = 3, gap = 1.5, boat = true },
    { t = 88, kind = "brute",   path = "mid_E",  n = 1, gap = 1.0, boat = true },
  },
}

L[2] = {
  id = 2,
  title = "第二夜 · 围堡",
  era = "崇祯五年（1632）",
  foe = "海盗刘香部",
  duration = 140,
  minli = 9,
  char = "下",
  waves = {
    { t = 4,   kind = "refugee", path = "ref_NE",  n = 4, gap = 1.2 },
    { t = 10,  kind = "raider",  path = "mid_E",   n = 4, gap = 1.3, boat = true },
    { t = 22,  kind = "runner",  path = "north_N", n = 4, gap = 0.9, boat = true },
    { t = 30,  kind = "refugee", path = "ref_SE",  n = 4, gap = 1.2 },
    { t = 38,  kind = "raider",  path = "south_S", n = 4, gap = 1.3, boat = true },
    { t = 50,  kind = "brute",   path = "mid_E",   n = 2, gap = 2.5, boat = true },
    { t = 58,  kind = "refugee", path = "ref_W",   n = 5, gap = 1.0 },
    { t = 66,  kind = "raider",  path = "north_E", n = 5, gap = 1.1, boat = true },
    { t = 76,  kind = "runner",  path = "south_E", n = 5, gap = 0.8, boat = true },
    { t = 90,  kind = "refugee", path = "ref_NE",  n = 4, gap = 1.1 },
    { t = 96,  kind = "raider",  path = "north_N", n = 5, gap = 1.1, boat = true },
    { t = 104, kind = "brute",   path = "south_S", n = 2, gap = 2.5, boat = true },
    { t = 114, kind = "raider",  path = "mid_E",   n = 6, gap = 1.0, boat = true },
  },
}

L[3] = {
  id = 3,
  title = "第三夜 · 避乱",
  era = "顺治五年（1648）",
  foe = "何兆龙所引山寇与海盗",
  duration = 170,
  minli = 12,
  char = "太",
  waves = {
    { t = 4,   kind = "refugee", path = "ref_W",   n = 5, gap = 1.0 },
    { t = 8,   kind = "raider",  path = "mid_E",   n = 4, gap = 1.2, boat = true },
    { t = 18,  kind = "refugee", path = "ref_SW",  n = 5, gap = 1.0 },
    { t = 24,  kind = "raider",  path = "hill_W",  n = 4, gap = 1.4 },
    { t = 34,  kind = "runner",  path = "north_N", n = 5, gap = 0.8, boat = true },
    { t = 42,  kind = "refugee", path = "ref_NE",  n = 5, gap = 1.0 },
    { t = 50,  kind = "brute",   path = "mid_E",   n = 2, gap = 2.0, boat = true },
    { t = 58,  kind = "raider",  path = "hill_S",  n = 5, gap = 1.2 },
    { t = 66,  kind = "refugee", path = "ref_NW",  n = 5, gap = 1.0 },
    { t = 74,  kind = "raider",  path = "south_S", n = 6, gap = 1.0, boat = true },
    { t = 84,  kind = "runner",  path = "hill_W",  n = 5, gap = 0.8 },
    { t = 92,  kind = "refugee", path = "ref_SE",  n = 5, gap = 1.0 },
    { t = 100, kind = "brute",   path = "north_E", n = 3, gap = 2.0, boat = true },
    { t = 110, kind = "raider",  path = "hill_N",  n = 6, gap = 1.0 },
    { t = 120, kind = "refugee", path = "ref_W",   n = 5, gap = 1.0 },
    { t = 128, kind = "raider",  path = "mid_E",   n = 7, gap = 0.9, boat = true },
    { t = 138, kind = "brute",   path = "hill_W",  n = 2, gap = 2.5 },
    { t = 146, kind = "runner",  path = "south_E", n = 6, gap = 0.7, boat = true },
  },
}

L.count = 3
return L
