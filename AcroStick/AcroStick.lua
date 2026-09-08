--[[
© 2026 YGTECH 出品。本作品著作权归作者 helloyuanyuan 所有。
作者微信 / 抖音同号（欢迎关注，合作请备注）。
未经书面许可，任何单位或个人不得对作品内容进行修改、摘编、转载或分发，不得用于商业用途。
如需合作或授权，请联系作者获取正式许可。侵权必究。

© 2026 YGTECH. This work is the property of the author, helloyuanyuan.
The author's WeChat and Douyin accounts are the same (followers welcome; please note "collaboration" in your message).
No part of this work may be modified, excerpted, reposted, or distributed for any purpose without prior written permission. Commercial use is strictly prohibited.
For collaboration or licensing inquiries, please contact the author directly. All rights reserved. Unauthorized use will be pursued legally.
]]--

local SPLASH_DURATION_CS = 200
local showingSplash = true
local splashStartCs = 0

local function computeLayout()
  local w, h = LCD_W, LCD_H

  local margin = math.floor(w * 10 / 480 + 0.5)
  if margin < 4 then margin = 4 end

  local titleFont
  if h >= 300 then
    titleFont = DBLSIZE
  else
    titleFont = 0
  end

  local topPad = math.floor(h * 0.03 + 0.5)
  local titleH = math.floor(h * (h >= 400 and 0.13 or (h >= 300 and 0.15 or 0.13)) + 0.5)
  local statH = math.floor(h * 0.12 + 0.5)
  local bottomPad = math.floor(h * 0.04 + 0.5)

  local areaTop = topPad + titleH + statH
  local areaH = h - areaTop - bottomPad

  local gap = math.floor(w * 0.05 + 0.5)
  local box = math.min(math.floor((w - margin * 2 - gap) / 2), areaH)
  if box < 60 then box = 60 end

  local pairW = box * 2 + gap
  local leftX = math.floor((w - pairW) / 2)

  return {
    w = w, h = h,
    margin = margin,
    titleFont = titleFont, titleY = topPad,
    statY = topPad + titleH + math.floor(statH * 0.20),
    box = box,
    boxY = areaTop + math.floor((areaH - box) / 2),
    leftX = leftX,
    rightX = leftX + box + gap,
  }
end

local L = computeLayout()

local COL_BG        = lcd.RGB(12, 14, 20)
local COL_PANEL     = lcd.RGB(20, 24, 34)
local COL_AXIS      = lcd.RGB(60, 72, 96)
local COL_FRAME_REC = lcd.RGB(0, 210, 255)
local COL_FRAME_IDLE= lcd.RGB(70, 84, 110)
local COL_WHITE     = lcd.RGB(255, 255, 255)
local COL_DOT       = lcd.RGB(255, 255, 255)
local COL_DIM       = lcd.RGB(190, 200, 218)
local COL_YGTECH    = lcd.RGB(255, 185, 30)

local SW_CANDIDATES = {
  "sa", "sb", "sc", "sd", "se", "sf", "sg", "sh", "si", "sj",
  "s1", "s2", "s3", "s4", "s5", "s6",
}
local switchSource = "sa"
local switchIndex = 1
local switchSelected = false

local selectBaseline = nil
local MOVE_THRESHOLD = 200

local ARM_ON  = 60
local ARM_OFF = 30
local STAY_TICKS = 35
local armInitial = 0
local seenAway = false
local awaySince = 0
local maintained = false
local recording = false
local hasResult = false

local lastFull = 0
local FULL_INTERVAL = 8
local dotPrev = { nil, nil }

local GRID = 48
local SPLAT_R = 2.0
local heatL, heatR = {}, {}
local touchedL, touchedR = {}, {}
local totalW = 0
local nonZero = 0
local REF_K = 4.0

local ftc = 0
local thrWasFull = false
local thrSum = 0
local thrN = 0

local function clearHeat()
  heatL, heatR = {}, {}
  touchedL, touchedR = {}, {}
  totalW = 0
  nonZero = 0
  ftc = 0
  thrWasFull = false
  thrSum = 0
  thrN = 0
end

clearHeat()

local HEAT_STOPS = {
  {0.00,   8,  24,  70},
  {0.16,   0, 110, 210},
  {0.36,   0, 195, 175},
  {0.55,  90, 215,  45},
  {0.72, 240, 215,   0},
  {0.86, 250, 130,  10},
  {1.00, 250,  40,  25},
}

