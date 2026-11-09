-- Method C landmarks: hand-drawn pixel sprites and a procedural Stormwind, placed on the B terrain at the real
-- positions of their WMOs (prep_b.py "big" list) or dungeon entrances (ForeverDungeonJournal data).
-- Loaded by b_render.lua with mode=c; returns function(L, O).

-- Sprite key: . clear | o outline | K shadow | 1 2 3 stone dark..light | W w white, pale | r R red roof dark, light
-- b B slate roof dark, light | l L lava, glow | p blight | j g G jungle greens | d D e dirt | a A s ash | y gold | h f water
local S = {}

S.cathedral = {
  "........R........",
  ".......rRr.......",
  ".......r3r.......",
  "......o232o......",
  "......RRRRR......",
  ".....rRRRRRr.....",
  "..R.rrrrrrrrr.R..",
  ".rRr3W3W3W3W3rRr.",
  ".r3r33K333K33r3r.",
  ".r2r3W3W3W3W3r2r.",
  ".3233333K3333323.",
  ".3233333K3333323.",
  ".2222222K2222222.",
}

S.gilneas = {
  "........B........",
  ".......bBb.......",
  ".......b3b.......",
  "......o232o......",
  "......BBBBB......",
  ".....bBBBBBb.....",
  "..B.bbbbbbbbb.B..",
  ".bBb3W3W3W3W3bBb.",
  ".b3b33K333K33b3b.",
  ".b2b3W3W3W3W3b2b.",
  ".3233333K3333323.",
  ".2222222K2222222.",
}

S.ironforge = {
  "...........W...........",
  "..........WwW..........",
  ".........Ww33W.........",
  "........Ww3332.........",
  ".......Ww333322W.......",
  "......Ww33322222w......",
  ".....Ww3332222221W.....",
  "....Ww333oooooo2211....",
  "...Ww332o3333332o211...",
  "..Ww3322o3LLLL32o2211..",
  ".Ww33222o3LyyL32o22211.",
  "Ww332222o3LyyL32o222111",
  "w3322222o3LyyL32o222211",
  "33222o2o23LLLL322o2o211",
  "3222o3o2o3KKKK32o2o3o11",
  "2222o3o2o3KKKK32o2o3o11",
  "1111111111111111111111.",
}

S.lordaeron = {
  ".2.......3.......2.",
  "232.....323.....232",
  "232..2..323..2..232",
  "232.232.232.232.232",
  "2323232323232323232",
  "232..p.....p....232",
  "2322222222222222232",
  "2323K32322323K32232",
  "232KK3232323KK32232",
  "2322222p22p22222232",
  "1111111p11p11111111",
}

S.blackrock = {
  "............L............",
  "...........lLl...........",
  "..........aAlLa..........",
  ".........aAlLlAa.........",
  "........aAAAlLAAs........",
  ".......aAAsAlLAAAs.......",
  "......aAAAAAlLAAAAs......",
  ".....aAAAsAAAlAAsAAs.....",
  "....aAAAAAAAAlLAAAAAs....",
  "...aAAAsAAAAAAlLAAsAAs...",
  "..aAAAAAAAAAAAlLAAAAAAs..",
  ".aAAAsAAAAaaAAAlAAAAsAAs.",
  "aAAAAAAAAaKKaAAlLAAAAAAAs",
  "aaaaaaaaaaKKaaaalLaaaaaaa",
}

S.keep = {
  "b.....b.....b",
  "B....bBb....B",
  "3...b333b...3",
  "3.3.33K33.3.3",
  "3333333333333",
  "33K3K333K3K33",
  "3333333333333",
  "33333KKK33333",
  "2222KKKKK2222",
}

S.karazhan = {
  "....R....",
  "...rRr...",
  "..rrRrr..",
  "...323...",
  "...3K3...",
  "...323...",
  "..o323o..",
  "...3K3...",
  "...323...",
  "...323...",
  "..32223..",
  "..3K323..",
  "..32223..",
  ".3222223.",
  ".3222K23.",
  "322222223",
  "111111111",
}

S.zulgurub = {
  "......GGG......",
  ".....G333G.....",
  ".....3KKK3.....",
  "....3333333....",
  "...g2222222g...",
  "...333333333...",
  "..g222222222g..",
  "..33333K33333..",
  ".g2222KKK2222g.",
  ".3333KKKKK3333.",
  "j22222222222222",
}

