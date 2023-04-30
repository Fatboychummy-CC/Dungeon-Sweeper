---@class BoxObject : {[1]:string, [2]:string, [3]:DualColor, [4]:DualColor}

---@class TextColor : string
---@class BGColor : string

---@class DualColor : {[1]:TextColor, [2]:BGColor}

---@generic T
---@class Array<T> : {[number]:T}

---@class Enemy
---@field Object BoxObject The object to be drawn when this enemy is revealed.
---@field Level integer The level of this enemy.
---@field Health integer The health of this enemy.

---@class Position2 : {x:integer, y:integer}

---@class Node
---@field Enemy Enemy? The enemy object, if one is at this position.
---@field Revealed boolean If this node has been revealed.
---@field Toggled boolean If this revealed enemy node has been toggled.
---@field GuessedLevel integer The level the player is assuming this node is. If the player's level is lower than the guessed level, it should not reveal when clicked.
---@field X integer The X position of the node.
---@field Y integer The Y position of the node.

---@class Color : integer

local strings = require "cc.strings"

local term_w, term_h = term.getSize() ---@type integer, integer
local main_w_cover, main_h_cover = term_w % 2 == 0 and 1 or 0, term_h % 2 == 0 and 1 or 0
local term_win = window.create(term.current(), 1, 1, term.getSize())
local main_win = window.create(term.current(), 1 + main_w_cover, 2, term_w - 1 - main_w_cover, term_h - 1 - main_h_cover)
local flash_win = window.create(term.current(), 1 + main_w_cover, 2, term_w - 1 - main_w_cover, term_h - 1 - main_h_cover)
local stats_win = window.create(term.current(), 1, 1, term_w, 1)
local levels_win = window.create(term.current(), term_w, 2, 1, term_h - 1)
local console_win = window.create(term.current(), 1, 1, term.getSize())
console_win.setVisible(false)
local function console_print(...)
  local old = term.redirect(console_win)
  print(...)
  term.redirect(old)
end

local hp                     = 30
local xp                     = 0
local lvl                    = 1
local time                   = 0
local n_uncovered            = 0
local difficulty             = 1

local flash_kill_timer

local board_fill             = 0.2 -- 20% filled with enemies?
local PERCENT_REQUIRED_BEGIN = 0.5
local percent_required_incr  = 0.088

---@type Array<integer>
local level_thresholds       = {}

---@type Array<Enemy>
local enemies                = {
  {}
}

--- Stores all node information
---@type {[string]:Node}
local nodes                  = {}

--- Stores which positions have been uncovered.
---@type {[string]:boolean?}
local uncovered              = {}

---@type BoxObject
local box                    = {
  " \x95", "\x8f\x85",
  { "75", "57" },
  { "55", "77" }
}
local uncovered_box          = {
  "\x87\x8b", "  ",
  { "00", "ff" },
  { "00", "ff" }
}

--- Create a deep clone of the inserted value.
---@param t any The value to clone, recommend table.
local function deep_copy(t)
  if type(t) ~= "table" then
    return t
  end

  local clone = {}

  for k, v in pairs(t) do
    if type(v) == "table" then
      clone[k] = deep_copy(v)
    else
      clone[k] = v
    end
  end

  return clone
end

--- Create an enemy object.
---@param level integer The level of this enemy. Health and level are set to this.
---@param object BoxObject The object this enemy will become when revealed.
---@return Enemy enemy The enemy object.
local function create_enemy(level, object)
  return {
    Object = deep_copy(object),
    Level = level,
    Health = level
  }
end

--- Create a new node object.
---@param x integer The X position of this node.
---@param y integer The Y position of this node.
---@return Node Node The node.
local function create_node(x, y)
  return {
    Revealed = false,
    Toggled = false,
    GuessedLevel = 0,
    X = x,
    Y = y
  }
end

--- Draw a BoxObject to the screen
---@param t_obj table The term object to draw to.
---@param object BoxObject The box object to be drawn.
---@param x integer The X position of the object.
---@param y integer The Y position of the object.
local function draw_object(t_obj, object, x, y)
  x = x * 2 - 1 + main_w_cover
  y = y * 2 - 1
  t_obj.setCursorPos(x, y)
  t_obj.blit(object[1], object[3][1], object[3][2])
  t_obj.setCursorPos(x, y + 1)
  t_obj.blit(object[2], object[4][1], object[4][2])
