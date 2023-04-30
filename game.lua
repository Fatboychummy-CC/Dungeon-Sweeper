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

local term_w, term_h = term.getSize() ---@type integer, integer
local main_w_cover, main_h_cover = term_w % 2 == 0 and 1 or 0, term_h % 2 == 0 and 1 or 0
local main_win = window.create(term.current(), 1 + main_w_cover, 2, term_w - 1 - main_w_cover, term_h - 1 - main_h_cover)
local flash_win = window.create(term.current(), 1 + main_w_cover, 2, term_w - 1 - main_w_cover, term_h - 1 - main_h_cover)
local stats_win = window.create(term.current(), 1, 1, term_w, 1)
local levels_win = window.create(term.current(), term_w, 2, 1, term_h - 1)
local console_win = window.create(term.current(), 1, 1, term.getSize())
console_win.setVisible(false)

local _print = print
local function print(...)
  local old = term.redirect(console_win)
  _print(...)
  term.redirect(old)
end

local hp = 30
local xp = 0
local lvl = 1
local time = 0

local flash_kill_timer

local BOARD_FILL = 0.2 -- 20% filled with enemies?
local PERCENT_REQUIRED_BEGIN = 0.5
local PERCENT_REQUIRED_INCR  = 0.088

---@type Array<integer>
local level_thresholds = {}

---@type Array<Enemy>
local enemies = {
  {}
}

--- Stores all node information
---@type {[string]:Node}
local nodes = {}

--- Stores which positions have been uncovered.
---@type {[string]:boolean?}
local uncovered = {}

---@type BoxObject
local box = {
  " \x95", "\x8f\x85",
  { "75", "57" },
  { "55", "77" }
}
local uncovered_box = {
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

  print("Init enemy width, height =", w, h)

  for y = 1, h do
    for x = 1, w do
      draw_object(main_win, box, x, y)
    end
  end

  -- Set the positions of all the enemies.

  nodes = {}
  uncovered = {}

  local total = math.floor(w * h * BOARD_FILL)
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
  print("Enemies:")
  for i = 1, 9 do
    local threshold = math.ceil(percent_required * enemy_levels[i])
    sum = sum + threshold * i
    print(("Level:%d | Count:%2d | %%%3d | Diff:%3d | Total:%4d"):format(i, enemy_levels[i], percent_required * 100, threshold * i, sum))
    percent_required = percent_required + PERCENT_REQUIRED_INCR
    level_thresholds[i] = sum
  end

  sum = 0
  for i = 1, 9 do
    sum = sum + enemy_levels[i] * i
  end
  print("Total XP to earn:", sum)

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

  -- clear terminal
  term.setBackgroundColor(colors.gray)
  term.clear()

  -- clear all windows
  stats_win.clear()
  levels_win.clear()
  main_win.setBackgroundColor(colors.red)
  main_win.clear()

  -- initialize the board and stats
  init_enemies()
  init_board()
  draw_stats()
  draw_levels()
end

--- Display the death screen.
local function popup_death()
  error("You died.") --TODO make this not temporary.
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
    print("Player took", before - hp, "damage.")
    flash(colors.red)
  end

  if hp <= 0 then
    hp = 0
  else
    print("Player gained", enemy.Level, "experience.")
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

--- Uncover a node.
---@param x integer The X position to draw to.
---@param y integer The Y position to draw to.
---@return boolean died If the player died as a result of uncovering this node.
local function uncover(x, y)
  local pos = x .. ":" .. y
  local node = nodes[pos]
  if not node then
    print("Nil node passed.")
    return false
  end

  print("Uncover node at", pos, "Guessed:", node.GuessedLevel)

  if node.GuessedLevel <= lvl or node.GuessedLevel == 0 then
    uncovered[pos] = true
    node.Revealed = true
    print("Node uncovered.")
    if node.Enemy then
      print("Node has enemy!")
      fight_enemy(node.Enemy)
      draw_stats()

      local sum = sum_neighbours(x, y)

      node.Enemy.Object[2] = ("%2d"):format(sum)

      draw_object(main_win, node.Enemy.Object, x, y)

      if hp <= 0 then
        sleep(2)
        popup_death()
        return true
      end
    else
      print("No enemy for this node.")

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

  return false
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

local function run_game()
  init_all()

  local timer = os.startTimer(1)
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
            if uncover(o_x, o_y) then
              return
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

print("Console is ready.")
local ok, err = pcall(run_game)
if not ok then
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  error(err, 0)
end