local function heatColorRaw(t)
  if t > 1 then t = 1 end
  for i = 1, #HEAT_STOPS - 1 do
    local a, b = HEAT_STOPS[i], HEAT_STOPS[i + 1]
    if t <= b[1] then
      local span = b[1] - a[1]
      local k = (span > 0) and (t - a[1]) / span or 0
      return lcd.RGB(
        math.floor(a[2] + (b[2] - a[2]) * k),
        math.floor(a[3] + (b[3] - a[3]) * k),
        math.floor(a[4] + (b[4] - a[4]) * k))
    end
  end
  local z = HEAT_STOPS[#HEAT_STOPS]
  return lcd.RGB(z[2], z[3], z[4])
end

local HEAT_LUT_N = 64
local HEAT_LUT = {}
for k = 1, HEAT_LUT_N do
  HEAT_LUT[k] = heatColorRaw((k / HEAT_LUT_N) ^ 0.85)
end

local function axisWeights(c)
  local lo = math.floor(c - SPLAT_R + 0.5)
  local hi = math.ceil(c + SPLAT_R - 0.5)
  if lo < 1 then lo = 1 end
  if hi > GRID then hi = GRID end
  local idx, w, sum, n = {}, {}, 0, 0
  for i = lo, hi do
    local d = ((i - 0.5) - c) / SPLAT_R
    if d < 0 then d = -d end
    if d < 1 then
      local ww = 1 - d * d
      n = n + 1
      idx[n] = i
      w[n] = ww
      sum = sum + ww
    end
  end
  return idx, w, sum, n
end

local function addWeight(heat, touched, idx, wgt)
  local cur = heat[idx]
  if cur == nil then
    heat[idx] = wgt
    touched[#touched + 1] = idx
    nonZero = nonZero + 1
  else
    heat[idx] = cur + wgt
  end
end

local function feed(heat, touched, hv, vv)
  local cx = (hv + 1024) / 2048 * GRID
  local cy = (1024 - vv) / 2048 * GRID
  local xi, xw, xs, xn = axisWeights(cx)
  local yi, yw, ys, yn = axisWeights(cy)
  if xs <= 0 or ys <= 0 then return end
  local norm = 1 / (xs * ys)
  for a = 1, yn do
    local rowBase = (yi[a] - 1) * GRID
    local wy = yw[a] * norm
    for b = 1, xn do
      addWeight(heat, touched, rowBase + xi[b], xw[b] * wy)
    end
  end
end

local function recordSample()
  local yaw   = getValue("rud") or 0
  local thr   = getValue("thr") or 0
  local roll  = getValue("ail") or 0
  local pitch = getValue("ele") or 0

  feed(heatL, touchedL, yaw, thr)
  feed(heatR, touchedR, roll, pitch)
  totalW = totalW + 1

  local thrPct = math.floor((thr + 1024) / 2048 * 100 + 0.5)
  if thrPct < 0 then thrPct = 0 elseif thrPct > 100 then thrPct = 100 end
  thrSum = thrSum + thrPct
  thrN = thrN + 1

  if (not thrWasFull) and thrPct >= 100 then
    ftc = ftc + 1
    thrWasFull = true
  elseif thrWasFull and thrPct < 98 then
    thrWasFull = false
  end
end

local function drawTitle()
  local font = L.titleFont
  local parts = {
    { text = "AcroStick", color = lcd.RGB(233, 60, 76) },
    { text = " / ",       color = lcd.RGB(255, 255, 255) },
    { text = "YGTECH",    color = COL_YGTECH },
  }
  local totalTextW = 0
  for _, p in ipairs(parts) do
    p.w = lcd.sizeText(p.text, font)
    totalTextW = totalTextW + p.w
  end
  local x = L.w / 2 - totalTextW / 2
  for _, p in ipairs(parts) do
    lcd.drawText(x, L.titleY, p.text, p.color + font)
    x = x + p.w
  end
end

local function drawArcCorner(cx, cy, r, a0, a1, th, col)
  local steps = 10
  for s = 0, steps do
    local a = a0 + (a1 - a0) * s / steps
    local px = cx + r * math.cos(a)
    local py = cy + r * math.sin(a)
    lcd.drawFilledRectangle(px - th / 2, py - th / 2, th, th, col)
  end
end

local function drawRoundRectBorder(x, y, w, h, r, th, col)
  lcd.drawFilledRectangle(x + r, y, w - 2 * r, th, col)
  lcd.drawFilledRectangle(x + r, y + h - th, w - 2 * r, th, col)
  lcd.drawFilledRectangle(x, y + r, th, h - 2 * r, col)
  lcd.drawFilledRectangle(x + w - th, y + r, th, h - 2 * r, col)
  local rr = r - th / 2
  drawArcCorner(x + r,     y + r,     rr, math.pi,        math.pi * 1.5, th, col)
  drawArcCorner(x + w - r, y + r,     rr, math.pi * 1.5,  math.pi * 2.0, th, col)
  drawArcCorner(x + w - r, y + h - r, rr, 0,              math.pi * 0.5, th, col)
  drawArcCorner(x + r,     y + h - r, rr, math.pi * 0.5,  math.pi,       th, col)
end

local function heatRef()
  local ref = 1
  if nonZero > 0 and totalW > 0 then
    ref = (totalW / nonZero) * REF_K
    if ref < 1 then ref = 1 end
  end
  return ref
end

local function drawHeatBox(ox, oy, heat, touched, isRec)
  local box = L.box
  local cell = box / GRID

  lcd.drawFilledRectangle(ox, oy, box, box, COL_PANEL)

  local invRef = HEAT_LUT_N / heatRef()
  for i = 1, #touched do
    local idx = touched[i]
    local c = heat[idx]
    if c ~= nil and c > 0 then
      local gy = math.floor((idx - 1) / GRID)
      local gx = idx - gy * GRID - 1
      local k = math.floor(c * invRef) + 1
      if k > HEAT_LUT_N then k = HEAT_LUT_N end
      lcd.drawFilledRectangle(ox + gx * cell, oy + gy * cell, cell + 1, cell + 1, HEAT_LUT[k])
    end
  end

  lcd.drawFilledRectangle(ox, oy + box / 2, box, 1, COL_AXIS)
  lcd.drawFilledRectangle(ox + box / 2, oy, 1, box, COL_AXIS)

  if isRec then
    lcd.drawRectangle(ox - 1, oy - 1, box + 2, box + 2, COL_FRAME_REC, 2)
    lcd.drawRectangle(ox - 4, oy - 4, box + 8, box + 8, COL_FRAME_REC, 3)
  else
    lcd.drawRectangle(ox - 1, oy - 1, box + 2, box + 2, COL_FRAME_IDLE, 2)
  end
end

local function repaintPatch(ox, oy, heat, touched, rx, ry, rw)
  local box = L.box
  local x1 = math.max(rx, ox)
  local y1 = math.max(ry, oy)
  local x2 = math.min(rx + rw, ox + box)
  local y2 = math.min(ry + rw, oy + box)
  if x2 <= x1 or y2 <= y1 then return end

  lcd.drawFilledRectangle(x1, y1, x2 - x1, y2 - y1, COL_PANEL)

  local cell = box / GRID
  local invRef = HEAT_LUT_N / heatRef()
  for i = 1, #touched do
    local idx = touched[i]
    local c = heat[idx]
    if c ~= nil and c > 0 then
      local gy = math.floor((idx - 1) / GRID)
      local gx = idx - gy * GRID - 1
      local cxp = ox + gx * cell
      local cyp = oy + gy * cell
      if cxp < x2 and cxp + cell > x1 and cyp < y2 and cyp + cell > y1 then
        local k = math.floor(c * invRef) + 1
        if k > HEAT_LUT_N then k = HEAT_LUT_N end
        lcd.drawFilledRectangle(cxp, cyp, cell + 1, cell + 1, HEAT_LUT[k])
      end
    end
  end

  local axisY = oy + box / 2
  if axisY >= y1 and axisY < y2 then
    lcd.drawFilledRectangle(x1, axisY, x2 - x1, 1, COL_AXIS)
  end
  local axisX = ox + box / 2
  if axisX >= x1 and axisX < x2 then
    lcd.drawFilledRectangle(axisX, y1, 1, y2 - y1, COL_AXIS)
  end
end

local function drawLiveDot(bi, ox, oy, heat, touched, liveH, liveV)
  local box = L.box
  local pv = dotPrev[bi]
  if pv then
    repaintPatch(ox, oy, heat, touched, pv.x - 7, pv.y - 7, 15)
  end
  local px = ox + (liveH + 1024) / 2048 * box
  local py = oy + (1024 - liveV) / 2048 * box
  lcd.drawRectangle(px - 4, py - 4, 9, 9, lcd.RGB(0, 0, 0))
  lcd.drawFilledRectangle(px - 3, py - 3, 6, 6, COL_DOT)
  dotPrev[bi] = { x = px, y = py }
end

local function drawFull()
  lcd.clear(COL_BG)
  drawTitle()

  local avgTxt = (thrN > 0)
    and (math.floor(thrSum / thrN + 0.5) .. "%")
    or "--%"

  lcd.drawText(L.leftX + L.box / 2, L.statY,
    string.format("FTC: %d times", ftc), CENTER + MIDSIZE + COL_DIM)
  lcd.drawText(L.rightX + L.box / 2, L.statY,
    "Avg Thr: " .. avgTxt, CENTER + MIDSIZE + COL_DIM)

  drawHeatBox(L.leftX, L.boxY, heatL, touchedL, recording)
  drawHeatBox(L.rightX, L.boxY, heatR, touchedR, recording)

  dotPrev[1] = nil
  dotPrev[2] = nil
end

local function updateSwitchSelect()
  if selectBaseline == nil then
    selectBaseline = {}
    for _, name in ipairs(SW_CANDIDATES) do
      selectBaseline[name] = getValue(name) or 0
    end
    switchSource = "sa"
    switchIndex = 1
  end

  local bestName, bestDev = nil, MOVE_THRESHOLD
  for _, name in ipairs(SW_CANDIDATES) do
    local v = getValue(name) or 0
    local dev = math.abs(v - (selectBaseline[name] or 0))
    if dev > bestDev then
      bestDev = dev
      bestName = name
    end
  end
  if bestName ~= nil then
    switchSource = bestName
    for i, name in ipairs(SW_CANDIDATES) do
      if name == bestName then switchIndex = i end
    end
    for _, name in ipairs(SW_CANDIDATES) do
      selectBaseline[name] = getValue(name) or 0
    end
  end
end

local function selectManual(delta)
  switchIndex = switchIndex + delta
  if switchIndex < 1 then switchIndex = #SW_CANDIDATES end
  if switchIndex > #SW_CANDIDATES then switchIndex = 1 end
  switchSource = SW_CANDIDATES[switchIndex]
  if selectBaseline then
    for _, name in ipairs(SW_CANDIDATES) do
      selectBaseline[name] = getValue(name) or 0
    end
  end
end

local function drawSwitchSelect(event)
  lcd.clear(COL_BG)
  drawTitle()

  updateSwitchSelect()

  local bw = math.max(150, math.floor(L.w * 0.36))
  local bh = math.max(84, math.floor(L.h * 0.26))
  local bx = math.floor(L.w / 2 - bw / 2)
  local by = math.floor(L.h / 2 - bh / 2)
  local r = math.max(10, math.floor(bh * 0.18))

  drawRoundRectBorder(bx, by, bw, bh, r, 4, COL_YGTECH)
  local nf = L.titleFont
  local nh = (nf == DBLSIZE) and 24 or 12
  local name = string.upper(switchSource)
  lcd.drawText(L.w / 2, by + math.floor((bh - nh) / 2), name,
    CENTER + nf + COL_WHITE)

  lcd.drawText(L.w / 2, by + bh + math.floor(L.h * 0.07), "Select ARM button",
    CENTER + MIDSIZE + COL_DIM)

  if event == EVT_VIRTUAL_EXIT_LONG then
    return 2
  elseif event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_NEXT
      or event == EVT_VIRTUAL_NEXT_REPT or event == EVT_ROT_RIGHT then
    selectManual(1)
  elseif event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_PREV
      or event == EVT_VIRTUAL_PREV_REPT or event == EVT_ROT_LEFT then
    selectManual(-1)
  elseif event == EVT_VIRTUAL_ENTER then
    switchSelected = true
    recording = false
    hasResult = false
    armInitial = getValue(switchSource) or 0
    seenAway = false
    maintained = false
    lastFull = 0
    clearHeat()
  end
  return 0
end

local COL_BLACK = lcd.RGB(0, 0, 0)
local COL_LOGO_WHITE = lcd.RGB(255, 255, 255)
local COL_CLUB_RED = lcd.RGB(255, 0, 0)

local CLUB_LOGO_ASPECT = 1.0199
local CLUB_LOGO_SHAPES = {
  { color = COL_BLACK,
    {0.9818,0.2146,0.9592,0.1967,0.9307,0.1885,0.5469,0.1882,0.5469,0.1161,0.7275,0.1159,0.7454,0.1115,0.7638,0.0991,0.7791,0.0720,0.7791,0.0441,0.7638,0.0170,0.7367,0.0017,0.2772,0.0000,0.2589,0.0030,0.2395,0.0140,0.2237,0.0355,0.2192,0.0581,0.2237,0.0807,0.2395,0.1021,0.2546,0.1115,0.2725,0.1159,0.4531,0.1161,0.4531,0.1882,0.0693,0.1885,0.0357,0.1995,0.0182,0.2146,0.0084,0.2290,0.0000,0.2637,0.0000,0.9445,0.0038,0.9683,0.0182,0.9936,0.0461,1.0140,0.0755,1.0199,0.9245,1.0199,0.9484,1.0161,0.9737,1.0018,0.9941,0.9738,1.0000,0.9445,1.0000,0.2637,0.9962,0.2398},
  },
  { color = COL_LOGO_WHITE,
    {0.3552,0.5642,0.2934,0.5024,0.2316,0.5642,0.1767,0.5093,0.2385,0.4475,0.1767,0.3857,0.2316,0.3308,0.2934,0.3926,0.3552,0.3308,0.4101,0.3857,0.3483,0.4475,0.4101,0.5093},
    {0.2790,0.2732,0.2514,0.2777,0.2130,0.2921,0.1901,0.3064,0.1606,0.3337,0.1380,0.3671,0.1274,0.3922,0.1191,0.4331,0.1191,0.4618,0.1236,0.4895,0.1380,0.5278,0.1523,0.5508,0.1796,0.5802,0.2130,0.6028,0.2381,0.6134,0.2790,0.6218,0.3077,0.6218,0.3354,0.6173,0.3737,0.6028,0.3966,0.5886,0.4261,0.5613,0.4487,0.5278,0.4593,0.5027,0.4677,0.4618,0.4677,0.4331,0.4632,0.4055,0.4487,0.3671,0.4345,0.3442,0.4072,0.3147,0.3737,0.2921,0.3486,0.2815,0.3077,0.2732},
  },
  { color = COL_CLUB_RED,
    {0.8942,0.4618,0.8897,0.4895,0.8753,0.5278,0.8610,0.5508,0.8337,0.5802,0.8003,0.6028,0.7752,0.6134,0.7343,0.6218,0.7056,0.6218,0.6779,0.6173,0.6396,0.6028,0.6166,0.5886,0.5871,0.5613,0.5646,0.5278,0.5540,0.5027,0.5456,0.4618,0.5456,0.4331,0.5501,0.4055,0.5646,0.3671,0.5788,0.3442,0.6061,0.3147,0.6396,0.2921,0.6646,0.2815,0.7056,0.2732,0.7343,0.2732,0.7619,0.2777,0.8003,0.2921,0.8232,0.3064,0.8527,0.3337,0.8753,0.3671,0.8859,0.3922,0.8942,0.4331},
  },
  { color = COL_LOGO_WHITE,
    {0.6581,0.5642,0.6032,0.5093,0.7817,0.3308,0.8366,0.3857},
  },
  { color = COL_LOGO_WHITE,
    {0.6032,0.3857,0.6581,0.3308,0.8366,0.5093,0.7817,0.5642},
  },
  { color = COL_LOGO_WHITE,
    {0.1185,0.9372,0.1185,0.6757,0.8815,0.6757,0.8815,0.9372},
  },
  { color = COL_CLUB_RED,
    {0.8496,0.8058,0.8429,0.8237,0.8270,0.8324,0.5787,0.8332,0.5300,0.9026,0.5209,0.9105,0.5081,0.9141,0.4953,0.9105,0.4862,0.9025,0.4395,0.8345,0.3568,0.8319,0.3454,0.8227,0.3136,0.7767,0.2792,0.8249,0.2618,0.8341,0.1716,0.8338,0.1570,0.8252,0.1504,0.8075,0.1554,0.7918,0.1684,0.7818,0.2447,0.7786,0.2915,0.7106,0.3007,0.7024,0.3134,0.6988,0.3260,0.7026,0.3352,0.7109,0.3822,0.7791,0.4647,0.7811,0.4755,0.7897,0.5077,0.8365,0.5422,0.7878,0.5608,0.7787,0.8256,0.7788,0.8423,0.7873},
  },
}

local function drawFilledPolygonMulti(contours, color)
  local minY, maxY = nil, nil
  for _, c in ipairs(contours) do
    for i = 1, #c / 2 do
      local y = c[2 * i]
      if minY == nil or y < minY then minY = y end
      if maxY == nil or y > maxY then maxY = y end
    end
  end
  for y = math.floor(minY), math.ceil(maxY) do
    local xs = {}
    for _, c in ipairs(contours) do
      local n = #c / 2
      for i = 1, n do
        local j = (i % n) + 1
        local x1, y1 = c[2 * i - 1], c[2 * i]
        local x2, y2 = c[2 * j - 1], c[2 * j]
        if (y1 <= y and y2 > y) or (y2 <= y and y1 > y) then
          local t = (y - y1) / (y2 - y1)
          table.insert(xs, x1 + t * (x2 - x1))
        end
      end
    end
    table.sort(xs)
    for k = 1, #xs - 1, 2 do
      local xa, xb = xs[k], xs[k + 1]
      if xb > xa then
        lcd.drawFilledRectangle(xa, y, xb - xa + 1, 1, color)
      end
    end
  end
end

local function drawClubLogo(leftX, topY, width)
  for _, shape in ipairs(CLUB_LOGO_SHAPES) do
    local contours = {}
    for _, poly in ipairs(shape) do
      local n = #poly / 2
      local pts = {}
      for i = 1, n do
        pts[2 * i - 1] = leftX + poly[2 * i - 1] * width
        pts[2 * i]     = topY + poly[2 * i] * width
      end
      table.insert(contours, pts)
    end
    drawFilledPolygonMulti(contours, shape.color)
  end
end

local function drawSplash()
  lcd.clear(lcd.RGB(245, 225, 180))

  local availW = L.w * 0.94
  local availH = L.h * 0.94
  local clubW = math.min(availW, availH / CLUB_LOGO_ASPECT)
  local clubH = clubW * CLUB_LOGO_ASPECT
  local leftX = (L.w - clubW) / 2
  local topY = (L.h - clubH) / 2

  drawClubLogo(leftX, topY, clubW)
end

local function init()
  showingSplash = true
  splashStartCs = getTime()
  switchSelected = false
  selectBaseline = nil
  switchSource = "sa"
  switchIndex = 1
  recording = false
  hasResult = false
  seenAway = false
  maintained = false
  lastFull = 0
  dotPrev[1] = nil
  dotPrev[2] = nil
  clearHeat()
end

local function run(event, touchState)

  if showingSplash then
    drawSplash()
    if getTime() - splashStartCs >= SPLASH_DURATION_CS then
      showingSplash = false
    elseif event == EVT_VIRTUAL_EXIT_LONG then
      return 2
    end
    return 0
  end

  if not switchSelected then
    return drawSwitchSelect(event)
  end

  local v = getValue(switchSource) or 0
  local dev = math.abs(v - armInitial)

  local function startRec()
    clearHeat()
    recording = true
    hasResult = false
    lastFull = 0
  end
  local function stopRec()
    recordSample()
    recording = false
    hasResult = true
    lastFull = 0
  end

  if not seenAway and dev > ARM_ON then
    seenAway = true
    awaySince = getTime()
    maintained = false
  end

  if seenAway and not maintained and dev > ARM_OFF
     and (getTime() - awaySince) > STAY_TICKS then
    -- 停留够久 = 二段/三段等保持型开关: 电平语义, 离开初始位即记录
    maintained = true
    if not recording then startRec() end
  end

  if seenAway and dev < ARM_OFF then
    if maintained then
      if recording then stopRec() end          -- 回到初始位 = 停止
    else
      -- 回弹 / 按键: 一次完整的 离开->回位 = 翻转一次
      if recording then stopRec() else startRec() end
    end
    seenAway = false
    maintained = false
  end

  if recording then
    recordSample()
  end

  local now = getTime()
  if lastFull == 0 or (now - lastFull) >= FULL_INTERVAL then
    lastFull = now
    drawFull()
  end

  local thr   = getValue("thr") or 0
  local yaw   = getValue("rud") or 0
  local roll  = getValue("ail") or 0
  local pitch = getValue("ele") or 0
  drawLiveDot(1, L.leftX, L.boxY, heatL, touchedL, yaw, thr)
  drawLiveDot(2, L.rightX, L.boxY, heatR, touchedR, roll, pitch)

  if event == EVT_VIRTUAL_EXIT then
    switchSelected = false
    selectBaseline = nil
    recording = false
    return 0
  elseif event == EVT_VIRTUAL_EXIT_LONG then
    return 2
  end
  return 0
end

return { init = init, run = run }