end

--- Initialize the board (and enemy positions on the board)
local function init_board()
  local w, h = main_win.getSize()
  w = math.floor(w / 2)
  h = math.floor(h / 2)

  console_print("Init enemy width, height =", w, h)

  for y = 1, h do
    for x = 1, w do
      draw_object(main_win, box, x, y)
    end
  end

  -- Set the positions of all the enemies.

  nodes = {}
  uncovered = {}

  local total = math.floor(w * h * board_fill)
  local percentages = { --- The percentage of enemies of each level.
    0.20,
    0.15,
    0.14,
    0.13,
    0.11,
    0.10,
    0.09,
    0.07,
    0.01,
  }
  local function sum_to(n)
    local sum = 0

    for i = 1, n do
      sum = sum + percentages[i]
    end

    return sum
  end
  local function next_level(i)
    for j = 1, #percentages do
      if i / total < sum_to(j) then
        return j
      end
    end

    return 9
  end

  local enemy_levels = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  for i = 1, total do
    local level = next_level(i)
    level = math.min(9, math.max(level, 1))
    local enemy_object = deep_copy(enemies[level])
    enemy_levels[level] = enemy_levels[level] + 1

    -- Ensure no position is used twice. This is technically O(infinity) :)
    local pos, x, y
    repeat
      x, y = math.random(1, w), math.random(1, h)
      pos = x .. ":" .. y
    until not nodes[pos]

    local node = create_node(x, y)
    node.Enemy = enemy_object

    nodes[pos] = node
  end

  local sum = 0
  local percent_required = PERCENT_REQUIRED_BEGIN
  console_print("Enemies:")
  for i = 1, 9 do
    local threshold = math.ceil(percent_required * enemy_levels[i])
    sum = sum + threshold * i
    console_print(("Level:%d | Count:%2d | %%%3d | Diff:%3d | Total:%4d"):format(i, enemy_levels[i],
      percent_required * 100,
      threshold * i, sum))
    percent_required = percent_required + percent_required_incr
    level_thresholds[i] = sum
  end
  level_thresholds[10] = 10000000

  sum = 0
  for i = 1, 9 do
    sum = sum + enemy_levels[i] * i
  end
  console_print("Total XP to earn:", sum)

  -- Create leftover nodes.
  for x = 1, w do
    for y = 1, h do
      local pos = x .. ":" .. y
      if not nodes[pos] then
        nodes[pos] = create_node(x, y)
      end
    end
  end
end

local function get_next_level_exp()
  return level_thresholds[lvl]
end

