local main_wnd = reaper.GetMainHwnd() -- GET MAIN WINDOW
local track_window = reaper.JS_Window_FindChildByID(main_wnd, 0x3E8) -- GET TRACK VIEW
local cur_path = package.cursor

local Element = {}

local ZONE_BUFFER
local split, drag_copy

function Color()
end

function DeepCopy(original)
  local copy = {}
  for k, v in pairs(original) do
    if type(v) == 'table' then
        v = DeepCopy(v)
    end
    copy[k] = v
  end
  return copy
end

function Element:new(x, y, w, h, guid, time_start, time_dur, info)
  local elm = {}
  elm.x, elm.y, elm.w, elm.h = x, y, w, h
  elm.guid, elm.bm = guid, reaper.JS_LICE_CreateBitmap(true, elm.w, elm.h)
  reaper.JS_LICE_Clear(elm.bm, 0x66002244)
  elm.info, elm.time_start, elm.time_dur = info, time_start, time_dur
  setmetatable(elm, self)
  self.__index = self
  return elm
end

function Extended(Child, Parent)
  setmetatable(Child, {__index = Parent})
end

function Element:update_zone(z)
  if copy then return end
  if mouse.l_down then
    if z[1] == "L" then
      local new_L = (Snap_val(z[2]) + mouse.dp) <= (z[3]+z[2]) and (Snap_val(z[2]) + mouse.dp) or Snap_val(z[3]+z[2])
      new_L = new_L >= 0 and new_L or 0
      local new_R = (z[3]+z[2]) - new_L >= 0 and (z[3]+z[2]) - new_L or 0
      self.time_start = new_L
      self.time_dur = new_R
    elseif z[1] == "R" then
      local new_R = Snap_val(z[3]+z[2]) + mouse.dp
      self.time_dur = new_R - self.time_start
      self.time_dur = self.time_dur >= 0 and self.time_dur or 0
    elseif z[1] == "C" then
        if (mouse.dp ~= 0 or mouse.tr ~= mouse.last_tr) and not drag_copy then
          if not split then Area_function({z[5]}, "Move") split = true end
        end
        local new_L = z[2] + mouse.dp >= 0 and z[2] + mouse.dp or 0
        self.time_start = new_L
        Track_offset(z[5].sel_info, self.sel_info)
        Env_offset(z[5].sel_info, self.sel_info)
        self.y, self.h = GetTrackTBH(self.sel_info)
        self:ghosts(self.time_start - z[2]) -- DRAW GHOSTS
    elseif z[1] == "T" then
      local rd = (mouse.last_r_t - mouse.ort)
      if (z[3] - rd) > 0 then
        local new_y, new_h = z[2] + rd, z[3] - rd
        self.y, self.h = new_y, new_h
      end
    elseif z[1] == "B" then
      local rd = (mouse.last_r_b - mouse.orb)
      if (z[3] + rd) > 0 then
        local new_h = z[3] + rd
        self.h = new_h
      end
    end
    self.x, self.w = Convert_time_to_pixel(self.time_start, self.time_dur)
    self:draw(1,1)
  elseif mouse.l_up then
    if z[1] == "C" then
      if not drag_copy then
        Move_items_envs(z[5].sel_info, self.sel_info, {z[2], z[3]}, {self.time_start,self.time_dur}, self.time_start - z[2])
      else
        Area_function({self}, "Drag_Paste")
      end
      Ghost_unlink_or_destroy({self}, "Unlink")
    end
    --create_undo(z, z[1])
    ZONE_BUFFER = nil
    split, drag_copy = nil, nil

    if self.time_dur == 0 then
      RemoveAsFromTable(Areas_TB, self.guid, "==")
    else
      self.sel_info = GetSelectionInfo(self)
    end
  end
end

function Element:update_xywh()
  self.x, self.w = Convert_time_to_pixel(self.time_start, self.time_dur) --Convert_time_to_pixel(self.time_start, self.time_start + self.time_dur)
  self.y, self.h = GetTrackTBH(self.sel_info)
  self:draw(1,1)
end

function Element:draw(w,h)
    reaper.JS_Composite(track_window, self.x, self.y, self.w, self.h, self.bm, 0, 0, w, h)
    Refresh_reaper()
end

function Element:copy()
    local mouse_delta = Mouse_tr_offset()
    local area_offset = self.time_start - lowest_start() --  OFFSET AREA SELECTIONS TO MOUSE POSITION
    local mouse_offset = (mouse.p - self.time_start) + area_offset
    for i = 1, #self.sel_info do
        local tr = self.sel_info[i].track
        local new_tr, under = Track_from_offset(tr, mouse_delta) --  ALWAYS FIRST CONVERT ALL TRACK TYPES TO MEDIA TRACK (WE USE IT AS MAIN ID TO KNOW THE POSITION OF ENVELOPES), AND RETURN HOW MANY TRACK IS NEW TRACK UNDER LAST PROJECT TRACK
        local _, new_tr_h = Get_tr_TBH(new_tr)
        local off_height = under and new_tr_h * under or 0 -- GET HEIGHT OFFSET POSITION (IF MOUSE IS UNDER LAST PROJECT TRACK - USED FOR COPY MOODE)
        local new_env_tr, mode = Env_Mouse_Match_Override_offset(self.sel_info, new_tr, i-1, self.sel_info[i].env_name)-- ENVELOPE COPY MODE OFFSET
        local off_tr = mode and new_env_tr or new_tr -- OVERRIDE MODE IS ACTIVE ONLY ON SIGNLE ACTIVE AREAS OTHERWISE IT REVERTS TO MATCH MODE
        if self.sel_info[i].ghosts then
          for j = 1, #self.sel_info[i].ghosts do
            local ghost = self.sel_info[i].ghosts[j]
            local ghost_start = mouse_offset and (mouse_offset + ghost.time_start) or ghost.time_start
            ghost.x, ghost.w = Convert_time_to_pixel(ghost_start, ghost.time_dur)
            ghost.y, ghost.h = Get_tr_TBH(off_tr)
            ghost.y = ghost.y + off_height
            ghost:draw(ghost.info[1], ghost.info[2]) -- STORED GHOST W AND H
            if mode == "OVERRIDE" and not Get_tr_TBH(new_env_tr) then reaper.JS_Composite_Unlink(track_window, ghost.bm) end -- IF IN OVERRIDE MODE REMOVE GHOSTS THAT HAVE NO TRACKS
          end
        end
    end
    DRAW_GHOSTS = false
