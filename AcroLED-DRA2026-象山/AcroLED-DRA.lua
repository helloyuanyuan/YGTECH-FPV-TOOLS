--[[
© 2026 YGTECH 出品。本作品著作权归作者 helloyuanyuan 所有。
作者微信 / 抖音同号（欢迎关注，合作请备注）。
未经书面许可，任何单位或个人不得对作品内容进行修改、摘编、转载或分发，不得用于商业用途。
如需合作或授权，请联系作者获取正式许可。侵权必究。

© 2026 YGTECH. This work is the property of the author, helloyuanyuan.
The author’s WeChat and Douyin accounts are the same (followers welcome; please note “collaboration” in your message).
No part of this work may be modified, excerpted, reposted, or distributed for any purpose without prior written permission. Commercial use is strictly prohibited.
For collaboration or licensing inquiries, please contact the author directly. All rights reserved. Unauthorized use will be pursued legally.
]]--

local FM_INDEX = 0
local GV_INDEX = 0

local RC_RANGE_MIN_US = 1000
local RC_RANGE_MAX_US = 2000

local function gvValueForStep(index, count)
  local stepWidthUs = (RC_RANGE_MAX_US - RC_RANGE_MIN_US) / count
  local centerUs = RC_RANGE_MIN_US + (index + 0.5) * stepWidthUs
  local v = (centerUs - 1500) * 1024 / (RC_RANGE_MAX_US - 1500)
  if v > 1024 then v = 1024 end
  if v < -1024 then v = -1024 end
  return math.floor(v + 0.5)
end

local function stepFromGvValue(v, count)
  local centerUs = 1500 + v * (RC_RANGE_MAX_US - 1500) / 1024
  local index = math.floor((centerUs - RC_RANGE_MIN_US) * count / (RC_RANGE_MAX_US - RC_RANGE_MIN_US))
  if index < 0 then index = 0 end
  if index > count - 1 then index = count - 1 end
  return index
end

local COL_WHITE_TEXT = lcd.RGB(255, 255, 255)
local COL_DARK_TEXT  = lcd.RGB(20, 30, 30)

local pointOptions = {
  { label = "R1", color = lcd.RGB(250,   0,   0), textColor = COL_WHITE_TEXT },
  { label = "R2", color = lcd.RGB(230, 199,  20), textColor = COL_DARK_TEXT  },
  { label = "R3", color = lcd.RGB(230, 150,  20), textColor = COL_DARK_TEXT  },
  { label = "R6", color = lcd.RGB( 40, 110, 230), textColor = COL_WHITE_TEXT },
  { label = "F2", color = lcd.RGB( 20,  40, 160), textColor = COL_WHITE_TEXT },
  { label = "F4", color = lcd.RGB( 79,  40, 200), textColor = COL_WHITE_TEXT },
  { label = "R7", color = lcd.RGB( 19, 250,   0), textColor = COL_DARK_TEXT  },
  { label = "R8", color = lcd.RGB( 20, 180, 190), textColor = COL_WHITE_TEXT },
}

local staged = 0
local confirmed = 0

local sendEnabled = true

local SPLASH_DURATION_CS = 250
local showingSplash = true
local splashStartCs = 0

local function computeLayout()
  local w, h = LCD_W, LCD_H

  local margin = math.floor(w * 10 / 480 + 0.5)
  local gap = math.floor(w * 6 / 480 + 0.5)
  if margin < 4 then margin = 4 end
  if gap < 2 then gap = 2 end

  local titleFont
  if h >= 300 then
    titleFont = DBLSIZE
  else
    titleFont = 0
  end

  local topPad = math.floor(h * 0.03 + 0.5)
  local titleH = math.floor(h * (h >= 400 and 0.14 or (h >= 300 and 0.16 or 0.13)) + 0.5)
  local bottomPad = math.floor(h * 0.04 + 0.5)
  local rowGap = math.floor(h * 0.03 + 0.5)
  if rowGap < 3 then rowGap = 3 end

  local rowsTop = topPad + titleH
  local rowH = math.floor((h - rowsTop - bottomPad - 2 * rowGap) / 3)
  if rowH < 24 then rowH = 24 end

  return {
    w = w, h = h,
    margin = margin, gap = gap,
    titleFont = titleFont, titleY = topPad,
    row1Y = rowsTop,
    row2Y = rowsTop + rowH + rowGap,
    confirmY = rowsTop + 2 * (rowH + rowGap),
    rowH = rowH,
  }