local function draw_stats()
  stats_win.clear()
  stats_win.setCursorPos(1, 1)
  stats_win.write(("LV:%d  HP:%02d  XP:%d  NL:%d"):format(lvl, hp, xp, get_next_level_exp()))

  local w = stats_win.getSize()
  local s_time = ("TIME:%d"):format(time)
  stats_win.setCursorPos(w - #s_time + 1, 1)
  stats_win.write(s_time)
end

local enemies_initted = false
--- Initialize the enemies.
local function init_enemies()
  if enemies_initted then return end
  enemies_initted = true

  for i = 1, 9 do
    enemies[i] = create_enemy(
      i,
      {
        "\x8c\x8c", "  ",
        { tostring(i):rep(2) --[[@as TextColor]], "ff" --[[@as BGColor]] },
        { "ee" --[[@as TextColor]],               "ff" --[[@as BGColor]] }
      }
    )
  end
end

local function draw_levels()
  for i = 1, 9 do
    levels_win.setCursorPos(1, i * 2 - 1)
    levels_win.blit('\x8c', tostring(i), 'f')
    levels_win.setCursorPos(1, i * 2)
    levels_win.blit(tostring(i), '0', 'f')
  end
end

--- Initialize all parts of the game.
local function init_all()
  -- Reset all values to initial values
  hp = 30
  xp = 0
  lvl = 1
  time = 0
  n_uncovered = 0

  -- clear terminal
  term.setBackgroundColor(colors.gray)
  term.clear()

  -- clear all windows
  stats_win.clear()
  levels_win.clear()
  main_win.setBackgroundColor(colors.red)
  main_win.clear()

  -- Set difficulty (amount of enemies)
  board_fill = difficulty == 1 and 0.1 or difficulty == 2 and 0.2 or difficulty == 3 and 0.35 or 1
  percent_required_incr = difficulty == 1 and 0.06 or difficulty == 2 and 0.07 or difficulty == 3 and 0.088 or 0.095

  -- initialize the board and stats
  init_enemies()
  init_board()
  draw_stats()
  draw_levels()
end

--- Draw a box to the given terminal object.
---@param t_obj table The terminal object.
---@param x integer The X position of the top left point of the box.
---@param y integer The Y position of the top left point of the box.
---@param w integer The width of the box.
---@param h integer The height of the box.
---@param color Color The color to set.
local function draw_box(t_obj, x, y, w, h, color)
  t_obj.setBackgroundColor(color)
  local txt = string.rep(' ', w)
  for _y = y, y + h - 1 do
    t_obj.setCursorPos(x, _y)
    t_obj.write(txt)
  end
end

--- Popup a message to the player.
---@param title string The title of the popup box.
---@param body string The body text of the popup box.
---@param color Color The color to use for the icon.
---@param char string The icon character.
---@param options Array<string>? The options to use.
---@return integer selected The option selected.
local function popup(t_obj, title, body, color, char, options)
  options = options or { "Okay" }

  local w, h = t_obj.getSize()
  t_obj.setBackgroundColor(colors.black)
  t_obj.clear()

  --]==] Ensure the max height of the body of text is 5 lines
  local function wrap(body_text, wrap_width)
    local lines

    -- first try checking if it's possible to fit in 5 lines.
    repeat
      wrap_width = wrap_width + 1
      lines = strings.wrap(body_text, wrap_width)
    until #lines <= 5 or wrap_width > (w - 2)

    -- if not, shorten the text.
    if wrap_width > w - 2 then
      wrap_width = w - 4
      repeat
        body_text = body_text:sub(1, -6) .. "..."
        lines = strings.wrap(body_text, wrap_width)
      until #lines <= 5
    end

    -- strings.wrap for some reason keeps spaces at the end of lines, remove them.
    for i, line in ipairs(lines) do
      if line:sub(-1) == ' ' then
        lines[i] = line:sub(1, -2)
      end
    end

    return lines, wrap_width
  end

  local lines, wrapWidth = wrap(body, 20)

  -- so now we have width and height of the text, let's figure out the buttons.
  local nOptions = #options
  -- each button is one wider than the text, and minimum one space between them.
  local minimumRequiredWidth = nOptions * 4
  for i = 1, nOptions do
    minimumRequiredWidth = minimumRequiredWidth + #options[i]
  end

  if minimumRequiredWidth > w then
    error("Pop-up options are too long to fit on screen.", 2)
  elseif minimumRequiredWidth > wrapWidth then
    -- we need to re-wrap at the new width.
    lines = wrap(body, minimumRequiredWidth)
    wrapWidth = minimumRequiredWidth
  end
  -- button_height + #lines + info_line + padding + top_bottom
  local totalHeight = 3 + #lines + 1 + 2 + 2
  -- wrapWidth + side_padding
  local totalWidth = wrapWidth + 4
  local topLeftPos = {
    math.floor(w / 2 - totalWidth / 2 + 0.5),
    math.floor(h / 2 - totalHeight / 2 + 0.5)
  }

  -- draw top gray line
  draw_box(t_obj, topLeftPos[1], topLeftPos[2], totalWidth, 1, colors.gray)
  term.setCursorPos(topLeftPos[1] + 2, topLeftPos[2])
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.write(title)

  -- draw
  draw_box(t_obj, topLeftPos[1], topLeftPos[2] + 1, totalWidth, totalHeight - 1, colors.lightGray)
  draw_box(t_obj, topLeftPos[1] + 1, topLeftPos[2] + 1, totalWidth - 2, totalHeight - 2, colors.white)
  term.setBackgroundColor(color)
  term.setCursorPos(topLeftPos[1], topLeftPos[2])
  term.write(char)

  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  for i = 1, #lines do
    term.setCursorPos(topLeftPos[1] + 2, topLeftPos[2] + 1 + i)
    term.write(lines[i])
  end

  local function makeColors(fg, bg)
    return {
      topLeft  = { string.char(0x97), fg, bg },
      top      = { string.char(0x83), fg, bg },
      topRight = { string.char(0x94), bg, fg },
      left     = { string.char(0x95), fg, bg },
      right    = { string.char(0x95), bg, fg },
      botLeft  = { string.char(0x8A), bg, fg },
      botRight = { string.char(0x85), bg, fg },
      bot      = { string.char(0x8F), bg, fg },
      mid      = bg
    }
  end

  local function makeButton(item, topLeft, top, topRight, left, right, botLeft, botRight, bot, mid)
    local working = {}
    working[1] = {
      table.concat { topLeft[1], top[1]:rep(#item), topRight[1] },
      table.concat { topLeft[2], top[2]:rep(#item), topRight[2] },
      table.concat { topLeft[3], top[3]:rep(#item), topRight[3] }
    }
    working[2] = {
      table.concat { left[1], item, right[1] },
      table.concat { left[2], ('f'):rep(#item), right[2] },
      table.concat { left[3], mid:rep(#item), right[3] }
    }
    working[3] = {
      table.concat { botLeft[1], bot[1]:rep(#item), botRight[1] },
      table.concat { botLeft[2], bot[2]:rep(#item), botRight[2] },
      table.concat { botLeft[3], bot[3]:rep(#item), botRight[3] }
    }
    return working
  end

  local clickMap

  local function redrawButtons(fg, bg, sel, fgS, bgS)
    -- buttons
    local selected = makeColors(fgS, bgS)
    local unselected = makeColors(fg, bg)

    local buttons = {}
    for i, item in ipairs(options) do
      if sel and sel == i then
        buttons[i] = makeButton(item,
          selected.topLeft, selected.top, selected.topRight, selected.left,
          selected.right, selected.botLeft, selected.botRight, selected.bot,
          selected.mid
        )
      else
        buttons[i] = makeButton(item,
          unselected.topLeft, unselected.top, unselected.topRight,
          unselected.left, unselected.right, unselected.botLeft,
          unselected.botRight, unselected.bot, unselected.mid
        )
      end
    end

    local preskip = 0
    local leftButtonPos = math.floor(w / 2 - minimumRequiredWidth / 2 + 0.5)
    clickMap = {}
    for i = 1, #buttons do
      for j = 1, 3 do
        local x, y = preskip + leftButtonPos + 2, topLeftPos[2] + 2 + #lines + j
        if not clickMap[y] then clickMap[y] = {} end
        term.setCursorPos(x, y)
        term.blit(buttons[i][j][1], buttons[i][j][2], buttons[i][j][3])
        for X = 1, #buttons[i][1][1] do
          clickMap[y][x - 1 + X] = i
        end
      end
      preskip = preskip + #buttons[i][1][1] + 1
    end
  end

  redrawButtons('7', '0')
  term.setCursorPos(1, 1)
  while true do
    local event, btn, x, y = os.pullEvent()
    if event == "mouse_up" and btn == 1 then
      if clickMap[y] and clickMap[y][x] then
        return clickMap[y][x]
      else
        redrawButtons('7', '0')
        term.setCursorPos(1, 1)
      end
    elseif (event == "mouse_click" or event == "mouse_drag") and btn == 1 then
      if clickMap[y] and clickMap[y][x] then
        redrawButtons('7', '0', clickMap[y][x], '9', '0')
      else
        redrawButtons('7', '0')
      end
    elseif (event == "mouse_move") then
      if y and clickMap[y] and clickMap[y][x] then
        redrawButtons('7', '0', clickMap[y][x], 'f', '8')
      else
        redrawButtons('7', '0')
      end
    end
  end
end

--- Display the death screen.
local function popup_death()
  return popup(
        term_win,
        "You died",
        "You have died. Do you wish to retry?",
        colors.red,
        "\x1e",
        { "Yes", "No" }
      ) == 1
end

local function popup_win()
  return popup(
    term_win,
    "You win!",
    string.format(
      "You won!\nDifficulty: %s\nTime: %d\nHP: %d",
      difficulty == 1 and "Easy" or difficulty == 2 and "Medium" or difficulty == 3 and "Hard" or "Impossible",
      time,
      hp
    ),
    colors.green,
    "\x03",
    {"Replay", "Exit"}
  ) == 1
end

--- Flash the screen a specified color.
---@param color integer The color to flash.
local function flash(color)
  flash_win.setBackgroundColor(color)
  flash_win.clear()
  main_win.setVisible(false)
  flash_kill_timer = os.startTimer(0.5)
end

--- Fight an enemy (player attack, if enemy alive, attack back. Repeat until one is dead).
---@param enemy Enemy
local function fight_enemy(enemy)
  local before = hp
  repeat
    enemy.Health = enemy.Health - lvl
    if enemy.Health > 0 then
      hp = hp - enemy.Level
    end
  until enemy.Health <= 0 or hp <= 0

  -- player took damage
  if hp < before then
    console_print("Player took", before - hp, "damage.")
    flash(colors.red)
  end

  if hp <= 0 then
    hp = 0
  else
    console_print("Player gained", enemy.Level, "experience.")
    xp = xp + enemy.Level

    local leveled_up = false
    repeat
      if xp >= level_thresholds[lvl] then
        lvl = lvl + 1
        leveled_up = true
      end
    until xp < level_thresholds[lvl]

    if leveled_up then
      flash(colors.green)
    end
  end
end


local neighbour_pos = {
  { 0,  1 },
  { 1,  0 },
  { 1,  1 },
  { 0,  -1 },
  { -1, 0 },
  { -1, -1 },
  { -1, 1 },
  { 1,  -1 }
}
--- Get a list of neighbouring nodes of this node.
---@param x integer The X position of this node.
---@param y integer The Y position of this node.
---@return Array<Node> nodes The neighbouring nodes.
local function get_neighbours(x, y)
  local neighbours = {}

  for i = 1, #neighbour_pos do
    local dx, dy = table.unpack(neighbour_pos[i], 1, 2)
    local node = nodes[(x + dx) .. ":" .. (y + dy)]
    if node then
      table.insert(neighbours, node)
    end
  end

  return neighbours
end

--- Get the sum of all neighbouring nodes' levels.
---@param x integer The X position of the node to test.
---@param y integer The Y position of the node to test.
local function sum_neighbours(x, y)
  local sum = 0

  for _, neighbour in ipairs(get_neighbours(x, y)) do
    if neighbour.Enemy then
      sum = sum + neighbour.Enemy.Level
    end
  end

  return sum
end

local mw_w, mw_h = main_win.getSize()
mw_w = math.floor(mw_w / 2)
mw_h = math.floor(mw_h / 2)

--- Uncover a node.
---@param x integer The X position to draw to.
---@param y integer The Y position to draw to.
---@return boolean died If the player died as a result of uncovering this node.
---@return boolean won If the player won as a result of uncovering this node.
---@return boolean? replay If the player wishes to replay (only returned on death or win).
local function uncover(x, y)
  local pos = x .. ":" .. y
  local node = nodes[pos]
  if not node then
    console_print("Nil node passed.")
    return false, false
  end

  console_print("Uncover node at", pos, "Guessed:", node.GuessedLevel)

  if node.GuessedLevel <= lvl or node.GuessedLevel == 0 then
    if not uncovered[pos] then
      n_uncovered = n_uncovered + 1
      console_print("Uncovered now:", n_uncovered)
    end
    uncovered[pos] = true
    node.Revealed = true
    console_print("Node uncovered.")
    if node.Enemy then
      console_print("Node has enemy!")
      fight_enemy(node.Enemy)
      draw_stats()

      local sum = sum_neighbours(x, y)

      node.Enemy.Object[2] = ("%2d"):format(sum)

      draw_object(main_win, node.Enemy.Object, x, y)

      if hp <= 0 then
        sleep(2)
        return true, false, popup_death()
      elseif hp > 0 and n_uncovered >= mw_w * mw_h then
        return false, true, popup_win()
      end
    else
      console_print("No enemy for this node.")

      local sum = sum_neighbours(x, y)

      local uncovered_clone = deep_copy(uncovered_box)
      if sum ~= 0 then
        uncovered_clone[2] = ("%2d"):format(sum)
      else
        -- uncover all neighbours.
        for _, neighbour in ipairs(get_neighbours(x, y)) do
          if not neighbour.Enemy and not neighbour.Revealed then
            uncover(neighbour.X, neighbour.Y)
          end
        end
      end
      draw_object(main_win, uncovered_clone, x, y)
    end
  end

  if n_uncovered >= mw_w * mw_h then
    return false, true, popup_win()
  end

  return false, false
end

--- Increment the guessed level at the given node position. Returns to 0 after 9.
---@param x integer The X position.
---@param y integer The Y position.
local function increment(x, y)
  local pos = x .. ":" .. y
  nodes[pos].GuessedLevel = (nodes[pos].GuessedLevel + 1) % 10

  local box_clone = deep_copy(box)
  if nodes[pos].GuessedLevel ~= 0 then
    box_clone[1] = nodes[pos].GuessedLevel .. "\x95"
  end

  draw_object(main_win, box_clone, x, y)
end

local console_visible = false
local function toggle_console()
  if console_visible then
    console_win.setVisible(false)
    main_win.setVisible(true)
    stats_win.setVisible(true)
    levels_win.setVisible(true)
  else
    console_win.setVisible(true)
    main_win.setVisible(false)
    stats_win.setVisible(false)
    levels_win.setVisible(false)
  end

  console_visible = not console_visible
end

local function set_visibility()
  console_win.setVisible(false)
  main_win.setVisible(true)
  stats_win.setVisible(true)
  levels_win.setVisible(true)
  console_visible = false
  console_win.redraw()
  main_win.redraw()
  stats_win.redraw()
  levels_win.redraw()
end

--- Play the game.
---@return boolean? replay If the player wanted to replay.
local function run_game()
  local timer = os.startTimer(1)
  set_visibility()
  while true do
    local event_data = table.pack(os.pullEvent())

    if event_data[1] == "timer" then
      if event_data[2] == timer then
        timer = os.startTimer(1)
        time = time + 1
        draw_stats()
      elseif event_data[2] == flash_kill_timer and not console_visible then
        main_win.setVisible(true)
        main_win.redraw()
      end
    elseif event_data[1] == "mouse_click" then
      local btn, x, y = table.unpack(event_data, 2, 4)
      local o_x, o_y = math.floor((x - main_w_cover + 1) / 2), math.floor(y / 2)

      local pos = o_x .. ":" .. o_y
      if nodes[pos] then             -- if within bounds
        if btn == 1 then             -- left-click
          if not uncovered[pos] then -- not yet uncovered
            local died, won, replay = uncover(o_x, o_y)
            if died or won then
              return replay
            end
          end
        elseif btn == 2 then -- right-click
          if not uncovered[pos] then
            increment(o_x, o_y)
          end
        end
      end
    elseif event_data[1] == "key" then
      local key = event_data[2]
      if key == keys.c then
        toggle_console()
      end
    end
  end
end

local function info()
  console_print("Displaying game information.")

  local txt = {
    "How to play:",
    "",
    "The game is played very similarly to MineSweeper, however instead of displaying the amount of bombs around the tile, this game displays the total *levels* of enemies around the tile.",
    "For example, if you uncover a tile with the number '3' on it, there could be one level 3 enemy next to the tile, or perhaps one level 1 and one level 2, or maybe even three level 1 enemies.",
    "",
    "Your current level is displayed at the top of the screen, along with your health, XP, and 'NL' -- the XP required for the next level.",
    "",
    "Enemies have their level in health, and deal damage equal to their health.",
    "When uncovering a tile. You attack first for your level damage. If the enemy survives, it attacks you for its level damage. This repeats until one of you dies.",
    "Uncover all tiles to win."
  }
  local text = table.concat(txt, '\n')

  term_win.setBackgroundColor(colors.black)
  term_win.setTextColor(colors.white)
  term_win.clear()
  term_win.setCursorPos(1, 1)
  local old = term.redirect(term_win)

  textutils.pagedPrint(text)
  sleep(1)
  term_win.setTextColor(colors.yellow)
  print()
  write("Press any key to return to the menu.")

  term.redirect(old)
  os.pullEvent("key")
end

console_print("Console is ready.")
local function main()
  while true do
    local option = popup(
      term_win,
      "Dungeon Sweeper",
      "Select an option.",
      colors.blue,
      "\x04",
      { "Play", "Info", "Exit" }
    )

    if option == 1 then -- Play game
      difficulty = popup(
        term_win,
        "Start Game",
        "Select a difficulty.",
        colors.green,
        "\x10",
        { "Easy", "Medium", "Hard", "Impossible" }
      )

      init_all()

      local replay = run_game()

      if not replay then return end
    elseif option == 2 then -- Info
      info()
    elseif option == 3 then -- Exit
      return
    end
  end
end

local ok, err = pcall(main)
if not ok then
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  error(err, 0)
end