end

function Element:ghosts(off_time, off_tr)
  for i = 1, #self.sel_info do
    if self.sel_info[i].ghosts then
      for j = 1, #self.sel_info[i].ghosts do
        local tr = off_tr and off_tr or self.sel_info[i].track
        local ghost = self.sel_info[i].ghosts[j]
        local ghost_start = off_time and (off_time + ghost.time_start) or ghost.time_start
        ghost.x, ghost.w = Convert_time_to_pixel(ghost_start,  ghost.time_dur)
        ghost.y, ghost.h = Get_tr_TBH(tr)
        ghost:draw(ghost.info[1], ghost.info[2]) -- STORED GHOST W AND H
      end
    end
  end
end

function Element:pointIN(sx, sy)
  local x, y = To_client(sx, sy)
  return x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h --then -- IF MOUSE IS IN ELEMENT
end

function Element:zoneIN(sx, sy)
  local x, y = To_client(sx, sy)
  local range2 = 8

  if x >= self.x and x <= self.x + range2 then
    if y >= self.y and y <= self.y + range2 then
      return {"TL"}
    elseif y <= self.y + self.h and y >= (self.y + self.h) - range2 then
      return {"BL"}
    end
    return {"L", self.time_start, self.time_dur}
  end

  if x >= (self.x + self.w - range2) and x <= self.x + self.w then
    if y >= self.y and y <= self.y + range2 then
      return {"TR"}
    elseif y <= self.y + self.h and y >= (self.y + self.h) - range2 then
      return {"BR"}
    end
    return {"R", self.time_start, self.time_dur}
  end

  if y >= self.y and y <= self.y + range2 then
    return {"T", self.y, self.h, self.time_start + self.time_dur}
  end
  if y <= self.y + self.h and y >= (self.y + self.h) - range2 then
    return {"B", self.y, self.h, self.time_start + self.time_dur}
  end

  if x > (self.x + range2) and x < (self.x + self.w - range2) then
    if y > self.y + range2 and y < (self.y + self.h) - range2 then
      return {"C", self.time_start, self.time_dur, self.y, DeepCopy(self)} --DeepCopy(self.sel_info)
    end
  end
end

function Element:mouseZONE()
  return self:zoneIN(mouse.ox, mouse.oy) -- mouse.ox, mouse.oy
end

function Element:mouseIN()
  return mouse.l_down == false and self:pointIN(mouse.x, mouse.y) --self:pointIN(mouse.x, mouse.y)
end
------------------------
function Element:mouseDown()
  return mouse.l_down and self:pointIN(mouse.ox, mouse.oy)
end
--------
function Element:mouseUp()
  return mouse.l_up --and self:pointIN(mouse.ox, mouse.oy)
end
--------
function Element:mouseClick()
  return mouse.l_click and self:pointIN(mouse.ox, mouse.oy)
end
------------------------
function Element:mouseR_Down()
  return mouse.r_down and self:pointIN(mouse.ox, mouse.oy)
end
--------
function Element:mouseM_Down()
  --return m_state&64==64 and self:pointIN(mouse_ox, mouse_oy)
end
--------

function Element:track()
  local active_as = Get_area_table("Active")
  if CREATING or WINDOW_IN_FRONT then
    return
  end
 -- if WINDOW_IN_FRONT then return end
  -- GET CLICKED AREA INFO GET ZONE
  if self:mouseClick() then
    ZONE_BUFFER = self:mouseZONE()
    ZONE_BUFFER.guid = self.guid
    if mouse.Ctrl() then drag_copy = true end
  end

  if copy then
    if active_as then
      if active_as.guid == self.guid then
        self:copy() -- draw only selected as ghost
      end
    else
      self:copy() -- draw every ghost
    end
  end
  -- UPDATE AREA ZONE
  if ZONE_BUFFER and ZONE_BUFFER.guid == self.guid then
    self:update_zone(ZONE_BUFFER)
  end

  BLOCK = (self:mouseIN() or ZONE_BUFFER) and true or nil  -- GLOBAL BLOCKING FLAG IF MOUSE IS OVER AREA (ALSO USED TO INTERCEPT LMB CLICK)
end

AreaSelection = {}
Ghosts = {}
Extended(AreaSelection, Element)
Extended(Ghosts, Element)

function Track(tbl)
  for _, area in pairs(tbl) do
    area:track()
  end
end

function Refresh_reaper()
  reaper.JS_Window_InvalidateRect(track_window, 0, 0, 5000, 5000, false)
end

function Draw(tbl)
  Track(tbl)
  local is_view_changed = Arrange_view_info()
  if is_view_changed and not DRAWING then--or (CHANGE and not DRAWING) then
    for i = #tbl, 1, -1 do
      tbl[i]:update_xywh()
    end -- UPDATE ALL AS ONLY ON CHANGE
  elseif DRAWING and #tbl ~= 0 then
    tbl[#tbl]:draw(1,1) -- UPDATE ONLY AS THAT IS DRAWING (LAST CREATED)
  end
end