S.stromgarde = {
  "2.2.....2.2",
  "222.....222",
  "232..2..232",
  "2322.2.2232",
  "23222222232",
  "232K2..2232",
  "2322...2232",
  "11111.11111",
}

S.shadowfang = {
  "...b.....b...",
  "..bBb...bBb..",
  "..b2b...b2b..",
  "..222.b.222..",
  "..2K2bBb2K2..",
  "..222b2b222..",
  ".22222222222.",
  ".2K2222222K2.",
  ".22222KK2222.",
  ".2222KKKK222.",
  "1111111111111",
}

S.stratholme = {
  "..p.......p..",
  ".p2p.....p2p.",
  ".222.....222.",
  ".2K2.p.p.2K2.",
  ".22222p22222.",
  ".2222p2p2222.",
  ".222KKKKK222.",
  ".222KKKKK222.",
  "1111KKKKK1111",
}

S.uldaman = {
  ".333333333.",
  "32222222223",
  "32K2K2K2K23",
  "32222222223",
  "322KKKKK223",
  "322KyyyK223",
  "322KyyyK223",
  "11111111111",
}

S.gnomeregan = {
  "...3.3.3...",
  "..3332333..",
  ".332222233.",
  "33221112233",
  ".3211y1123.",
  "33211y11233",
  ".3221112233",
  "..3322233..",
  "...3.3.3...",
}

S.deadmines = {
  "ddddddddddd",
  "dDDDDDDDDDd",
  "dD.......Dd",
  "dDKKKKKKKDd",
  "dDKKKKKKKDd",
  "dDKKyKKKKDd",
  "dDKKKKKKKDd",
}

S.temple = {
  ".....G.....",
  "....333....",
  "...3KKK3...",
  "...22222...",
  "..3333333..",
  "..2222222..",
  ".333333333.",
  ".22222KK22.",
  "hhhhhhhhhhh",
}

S.dalaran = {
  ".....B.....",
  "....BpB....",
  "...BpppB...",
  "..BpppppB..",
  "..3333333..",
  ".323232323.",
  ".3K33K33K3.",
  "33333333333",
}

S.gate = {
  ".ooooo.",
  "o33333o",
  "o3KKL3o",
  "o3KKK3o",
  "o3KKK3o",
  "ooooooo",
}

