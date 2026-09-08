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
  { label = "R7", color = lcd.RGB(  3,   0, 250), textColor = COL_WHITE_TEXT },
  { label = "R8", color = lcd.RGB( 19, 250,   0), textColor = COL_DARK_TEXT  },
}

local staged = 0
local confirmed = 0

local sendEnabled = true

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

local function rectForCell(cell)
  if cell.kind == "point" then
    if cell.idx <= 4 then
      return pointRow1Rects()[cell.idx]
    else
      return pointRow2Rects()[cell.idx - 4]
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

local function drawCursorHighlight(cell)
  local r = rectForCell(cell)
  lcd.drawRectangle(r.x - 6, r.y - 6, r.w + 12, r.h + 12, lcd.RGB(255, 255, 0), 2)
end

local function run(event, touchState)
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
  drawCursorHighlight(cell)

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
end

return { init = init, run = run }
