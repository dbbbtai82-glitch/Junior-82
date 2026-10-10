--[[
  POCKET SLAYER  (version 1)
  A tiny top-down monster shooter for Rockbox on the iPod nano 2nd gen.
  Inspired by games like Mighty Doom: you move, your hero shoots by itself.

  CONTROLS
    Menu  (top of wheel)     = move up
    Play  (bottom of wheel)  = move down
    <<    (left of wheel)    = move left
    >>    (right of wheel)   = move right
    Center button            = pause / pick an upgrade
    Spin the wheel           = choose an upgrade

  You only shoot while you STAND STILL (just like Mighty Doom).
  Clear every room, pick an upgrade, and see how far you get.
  Every 5th room has a boss!

  NOTE FOR LEARNING:
  Rockbox's Lua only has whole numbers (no decimals like 1.5).
  So we store positions 16x bigger than the real pixel position
  ("fixed point"). A player at x = 160 is really at pixel 10.
]]

require("buttons")        -- gives us rb.buttons (the iPod's button codes)
local B = rb.buttons

---------------------------------------------------------------------
-- SETTINGS: try changing these numbers to tweak the game!
---------------------------------------------------------------------
local FPS                = 25    -- frames per second
local SHOOT_WHILE_MOVING = false -- set to true to make the game easier
local START_HP           = 10
local PLAYER_SPEED       = 24    -- (in 1/16 pixels per frame)
local BULLET_SPEED       = 64
local START_FIRE_DELAY   = 12    -- frames between shots (smaller = faster)

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local W, H = rb.LCD_WIDTH, rb.LCD_HEIGHT
local FP   = 16   -- fixed point scale: 16 units = 1 pixel
local HUD  = 12   -- height of the top bar (hp, room number)

-- whole-number division that works the same everywhere
local function div(a, b)
  local q = a / b
  if q >= 0 then return math.floor(q) end
  return -math.floor(-q)
end

-- "bitwise and": used to check if a button is held down
local band
if bit and bit.band then
  band = bit.band
else
  band = function(a, b)
    local result, value = 0, 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then result = result + value end
      a, b, value = div(a, 2), div(b, 2), value * 2
    end
    return result
  end
end

-- whole-number square root (for working out distances)
local function isqrt(n)
  if n <= 0 then return 0 end
  local x = n
  local y = div(x + 1, 2)
  while y < x do
    x = y
    y = div(x + div(n, x), 2)
  end
  return x
end

-- make a screen colour from red, green, blue (each 0-255)
local function rgb(r, g, b)
  return div(r, 8) * 2048 + div(g, 4) * 32 + div(b, 8)
end

local COL_BG      = rgb(20, 16, 28)
local COL_FLOOR   = rgb(40, 34, 52)
local COL_WALL    = rgb(90, 80, 110)
local COL_PLAYER  = rgb(80, 220, 255)
local COL_EYE     = rgb(10, 10, 10)
local COL_BULLET  = rgb(255, 240, 80)
local COL_EBULLET = rgb(120, 255, 120)
local COL_GRUNT   = rgb(230, 60, 60)
local COL_SPITTER = rgb(190, 90, 230)
local COL_BOSS    = rgb(255, 140, 30)
local COL_TEXT    = rgb(255, 255, 255)
local COL_HP      = rgb(230, 40, 60)
local COL_HP_BACK = rgb(70, 20, 30)
local COL_SELECT  = rgb(255, 200, 0)

local function color(c) rb.lcd_set_foreground(c) end
local function box(x, y, w, h) rb.lcd_fillrect(x, y, w, h) end

-- write text centred left-to-right
local function text_center(y, str)
  local w = 6 * #str
  if rb.lcd_getstringsize then w = rb.lcd_getstringsize(str) end
  rb.lcd_putsxy(div(W - w, 2), y, str)
end

-- is a button being held down right now?
local function held(status, button)
  return button ~= nil and band(status, button) ~= 0
end

-- collect every button press that happened since last frame
local function read_presses()
  local list = {}
  local b = rb.button_get(false)
  while b ~= nil and b ~= 0 and #list < 20 do
    list[#list + 1] = b
    b = rb.button_get(false)
  end
  return list
end

local function pressed(list, button)
  for i = 1, #list do
    if list[i] == button then return true end
  end
  return false
end

-- do two squares overlap? (x, y are centres, in fixed point)
local function touching(x1, y1, size1, x2, y2, size2)
  local reach = div((size1 + size2) * FP, 2)
  return math.abs(x1 - x2) < reach and math.abs(y1 - y2) < reach
end

-- keep a value between low and high
local function clamp(v, low, high)
  if v < low then return low end
  if v > high then return high end
  return v
end

-- 8 directions for the boss's ring of bullets (already 16x scaled)
local RING = { {16,0},{11,11},{0,16},{-11,11},{-16,0},{-11,-11},{0,-16},{11,-11} }

---------------------------------------------------------------------
-- GAME STATE
---------------------------------------------------------------------
local state      -- "title", "play", "pause", "upgrade", "dead"
local player
local enemies, bullets, ebullets
local room
local frame
local choices, choice_index

-- room edges in fixed point (where things are allowed to be)
local MIN_X, MAX_X = 4 * FP, (W - 4) * FP
local MIN_Y, MAX_Y = (HUD + 4) * FP, (H - 4) * FP

---------------------------------------------------------------------
-- UPGRADES (add your own ideas here!)
---------------------------------------------------------------------
local UPGRADES = {
  { name = "Power Up",    desc = "+1 damage",
    apply = function(p) p.damage = p.damage + 1 end },
  { name = "Quick Shot",  desc = "shoot faster",
    apply = function(p) p.fire_delay = math.max(3, p.fire_delay - 2) end },
  { name = "Swift Boots", desc = "move faster",
    apply = function(p) p.speed = p.speed + 4 end },
  { name = "Big Heart",   desc = "+3 max HP",
    apply = function(p) p.max_hp = p.max_hp + 3; p.hp = p.hp + 3 end },
  { name = "Side Shot",   desc = "+1 extra bullet",
    apply = function(p) p.extra_shots = math.min(4, p.extra_shots + 1) end },
  { name = "Med Kit",     desc = "heal to full",
    apply = function(p) p.hp = p.max_hp end },
}

local function pick_upgrades()
  -- pick 3 different upgrades at random
  local pool = {}
  for i = 1, #UPGRADES do pool[i] = UPGRADES[i] end
  choices = {}
  for i = 1, 3 do
    local n = math.random(1, #pool)
    choices[i] = pool[n]
    table.remove(pool, n)
  end
  choice_index = 1
end

---------------------------------------------------------------------
-- SPAWNING
---------------------------------------------------------------------
local function random_spot_away_from_player()
  local x, y
  repeat
    x = math.random(MIN_X, MAX_X)
    y = math.random(MIN_Y, MAX_Y)
  until math.abs(x - player.x) + math.abs(y - player.y) > 60 * FP
  return x, y
end

local function add_enemy(kind)
  local x, y = random_spot_away_from_player()
  local e = { kind = kind, x = x, y = y, cool = math.random(20, 60) }
  if kind == "grunt" then
    e.size, e.speed, e.hp = 8, 10, 3 + div(room, 2)
  elseif kind == "spitter" then
    e.size, e.speed, e.hp = 8, 6, 2 + div(room, 3)
  else -- boss
    e.size, e.speed, e.hp = 16, 8, 30 + room * 3
  end
  e.max_hp = e.hp
  enemies[#enemies + 1] = e
end

local function start_room()
  enemies, bullets, ebullets = {}, {}, {}
  player.x = div(W, 2) * FP
  player.y = (H - 14) * FP
  if room % 5 == 0 then
    add_enemy("boss")
  else
    local count = 2 + room
    for i = 1, count do
      if room >= 2 and i % 3 == 0 then add_enemy("spitter") else add_enemy("grunt") end
    end
  end
  state = "play"
end

local function new_game()
  player = {
    hp = START_HP, max_hp = START_HP,
    speed = PLAYER_SPEED, damage = 1,
    fire_delay = START_FIRE_DELAY, fire_timer = 0,
    extra_shots = 0, hurt_timer = 0, size = 8,
  }
  room = 1
  start_room()
end

---------------------------------------------------------------------
-- SHOOTING
---------------------------------------------------------------------
-- returns a velocity (vx, vy) pointing from (x1,y1) to (x2,y2)
local function aim(x1, y1, x2, y2, speed)
  local dx, dy = x2 - x1, y2 - y1
  local len = isqrt(dx * dx + dy * dy)
  if len == 0 then return speed, 0 end
  return div(dx * speed, len), div(dy * speed, len)
end

local function nearest_enemy()
  local best, best_dist = nil, nil
  for _, e in ipairs(enemies) do
    -- divide by FP first so the numbers don't get too big
    local dx, dy = div(e.x - player.x, FP), div(e.y - player.y, FP)
    local d = dx * dx + dy * dy
    if best == nil or d < best_dist then best, best_dist = e, d end
  end
  return best
end

local function player_shoot(target)
  local vx, vy = aim(player.x, player.y, target.x, target.y, BULLET_SPEED)
  bullets[#bullets + 1] = { x = player.x, y = player.y, vx = vx, vy = vy }
  -- extra bullets spread out to the sides
  for i = 1, player.extra_shots do
    local side = (i % 2 == 1) and 1 or -1
    local amount = div(i + 1, 2)
    local sx = vx - div(vy * amount * side, 4)
    local sy = vy + div(vx * amount * side, 4)
    bullets[#bullets + 1] = { x = player.x, y = player.y, vx = sx, vy = sy }
  end
end

---------------------------------------------------------------------
-- UPDATE (game logic, runs every frame)
---------------------------------------------------------------------
local function hurt_player(amount)
  if player.hurt_timer > 0 then return end
  player.hp = player.hp - amount
  player.hurt_timer = 25
  if player.hp <= 0 then state = "dead" end
end

local function update_player()
  local s = rb.button_status()
  local mx, my = 0, 0
  if held(s, B.BUTTON_MENU)  then my = -1 end
  if held(s, B.BUTTON_PLAY)  then my =  1 end
  if held(s, B.BUTTON_LEFT)  then mx = -1 end
  if held(s, B.BUTTON_RIGHT) then mx =  1 end

  player.x = clamp(player.x + mx * player.speed, MIN_X, MAX_X)
  player.y = clamp(player.y + my * player.speed, MIN_Y, MAX_Y)

  if player.hurt_timer > 0 then player.hurt_timer = player.hurt_timer - 1 end
  if player.fire_timer > 0 then player.fire_timer = player.fire_timer - 1 end

  local moving = (mx ~= 0 or my ~= 0)
  if player.fire_timer == 0 and (SHOOT_WHILE_MOVING or not moving) then
    local target = nearest_enemy()
    if target then
      player_shoot(target)
      player.fire_timer = player.fire_delay
    end
  end
end

local function update_enemies()
  for _, e in ipairs(enemies) do
    local vx, vy = aim(e.x, e.y, player.x, player.y, e.speed)
    if e.kind == "spitter" then
      -- spitters like to keep some distance
      local dx, dy = div(player.x - e.x, FP), div(player.y - e.y, FP)
      if dx * dx + dy * dy < 50 * 50 then vx, vy = -vx, -vy end
    end
    e.x = clamp(e.x + vx, MIN_X, MAX_X)
    e.y = clamp(e.y + vy, MIN_Y, MAX_Y)

    e.cool = e.cool - 1
    if e.cool <= 0 then
      if e.kind == "spitter" then
        local bx, by = aim(e.x, e.y, player.x, player.y, 32)
        ebullets[#ebullets + 1] = { x = e.x, y = e.y, vx = bx, vy = by }
        e.cool = 50
      elseif e.kind == "boss" then
        for _, d in ipairs(RING) do
          ebullets[#ebullets + 1] = { x = e.x, y = e.y, vx = d[1] * 2, vy = d[2] * 2 }
        end
        e.cool = 60
      else
        e.cool = 1000 -- grunts don't shoot
      end
    end

    if touching(e.x, e.y, e.size, player.x, player.y, player.size) then
      hurt_player(e.kind == "boss" and 2 or 1)
    end
  end
end

local function outside(b)
  return b.x < 0 or b.x > W * FP or b.y < HUD * FP or b.y > H * FP
end

local function update_bullets()
  -- player bullets (go backwards through the list so removing is safe)
  for i = #bullets, 1, -1 do
    local b = bullets[i]
    b.x, b.y = b.x + b.vx, b.y + b.vy
    local hit = false
    for j = #enemies, 1, -1 do
      local e = enemies[j]
      if touching(b.x, b.y, 2, e.x, e.y, e.size) then
        e.hp = e.hp - player.damage
        if e.hp <= 0 then table.remove(enemies, j) end
        hit = true
        break
      end
    end
    if hit or outside(b) then table.remove(bullets, i) end
  end

  -- enemy bullets
  for i = #ebullets, 1, -1 do
    local b = ebullets[i]
    b.x, b.y = b.x + b.vx, b.y + b.vy
    if touching(b.x, b.y, 3, player.x, player.y, player.size) then
      hurt_player(1)
      table.remove(ebullets, i)
    elseif outside(b) then
      table.remove(ebullets, i)
    end
  end
end

---------------------------------------------------------------------
-- DRAWING
---------------------------------------------------------------------
local function draw_thing(x, y, size, c)
  color(c)
  box(div(x, FP) - div(size, 2), div(y, FP) - div(size, 2), size, size)
end

local function draw_hud()
  color(COL_HP_BACK)
  box(2, 2, 60, 7)
  color(COL_HP)
  box(2, 2, div(60 * math.max(player.hp, 0), player.max_hp), 7)
  color(COL_TEXT)
  rb.lcd_putsxy(68, 1, "Room " .. room)
end

local function draw_game()
  rb.lcd_set_background(COL_BG)
  rb.lcd_clear_display()

  -- floor and walls
  color(COL_WALL)
  box(0, HUD, W, H - HUD)
  color(COL_FLOOR)
  box(2, HUD + 2, W - 4, H - HUD - 4)

  -- enemies
  for _, e in ipairs(enemies) do
    local c = COL_GRUNT
    if e.kind == "spitter" then c = COL_SPITTER elseif e.kind == "boss" then c = COL_BOSS end
    draw_thing(e.x, e.y, e.size, c)
    -- little eyes
    color(COL_EYE)
    local ex, ey = div(e.x, FP), div(e.y, FP)
    box(ex - 2, ey - 2, 1, 2)
    box(ex + 1, ey - 2, 1, 2)
  end

  -- player (blinks after getting hurt)
  if player.hurt_timer % 4 < 2 then
    draw_thing(player.x, player.y, player.size, COL_PLAYER)
    color(COL_EYE)
    local px, py = div(player.x, FP), div(player.y, FP)
    box(px - 2, py - 2, 1, 2)
    box(px + 1, py - 2, 1, 2)
  end

  -- bullets
  for _, b in ipairs(bullets)  do draw_thing(b.x, b.y, 2, COL_BULLET) end
  for _, b in ipairs(ebullets) do draw_thing(b.x, b.y, 3, COL_EBULLET) end

  -- boss health bar along the bottom
  for _, e in ipairs(enemies) do
    if e.kind == "boss" then
      color(COL_HP_BACK)
      box(10, H - 6, W - 20, 3)
      color(COL_BOSS)
      box(10, H - 6, div((W - 20) * e.hp, e.max_hp), 3)
    end
  end

  rb.lcd_set_background(COL_BG)
  draw_hud()
end

local function draw_title()
  rb.lcd_set_background(COL_BG)
  rb.lcd_clear_display()
  color(COL_PLAYER)
  text_center(20, "POCKET SLAYER")
  color(COL_TEXT)
  text_center(50, "Center: start")
  text_center(66, "Menu: quit")
  color(COL_GRUNT)
  box(div(W, 2) - 30, 95, 8, 8)
  color(COL_PLAYER)
  box(div(W, 2) - 4, 95, 8, 8)
  color(COL_SPITTER)
  box(div(W, 2) + 22, 95, 8, 8)
end

local function draw_pause()
  draw_game()
  color(COL_BG)
  box(20, 40, W - 40, 50)
  color(COL_TEXT)
  text_center(48, "PAUSED")
  text_center(64, "Center: resume")
  text_center(76, "Menu: quit")
end

local function draw_upgrade()
  rb.lcd_set_background(COL_BG)
  rb.lcd_clear_display()
  color(COL_TEXT)
  text_center(4, "ROOM " .. room .. " CLEAR!")
  for i, u in ipairs(choices) do
    local y = 24 + (i - 1) * 32
    if i == choice_index then
      color(COL_SELECT)
      rb.lcd_drawrect(6, y - 2, W - 12, 30)
    else
      color(COL_TEXT)
    end
    rb.lcd_putsxy(12, y, u.name)
    rb.lcd_putsxy(12, y + 13, u.desc)
  end
end

local function draw_dead()
  rb.lcd_set_background(COL_BG)
  rb.lcd_clear_display()
  color(COL_HP)
  text_center(30, "YOU DIED")
  color(COL_TEXT)
  text_center(55, "Reached room " .. room)
  text_center(80, "Center: try again")
  text_center(96, "Menu: quit")
end

---------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------
local function main()
  if B == nil then
    rb.splash(rb.HZ * 3, "Can't find button codes")
    return
  end
  math.randomseed(rb.current_tick())
  if rb.backlight_force_on then rb.backlight_force_on() end

  state = "title"
  frame = 0
  local ticks_per_frame = math.max(1, div(rb.HZ, FPS))
  local running = true

  while running do
    local frame_start = rb.current_tick()
    local presses = read_presses()
    frame = frame + 1

    if state == "title" then
      if pressed(presses, B.BUTTON_SELECT) then new_game()
      elseif pressed(presses, B.BUTTON_MENU) then running = false end
      draw_title()

    elseif state == "play" then
      if pressed(presses, B.BUTTON_SELECT) then
        state = "pause"
      else
        update_player()
        update_enemies()
        update_bullets()
        if state == "play" and #enemies == 0 then
          pick_upgrades()
          state = "upgrade"
        end
      end
      draw_game()

    elseif state == "pause" then
      if pressed(presses, B.BUTTON_SELECT) then state = "play"
      elseif pressed(presses, B.BUTTON_MENU) then running = false end
      draw_pause()

    elseif state == "upgrade" then
      for _, p in ipairs(presses) do
        if p == B.BUTTON_SCROLL_FWD or p == B.BUTTON_PLAY then
          choice_index = choice_index % 3 + 1
        elseif p == B.BUTTON_SCROLL_BACK or p == B.BUTTON_MENU then
          choice_index = (choice_index + 1) % 3 + 1
        end
      end
      if pressed(presses, B.BUTTON_SELECT) then
        choices[choice_index].apply(player)
        room = room + 1
        start_room()
      end
      draw_upgrade()

    elseif state == "dead" then
      if pressed(presses, B.BUTTON_SELECT) then new_game()
      elseif pressed(presses, B.BUTTON_MENU) then running = false end
      draw_dead()
    end

    rb.lcd_update()

    -- wait so the game runs at the same speed every frame
    local used = rb.current_tick() - frame_start
    if used < ticks_per_frame then rb.sleep(ticks_per_frame - used) end
  end

  if rb.backlight_use_settings then rb.backlight_use_settings() end
end

main()