end

local L = computeLayout()

local function rectsForRow(y, h, n)
  local w = (L.w - L.margin * 2 - L.gap * (n - 1)) / n
  local rects = {}
  for i = 1, n do
    rects[i] = { x = L.margin + (i - 1) * (w + L.gap), y = y, w = w, h = h }
  end
  return rects
end

local confirmRect = { x = L.margin, y = L.confirmY, w = L.w - 2 * L.margin, h = L.rowH }

local function pointRow1Rects() return rectsForRow(L.row1Y, L.rowH, 4) end
local function pointRow2Rects() return rectsForRow(L.row2Y, L.rowH, 4) end

local flatCells = {}
for i = 1, #pointOptions do table.insert(flatCells, { kind = "point", idx = i }) end
table.insert(flatCells, { kind = "confirm" })
local cursorFlatIndex = 1

local function rectForCell(cell, r1, r2)
  if cell.kind == "point" then
    if cell.idx <= 4 then
      return r1[cell.idx]
    else
      return r2[cell.idx - 4]
    end
  else
    return confirmRect
  end
end

local function confirmSelection()
  confirmed = staged
  model.setGlobalVariable(GV_INDEX, FM_INDEX, gvValueForStep(confirmed, #pointOptions))
end

local function trySend()
  if not sendEnabled then return end
  confirmSelection()
  sendEnabled = false
end

local function markSelectionChanged()
  sendEnabled = true
end

local function drawConfirmBadge(rect)
  local bw, bh = L.margin * 3, L.margin * 2
  local bx = rect.x + rect.w - bw
  local by = rect.y
  lcd.drawFilledRectangle(bx, by, bw, bh, lcd.RGB(175, 255, 100))
  lcd.drawText(bx + bw / 2, by + bh / 2 - 6, "OK", CENTER + lcd.RGB(10, 40, 0) + SMLSIZE)
end

local function drawPointCell(rect, i)
  local opt = pointOptions[i]
  local isStaged = (staged == i - 1)
  local isConfirmed = (confirmed == i - 1)

  lcd.drawFilledRectangle(rect.x, rect.y, rect.w, rect.h, opt.color)
  lcd.drawText(rect.x + rect.w / 2, rect.y + rect.h / 2 - 8, opt.label, CENTER + opt.textColor + MIDSIZE)

  if isStaged then
    lcd.drawRectangle(rect.x - 3, rect.y - 3, rect.w + 6, rect.h + 6, lcd.RGB(255, 255, 255), 3)
  end
  if isConfirmed then
    drawConfirmBadge(rect)
  end
end

local function drawConfirmButton()
  local bg = sendEnabled and lcd.RGB(175, 255, 100) or lcd.RGB(60, 60, 60)
  local fg = sendEnabled and lcd.RGB(10, 40, 0) or lcd.RGB(150, 150, 150)
  local r = confirmRect
  lcd.drawFilledRectangle(r.x, r.y, r.w, r.h, bg)
  lcd.drawText(r.x + r.w / 2, r.y + r.h / 2 - 8, "SEND", CENTER + fg + MIDSIZE)
end

local function drawTitle()
  local font = L.titleFont
  local parts = {
    { text = "AcroLED Lite", color = lcd.RGB(233, 60, 76) },
    { text = " / ",      color = lcd.RGB(255, 255, 255) },
    { text = "YGTECH",   color = lcd.RGB(255, 185, 30) },
  }
  local totalW = 0
  for _, p in ipairs(parts) do
    p.w = lcd.sizeText(p.text, font)
    totalW = totalW + p.w
  end
  local x = L.w / 2 - totalW / 2
  for _, p in ipairs(parts) do
    lcd.drawText(x, L.titleY, p.text, p.color + font)
    x = x + p.w
  end
end

local function drawCursorHighlight(cell, r1, r2)
  local r = rectForCell(cell, r1, r2)
  lcd.drawRectangle(r.x - 6, r.y - 6, r.w + 12, r.h + 12, lcd.RGB(255, 255, 0), 2)
end

local COL_BLACK = lcd.RGB(0, 0, 0)
local COL_WHITE = lcd.RGB(255, 255, 255)
local COL_CLUB_RED = lcd.RGB(255, 0, 0)

local CLUB_LOGO_ASPECT = 1.0199
local CLUB_LOGO_SHAPES = {
  { color = COL_BLACK,
    {0.9818,0.2146,0.9592,0.1967,0.9307,0.1885,0.5469,0.1882,0.5469,0.1161,0.7275,0.1159,0.7454,0.1115,0.7638,0.0991,0.7791,0.0720,0.7791,0.0441,0.7638,0.0170,0.7367,0.0017,0.2772,0.0000,0.2589,0.0030,0.2395,0.0140,0.2237,0.0355,0.2192,0.0581,0.2237,0.0807,0.2395,0.1021,0.2546,0.1115,0.2725,0.1159,0.4531,0.1161,0.4531,0.1882,0.0693,0.1885,0.0357,0.1995,0.0182,0.2146,0.0084,0.2290,0.0000,0.2637,0.0000,0.9445,0.0038,0.9683,0.0182,0.9936,0.0461,1.0140,0.0755,1.0199,0.9245,1.0199,0.9484,1.0161,0.9737,1.0018,0.9941,0.9738,1.0000,0.9445,1.0000,0.2637,0.9962,0.2398},
  },
  { color = COL_WHITE,
    {0.3552,0.5642,0.2934,0.5024,0.2316,0.5642,0.1767,0.5093,0.2385,0.4475,0.1767,0.3857,0.2316,0.3308,0.2934,0.3926,0.3552,0.3308,0.4101,0.3857,0.3483,0.4475,0.4101,0.5093},
    {0.2790,0.2732,0.2514,0.2777,0.2130,0.2921,0.1901,0.3064,0.1606,0.3337,0.1380,0.3671,0.1274,0.3922,0.1191,0.4331,0.1191,0.4618,0.1236,0.4895,0.1380,0.5278,0.1523,0.5508,0.1796,0.5802,0.2130,0.6028,0.2381,0.6134,0.2790,0.6218,0.3077,0.6218,0.3354,0.6173,0.3737,0.6028,0.3966,0.5886,0.4261,0.5613,0.4487,0.5278,0.4593,0.5027,0.4677,0.4618,0.4677,0.4331,0.4632,0.4055,0.4487,0.3671,0.4345,0.3442,0.4072,0.3147,0.3737,0.2921,0.3486,0.2815,0.3077,0.2732},
  },
  { color = COL_CLUB_RED,
    {0.8942,0.4618,0.8897,0.4895,0.8753,0.5278,0.8610,0.5508,0.8337,0.5802,0.8003,0.6028,0.7752,0.6134,0.7343,0.6218,0.7056,0.6218,0.6779,0.6173,0.6396,0.6028,0.6166,0.5886,0.5871,0.5613,0.5646,0.5278,0.5540,0.5027,0.5456,0.4618,0.5456,0.4331,0.5501,0.4055,0.5646,0.3671,0.5788,0.3442,0.6061,0.3147,0.6396,0.2921,0.6646,0.2815,0.7056,0.2732,0.7343,0.2732,0.7619,0.2777,0.8003,0.2921,0.8232,0.3064,0.8527,0.3337,0.8753,0.3671,0.8859,0.3922,0.8942,0.4331},
  },
  { color = COL_WHITE,
    {0.6581,0.5642,0.6032,0.5093,0.7817,0.3308,0.8366,0.3857},
  },
  { color = COL_WHITE,
    {0.6032,0.3857,0.6581,0.3308,0.8366,0.5093,0.7817,0.5642},
  },
  { color = COL_WHITE,
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

local JUMPER_BANNER_ASPECT = 0.5495
local JUMPER_BANNER_SHAPES = {
  {
    {0.2409,0.5117,0.2484,0.5117,0.2486,0.5307,0.2529,0.5333,0.2570,0.5333,0.2570,0.5117,0.2645,0.5117,0.2645,0.5333,0.2727,0.5333,0.2727,0.5117,0.2802,0.5117,0.2802,0.5392,0.2444,0.5376,0.2410,0.5314},
  },
  {
    {0.2873,0.5117,0.2948,0.5117,0.2949,0.5307,0.2993,0.5333,0.3033,0.5333,0.3033,0.5117,0.3109,0.5117,0.3109,0.5333,0.3190,0.5333,0.3190,0.5117,0.3265,0.5117,0.3265,0.5392,0.2908,0.5376,0.2874,0.5314},
  },
  {
    {0.3336,0.5117,0.3411,0.5117,0.3413,0.5307,0.3457,0.5333,0.3497,0.5333,0.3497,0.5117,0.3573,0.5117,0.3573,0.5333,0.3654,0.5333,0.3654,0.5117,0.3729,0.5117,0.3729,0.5392,0.3372,0.5376,0.3338,0.5314},
  },
  {
    {0.3864,0.5392,0.3796,0.5392,0.3796,0.5318,0.3864,0.5318},
  },
  {
    {0.3949,0.5015,0.4024,0.5015,0.4024,0.5087,0.3949,0.5087},
    {0.3880,0.5489,0.3880,0.5432,0.3947,0.5406,0.3949,0.5117,0.4024,0.5117,0.4016,0.5434,0.3973,0.5478},
  },
  {
    {0.4353,0.5117,0.4353,0.5392,0.4175,0.5391,0.4123,0.5370,0.4095,0.5306,0.4094,0.5117,0.4169,0.5117,0.4170,0.5302,0.4206,0.5333,0.4277,0.5333,0.4277,0.5117},
  },
  {
    {0.4803,0.5153,0.4820,0.5392,0.4744,0.5392,0.4742,0.5201,0.4699,0.5176,0.4659,0.5176,0.4659,0.5392,0.4583,0.5392,0.4583,0.5176,0.4502,0.5176,0.4502,0.5392,0.4426,0.5392,0.4426,0.5117,0.4737,0.5118},
  },
  {
    {0.4966,0.5333,0.5040,0.5330,0.5076,0.5305,0.5088,0.5235,0.5060,0.5187,0.4966,0.5176},
    {0.5107,0.5133,0.5164,0.5221,0.5147,0.5336,0.5084,0.5385,0.4966,0.5392,0.4966,0.5495,0.4890,0.5495,0.4890,0.5117},
  },
  {
    {0.5447,0.5392,0.5302,0.5388,0.5233,0.5345,0.5205,0.5233,0.5254,0.5140,0.5447,0.5117,0.5447,0.5176,0.5318,0.5179,0.5288,0.5225,0.5447,0.5225,0.5447,0.5283,0.5288,0.5283,0.5320,0.5329,0.5447,0.5333},
  },
  {
    {0.5700,0.5134,0.5728,0.5241,0.5655,0.5241,0.5643,0.5185,0.5584,0.5176,0.5584,0.5392,0.5509,0.5392,0.5509,0.5117},
  },
  {
    {0.5867,0.5280,0.5736,0.5280,0.5736,0.5212,0.5867,0.5212},
  },
  {
    {0.6096,0.5134,0.6123,0.5241,0.6050,0.5241,0.6039,0.5185,0.5980,0.5176,0.5980,0.5392,0.5904,0.5392,0.5904,0.5117},
  },
  {
    {0.6398,0.5117,0.6398,0.5176,0.6261,0.5184,0.6227,0.5255,0.6267,0.5326,0.6398,0.5333,0.6398,0.5392,0.6200,0.5368,0.6151,0.5276,0.6178,0.5159,0.6242,0.5121},
  },
  {
    {0.6516,0.5392,0.6447,0.5392,0.6447,0.5318,0.6516,0.5318},
  },
  {
    {0.6811,0.5117,0.6811,0.5176,0.6675,0.5184,0.6641,0.5255,0.6680,0.5326,0.6811,0.5333,0.6811,0.5392,0.6614,0.5368,0.6565,0.5276,0.6592,0.5159,0.6656,0.5121},
  },
  {
    {0.6988,0.5171,0.6941,0.5197,0.6929,0.5271,0.6953,0.5324,0.7005,0.5338,0.7051,0.5312,0.7063,0.5235,0.7043,0.5187},
    {0.7055,0.5121,0.7133,0.5202,0.7125,0.5328,0.7041,0.5391,0.6914,0.5377,0.6856,0.5299,0.6867,0.5182,0.6939,0.5122},
  },
  {
    {0.7574,0.5153,0.7591,0.5392,0.7515,0.5392,0.7513,0.5201,0.7470,0.5176,0.7430,0.5176,0.7430,0.5392,0.7354,0.5392,0.7354,0.5176,0.7273,0.5176,0.7273,0.5392,0.7197,0.5392,0.7197,0.5117,0.7508,0.5118},
  },
  {
    {0.0000,0.4448,0.0000,0.4197,1.0000,0.4197,1.0000,0.4448},
  },
  {
    {0.6676,0.2300,0.6542,0.2110,0.6346,0.2020,0.5080,0.2009,0.4289,0.2813,0.3931,0.2009,0.3409,0.2014,0.2955,0.3712,0.3487,0.3712,0.3692,0.2948,0.4043,0.3735,0.5287,0.2470,0.6057,0.2470,0.6122,0.2499,0.6154,0.2562,0.6117,0.2690,0.5996,0.2773,0.5194,0.2777,0.4943,0.3712,0.5475,0.3712,0.5602,0.3239,0.5960,0.3236,0.6117,0.3204,0.6327,0.3100,0.6512,0.2937,0.6623,0.2775,0.6681,0.2624,0.6704,0.2462},
  },
  {
    {0.6666,0.3061,0.7521,0.3061,0.7612,0.2775,0.6853,0.2775,0.6783,0.2921},
  },
  {
    {0.5665,0.3712,0.7380,0.3712,0.7503,0.3250,0.6362,0.3250,0.6066,0.3441,0.5913,0.3494,0.5714,0.3526},
  },
  {
    {0.2534,0.3547,0.2799,0.3330,0.2985,0.3070,0.3066,0.2860,0.3293,0.2009,0.2761,0.2009,0.2488,0.2976,0.2420,0.3078,0.2314,0.3176,0.2217,0.3229,0.2103,0.3250,0.2001,0.3229,0.1933,0.3175,0.1881,0.3084,0.1865,0.2984,0.2110,0.2009,0.1578,0.2009,0.1325,0.2991,0.1331,0.3214,0.1411,0.3419,0.1488,0.3520,0.1602,0.3614,0.1737,0.3676,0.1894,0.3708,0.2069,0.3708,0.2242,0.3676},
  },
  {
    {0.2885,0.0229,0.2676,0.0098,0.2484,0.0029,0.2288,0.0000,0.2091,0.0010,0.1901,0.0056,0.1722,0.0138,0.1561,0.0255,0.1423,0.0404,0.1268,0.0694,0.0674,0.2939,0.0574,0.3093,0.0433,0.3206,0.0320,0.3246,0.0123,0.3250,-0.0000,0.3712,0.0280,0.3703,0.0537,0.3633,0.0782,0.3492,0.1028,0.3260,0.1131,0.3109,0.1207,0.2946,0.1476,0.1996,0.1727,0.1351,0.1985,0.0886,0.2235,0.0570,0.2463,0.0376,0.2655,0.0274},
  },
  {
    {0.1620,0.1835,0.1748,0.1835,0.1876,0.1686,0.2026,0.1568,0.2193,0.1480,0.2372,0.1425,0.2558,0.1403,0.2747,0.1416,0.2933,0.1465,0.3111,0.1551,0.3215,0.1320,0.3258,0.1080,0.3243,0.0839,0.3173,0.0609,0.2899,0.0661,0.2680,0.0735,0.2430,0.0857,0.2171,0.1040,0.1923,0.1293,0.1810,0.1451},
  },
  {
    {0.9425,0.3712,0.8845,0.3712,0.8472,0.2776,0.9069,0.2760,0.9129,0.2718,0.9178,0.2635,0.9187,0.2546,0.9146,0.2489,0.9087,0.2466,0.6915,0.2466,0.6871,0.2202,0.6765,0.2009,0.9323,0.2009,0.9548,0.2089,0.9652,0.2188,0.9725,0.2345,0.9739,0.2460,0.9713,0.2636,0.9638,0.2815,0.9547,0.2942,0.9413,0.3065,0.9228,0.3175},
  },
  {
    {0.8410,0.2775,0.7832,0.2775,0.7768,0.2807,0.7568,0.3616,0.7595,0.3694,0.7644,0.3712,0.8252,0.3712,0.8312,0.3515,0.7860,0.3515,0.7991,0.2978,0.8322,0.2978},
  },
  {
    {1.0000,0.4633,1.0000,0.4620,0.0000,0.4620,0.0000,0.4633},
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

local function drawJumperBanner(leftX, topY, width, color)
  for _, shape in ipairs(JUMPER_BANNER_SHAPES) do
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
    drawFilledPolygonMulti(contours, color)
  end
end

local function drawSplash()
  lcd.clear(lcd.RGB(245, 225, 180))

  local marginX = L.w * 0.08
  local availH = L.h * 0.72
  local clubW = math.min(L.w * 0.28, availH / CLUB_LOGO_ASPECT)
  local clubH = clubW * CLUB_LOGO_ASPECT
  local leftX = marginX
  local topY = (L.h - clubH) / 2

  drawClubLogo(leftX, topY, clubW)

  local bannerGap = L.w * 0.05
  local bannerLeft = leftX + clubW + bannerGap
  local bannerMaxW = (L.w - marginX) - bannerLeft
  local bannerW = bannerMaxW
  if bannerW * JUMPER_BANNER_ASPECT > availH then
    bannerW = availH / JUMPER_BANNER_ASPECT
  end
  local bannerX = (L.w - marginX) - bannerW
  local bannerY = L.h / 2 - (bannerW * JUMPER_BANNER_ASPECT) / 2

  drawJumperBanner(bannerX, bannerY, bannerW, lcd.RGB(167, 42, 46))
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

  lcd.clear(lcd.RGB(15, 15, 15))
  drawTitle()

  local r1 = pointRow1Rects()
  for i = 1, 4 do drawPointCell(r1[i], i) end
  local r2 = pointRow2Rects()
  for i = 1, 4 do drawPointCell(r2[i], i + 4) end
  drawConfirmButton()

  if touchState ~= nil and touchState.x ~= nil and touchState.y ~= nil then
    local tapped = false
    if touchState.event ~= nil then
      if touchState.event == TOUCH_START or touchState.event == TOUCH_END or touchState.tapCount ~= nil then
        tapped = true
      end
    else
      tapped = true
    end

    if tapped then
      for i, rect in ipairs(r1) do
        if touchState.x >= rect.x and touchState.x <= rect.x + rect.w
           and touchState.y >= rect.y and touchState.y <= rect.y + rect.h then
          staged = i - 1
          markSelectionChanged()
        end
      end
      for i, rect in ipairs(r2) do
        if touchState.x >= rect.x and touchState.x <= rect.x + rect.w
           and touchState.y >= rect.y and touchState.y <= rect.y + rect.h then
          staged = i + 4 - 1
          markSelectionChanged()
        end
      end
      local cr = confirmRect
      if touchState.x >= cr.x and touchState.x <= cr.x + cr.w
         and touchState.y >= cr.y and touchState.y <= cr.y + cr.h then
        trySend()
      end
    end
  end

  local cell = flatCells[cursorFlatIndex]
  drawCursorHighlight(cell, r1, r2)

  if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT then
    cursorFlatIndex = cursorFlatIndex + 1
    if cursorFlatIndex > #flatCells then cursorFlatIndex = 1 end
  elseif event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT then
    cursorFlatIndex = cursorFlatIndex - 1
    if cursorFlatIndex < 1 then cursorFlatIndex = #flatCells end
  elseif event == EVT_VIRTUAL_ENTER then
    if cell.kind == "point" then
      staged = cell.idx - 1
      markSelectionChanged()
    else
      trySend()
    end
  elseif event == EVT_VIRTUAL_EXIT_LONG then
    return 2
  end

  return 0
end

local function init()
  local v = model.getGlobalVariable(GV_INDEX, FM_INDEX)
  staged = stepFromGvValue(v, #pointOptions)
  confirmed = staged

  sendEnabled = true

  showingSplash = true
  splashStartCs = getTime()
end

return { init = init, run = run }