return function(L, O)
  local C, put, W, H = L.C, L.put, L.W, L.H
  local KEY = {
    o = C("outline"), K = C("shadow"), ["1"] = C("rock0"), ["2"] = C("rock1"), ["3"] = C("rock2"),
    W = C("snow2"), w = C("snow1"), r = C("roof0"), R = C("roof1"), b = C("deep"), B = C("mid"),
    l = C("lava0"), L = C("lava1"), p = C("blight"), j = C("jungle0"), g = C("jungle1"), G = C("jungle2"),
    d = C("dirt0"), D = C("dirt1"), e = C("dirt2"), a = C("ash0"), A = C("ash1"), s = C("ash2"),
    y = C("farm"), h = C("shallow"), f = C("foam"),
  }
  local OUT, SH = C("outline"), C("shadow")

  -- draw a sprite centred on (cx, cy) with a 1 px outline and a drop shadow down-right
  local function sprite(rows, cx, cy)
    local h, w = #rows, 0
    for _, r in ipairs(rows) do w = math.max(w, #r) end
    local x0, y0 = math.floor(cx - w / 2), math.floor(cy - h / 2)
    local function solid(i, j)
      local r = rows[j]
      if not r then return false end
      local ch = r:sub(i, i)
      return ch ~= "" and ch ~= "." and ch ~= " "
    end
    for j = 1, h do for i = 1, w do
      if solid(i, j) then put(x0 + i, y0 + j + 1, SH); put(x0 + i + 1, y0 + j + 1, SH) end
    end end
    for j = 0, h + 1 do for i = 0, w + 1 do
      if not solid(i, j) and (solid(i - 1, j) or solid(i + 1, j) or solid(i, j - 1) or solid(i, j + 1)) then
        put(x0 + i - 1, y0 + j - 1, OUT)
      end
    end end
    for j = 1, h do for i = 1, w do
      local ch = rows[j]:sub(i, i)
      if KEY[ch] then put(x0 + i - 1, y0 + j - 1, KEY[ch]) end
    end end
    return x0, y0, w, h
  end

  -- Stormwind: wall along the edge of the city's own area, irregular district blocks (mostly blue slate roofs),
  -- winding canals, a few plazas and parks, then the cathedral and keep sprites.
  local function stormwind(b)
    local bx0, by0, bx1, by1 = math.floor(b[1]), math.floor(b[2]), math.ceil(b[3]), math.ceil(b[4])
    local function inCity(x, y)
      return x >= bx0 and y >= by0 and x <= bx1 and y <= by1 and not L.isWater(x, y) and L.biomeOf(x, y) == 9
    end
    local mx0, my0, mx1, my1 = 1e9, 1e9, -1e9, -1e9
    for y = by0, by1 do for x = bx0, bx1 do
      if inCity(x, y) then mx0, my0 = math.min(mx0, x), math.min(my0, y); mx1, my1 = math.max(mx1, x), math.max(my1, y) end
    end end
    if mx0 > mx1 then return end
    local cx, cy = (mx0 + mx1) // 2, (my0 + my1) // 2
    -- street grid with irregular spacing (seeded by position, so the layout is stable)
    local function cuts(a0, a1, seed, lo, hi)
      local t, v = {}, a0
      while v < a1 do t[#t + 1] = v; v = v + lo + math.floor(L.hash(v, seed) * (hi - lo + 1)) end
      return t
    end
    local xs, ys = cuts(mx0, mx1, 17, 5, 9), cuts(my0, my1, 29, 4, 6)
    local function cell(v, list)
      local i = 1
      while list[i + 1] and list[i + 1] <= v do i = i + 1 end
      return i, v - list[i], (list[i + 1] or v + 1) - list[i]
    end
    local W2 = math.max(1, mx1 - mx0)
    local function canalAt(x, y)
      -- two meandering north-south canals and one east-west
      for k, f in ipairs({ 0.36, 0.64 }) do
        local c = mx0 + W2 * f + math.sin((y - my0) / 13 + k) * 3
        if x >= c and x < c + 3 then return x < c + 1 and 1 or 2 end
      end
      local r = my0 + (my1 - my0) * 0.58 + math.sin((x - mx0) / 17) * 3
      if y >= r and y < r + 3 then return y < r + 1 and 1 or 2 end
      return nil
    end
    local roofD, roofL, redD, redL = C("deep"), C("mid"), C("roof0"), C("roof1")
    local cob, cob2 = C("rock2"), C("rock1")
    for y = my0, my1 do for x = mx0, mx1 do
      if inCity(x, y) then
        local edge = not (inCity(x - 1, y) and inCity(x + 1, y) and inCity(x, y - 1) and inCity(x, y + 1))
        local edge2 = not (inCity(x - 2, y) and inCity(x + 2, y) and inCity(x, y - 2) and inCity(x, y + 2))
        local cn = canalAt(x, y)
        if edge then put(x, y, OUT)
        elseif edge2 then put(x, y, (x + y) % 2 == 0 and C("rock2") or C("snow1"))
        elseif cn then put(x, y, cn == 1 and C("shallow") or C("ocean"))
        else
          local ix, ox, wx = cell(x, xs)
          local iy, oy, hy = cell(y, ys)
          local r = L.hash(ix * 7 + 3, iy * 13 + 5)
          if ox == 0 or oy == 0 then
            put(x, y, (L.hash(x, y) < 0.12) and cob2 or cob)          -- street
          elseif r < 0.07 then
            put(x, y, ((x + y) % 2 == 0) and C("lush1") or C("lush2"))  -- park
            if L.hash(x, y + 7) < 0.25 then put(x, y, C("dark1")) end
          elseif r < 0.12 then
            put(x, y, ((x // 2 + y // 2) % 2 == 0) and cob or C("sand2")) -- plaza
          else
            local red = r > 0.93
            local c
            if oy == 1 then c = red and redL or roofL
            elseif oy == hy - 1 or ox == wx - 1 then c = SH
            else c = red and redD or roofD end
            -- split long blocks into houses with a dark gable every 3-4 px
            if c ~= SH and ox > 1 and (ox + iy) % 4 == 0 and oy > 1 then c = SH end
            put(x, y, c)
          end
        end
      end
    end end
    -- towers on the wall
    local n = 0
    for y = my0, my1, 2 do for x = mx0, mx1, 2 do
      if inCity(x, y) and not (inCity(x - 3, y) and inCity(x + 3, y) and inCity(x, y - 3) and inCity(x, y + 3)) then
        n = n + 1
        if n % 6 == 0 then
          for dy = -1, 1 do for dx = -1, 1 do put(x + dx, y + dy, (dx == 0 and dy == 0) and C("mid") or C("rock2")) end end
          put(x + 2, y, OUT); put(x - 2, y, OUT); put(x, y - 2, OUT); put(x, y + 2, OUT)
        end
      end
    end end
    sprite(S.cathedral, cx - 6, cy - 6)
    sprite(S.keep, cx + (mx1 - mx0) // 5, my0 + (my1 - my0) // 5)
  end

  -- Blackrock Mountain: a shaded volcanic cone the size of its WMO, lava runs and a glowing crater.
  local function blackrock(b)
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    local r = math.min(b[3] - b[1], b[4] - b[2]) / 2
    local a0, a1, a2, l0, l1 = C("ash0"), C("ash1"), C("ash2"), C("lava0"), C("lava1")
    for y = math.floor(cy - r) - 1, math.ceil(cy + r) + 1 do
      for x = math.floor(cx - r) - 1, math.ceil(cx + r) + 1 do
        local dx, dy = (x - cx) / r, (y - cy) / r
        local d = math.sqrt(dx * dx + dy * dy) + (L.vnoise(x, y, 5) - 0.5) * 0.18
        if d <= 1 then
          -- light from the north-west on a cone: brightness from the direction of the slope
          local lit = (d > 0.001) and (-(dx + dy) / (d * 1.414)) or 0
          local ang = math.atan(dy, dx)
          local ridge = math.sin(ang * 16 + L.vnoise(x, y, 6) * 3) * 0.45 * d
          local t = 1 + lit * 1.5 + ridge + (L.bayer(x, y) - 0.5) * 0.7
          local c = t < 0.45 and a0 or (t < 1.05 and a1 or (t < 1.7 and a2 or C("rock1")))
          local run = math.abs(math.sin(ang * 3 + L.vnoise(x, y, 7) * 2.2 + d * 2.5))
          if d < 0.2 then c = (d < 0.12) and l1 or l0
          elseif d < 0.27 then c = OUT
          elseif run < 0.07 + 0.05 * (1 - d) then c = (run < 0.035) and l1 or l0 end
          if d > 0.94 then c = OUT end
          put(x, y, c)
        end
      end
    end
  end

  local placed = {}
  local function near(x, y, r)
    for _, p in ipairs(placed) do if (p[1] - x) ^ 2 + (p[2] - y) ^ 2 < r * r then return true end end
    return false
  end
  local function at(name, x, y)
    if near(x, y, 18) then return end
    sprite(S[name], x, y)
    placed[#placed + 1] = { x, y }
  end
  local BIG = {
    { "^21138%.wmo$", "stormwind" }, { "^20884%.wmo$", "ironforge" }, { "^20736%.wmo$", "lordaeron" },
    { "^21070%.wmo$", "blackrock" }, { "kharazan", "karazhan" }, { "scarlet_monestary", "cathedral" },
    { "zulgurubcity", "zulgurub" }, { "stromguard", "stromgarde" }, { "ld_shadowfang", "shadowfang" },
    { "kz_uldaman", "uldaman" }, { "kz_gnomeragon", "gnomeregan" }, { "az_deadmines", "deadmines" },
    { "^21106%.wmo$", "stratholme" }, { "gilneas_cathedral%.wmo", "gilneas" },
  }
  for _, b in ipairs(O.big) do
    for _, m in ipairs(BIG) do
      if b[5]:match(m[1]) then
        local x, y = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
        if m[2] == "stormwind" then
          stormwind(b); placed[#placed + 1] = { x, y }
        elseif m[2] == "blackrock" then
          blackrock(b); placed[#placed + 1] = { x, y }
        else
          at(m[2], x, y)
        end
      end
    end
  end
  local POI = { ["Sunken Temple"] = "temple", ["City of Dalaran"] = "dalaran" }
  for _, p in ipairs(O.pois) do
    if POI[p.name] then at(POI[p.name], p.x, p.y)
    elseif p.kind == "dungeon" and not near(p.x, p.y, 24) then at("gate", p.x, p.y - 2) end
  end
end
