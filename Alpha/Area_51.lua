local W,H = 5000,5000
local ASbmp = reaper.JS_LICE_CreateBitmap( true, W, H )
--local ASbmpDC = reaper.JS_LICE_GetDC(ASbmp)
local combineBmp = reaper.JS_LICE_CreateBitmap( true, W, H )
--local combineBmpDC = reaper.JS_LICE_GetDC(combineBmp )
local main_wnd = reaper.GetMainHwnd() -- GET MAIN WINDOW
local mixer_wnd = reaper.JS_Window_Find("mixer", true) -- GET MIXEWR I GUESS
local track_window = reaper.JS_Window_Find("trackview", true) -- GET TRACK VIEW
local track_window_dc = reaper.JS_GDI_GetWindowDC( track_window )
local last_proj_state,prev_HH,prev_lvl

local function get_track_zoom_offset(tr,y_end,h,scroll)
    local retval, list = reaper.JS_Window_ListAllChild(main_wnd)
    local fl,offset
    for adr in list:gmatch("%w+") do
      local handl = reaper.JS_Window_HandleFromAddress(tonumber(adr))
      if reaper.JS_Window_GetLongPtr(handl, "USER") == tr then 
        if mixer_wnd ~= reaper.JS_Window_GetParent(reaper.JS_Window_GetParent(handl)) then fl = handl break end
      end
    end
    if not fl then return end
    local __, __, ztop, __, __ = reaper.JS_Window_GetRect(fl)
    if y_end > (ztop + h - 1) then offset = y_end - ztop - h end
    return offset
end

local function get_track_y_range(y_view_start,scroll,cur_tr)
  if not cur_tr then return end
  local trcount = reaper.GetMediaTrackInfo_Value( cur_tr, "IP_TRACKNUMBER" ) -- WE ONLY COUNT TO CURRENT SELECTED TRACK (SINCE WE ONLY NEED Y-POS OF THAT TRACK)
  local masvis, totalh, idx = reaper.GetMasterTrackVisibility(), y_view_start - scroll, 1 -- VIEWS Y START, SUBTRACTED BY SCROLL POSITION
  if masvis == 1 then totalh = totalh+ 5; idx = 0 end 
  local y_start,y_end,height,offset
  for tr = idx, trcount do
    local track = reaper.CSurf_TrackFromID(tr, false)
    height = reaper.GetMediaTrackInfo_Value(track, "I_WNDH") -- TRACK HEIGHT    
    y_start = totalh  -- TRACK Y START
    y_end = totalh + height -- TRACK Y END -- EXCLUDE 1 PIXEL SO WE DONT USE TRACKS DEVIDER
    totalh = (totalh + height)
    if get_track_zoom_offset(  track,totalh,height,scroll) then
      offset = get_track_zoom_offset(track,totalh,height,scroll)
      totalh = totalh - get_track_zoom_offset(track,totalh,height,scroll)
    end
  end
  return y_start,y_end -- RETURN SELECTED TRACKS Y START & END
end

local function to_pixel(val,zoom)
  local pixel = math.floor(val * zoom)
return pixel
end

local function get_mouse_y_pos_in_track(tr,xV,mX,mY,tYs,tYe)
  if not tr or not tYe then return end
  local tr_h = tYe - tYs
  if mX > xV and tYs and (mY >= tYs and mY <= tYe) then -- IF MOUSE IS IN THE TRACK
    local mouse_in = mY - tYs -- GET MOUSE Y IN TRACK(WE WANT NEW RANGE FROM 0 TO ITS HEIGHT
    if mouse_in < tr_h/2 then return true end -- IF MOUSE IS IN UPPER HALF OF THE TRACK RETURN TRUE
  end 
end

local function has_val(tab, val)
  for i = 1 , #tab do
    local in_table = tab[i]
    if in_table == val then return i end
  end
return false
end

local down,hold
local click_start,click_end
local first_tr,last_tr
area_tracks = {} -- TABLE FOR AS TRACKS
local function mouse_click(click,time,tr,grid)
  if click == 1 then down = true   
    if not hold then
      click_start = grid or time -- GET TIME WHEN MOUSE IS CLICKED
      hold = true
    end 
  end
  if down then
    if not has_val(area_tracks, tr) then area_tracks[#area_tracks+1]=tr  -- add track to table if does not exits
    else
    local last_num = has_val(area_tracks, tr) -- get last track
    if last_num < #area_tracks then table.remove(area_tracks,#area_tracks) end -- if last track is no longer in table remove it
    end
    click_end = grid or time -- GET TIME WHILE MOUSE IS DOWN
    
    if click == 0 then 
      down,hold = nil
    end
  end 
  
  if click_start ~= click_end then
    if click_end < click_start then -- IF START TIMES ARE IN OPPOSITE DIRECTION
      return click_end,click_start  -- RETURN REVERSE
    else
      return click_start,click_end  -- RETURN NORMAL
    end
  else
    area_tracks = {}
  end
  
end

local prev_start,prev_end,prev_scroll
local prev_Arr_start_time,prev_Arr_end_time = reaper.GetSet_ArrangeView2( 0, false,0,0)
local prev_proj_state = reaper.GetProjectStateChangeCount( 0 )

local function status(c_end,Arr_start_time,Arr_end_time)
  local proj_state = reaper.GetProjectStateChangeCount( 0 )
  if prev_Arr_start_time ~= Arr_start_time or prev_Arr_end_time ~= Arr_end_time  then
    prev_Arr_start_time,prev_Arr_end_time = Arr_start_time,Arr_end_time
    return true
  elseif prev_end ~= c_end then 
    prev_end = c_end 
    return true
  elseif prev_proj_state ~= proj_state then
    prev_proj_state = proj_state
    return true
  end 
end

local function area_coordinates(c_start,c_end,zoom_lvl,Arr_pixel,last_tr_y_end,tr_y_start,y_view_start,last_tr_y_start , tr_y_end)
  if not c_start then return end
  local xStart = to_pixel(c_start,zoom_lvl) -- convert time to pixel
  local xEnd  = to_pixel(c_end,zoom_lvl)
  
  local area_width = xEnd - xStart
  local area_y_start,area_height
  
  if last_tr_y_start >= tr_y_start then -- EXPAND TO BOTTOM
    area_height = last_tr_y_end - tr_y_start
    area_y_start = tr_y_start - y_view_start
  else
    area_height = tr_y_end - last_tr_y_start -- EXPANT AS TO TOP
    area_y_start = last_tr_y_start - y_view_start
  end
  
  W,H = area_width, area_height
      
  local area_x_start = xStart - Arr_pixel -- UPDATE X WHEN MOVING,SCROLLING,ZOOMING
  return area_width,area_height,area_x_start,area_y_start
end

local function draw_area_selection(aX,aY,aW,aH)
  if not aW then return end
  reaper.JS_LICE_Clear(combineBmp, 0)
  reaper.JS_LICE_Blit(combineBmp, 0, 0, ASbmp, 0, 0, 5000, 5000, 1, "COPY" ) 
  reaper.JS_LICE_FillRect(combineBmp, aX,aY,aW,aH, 0xFF0000, 0.5, "COPY")
  reaper.JS_Window_InvalidateRect(track_window, 0, 0, W, H, true)
  
  -- OLD API CODE
  --reaper.JS_LICE_Blit(combineBmp, 0, 0, ASbmp, 0, 0, 5000, 5000, 1, "COPY")
  --reaper.JS_LICE_FillRect(combineBmp, aX,aY,W,H, 0xFF0000, 0.5, "COPY")
  --reaper.JS_GDI_Blit(track_window_dc, 0, 0, combineBmpDC, 0, 0, 5000, 5000 )
end

local del = 0x2E
local function keys()
  local OK, state = reaper.JS_VKeys_GetState()
  if state:byte(del) ~= 0 then
    return true
  end
end

local function split_item(item, time_s, time_e)
  if not item then return end
  local s_item_first = reaper.SplitMediaItem( item, time_e )
  local s_item_last = reaper.SplitMediaItem( item, time_s )
  if s_item_first and s_item_last then
    return s_item_last
  elseif s_item_last and not s_item_first then
    return s_item_last
  elseif s_item_first and not s_item_last then
    return item
  elseif not s_item_first and not s_item_last then
    -- return item -- BREAKS DELETING, NEED TO FIX IT (GETS MULTILPLE ITEMS)
  end
end

local function get_items_in_ts(item,s_start,s_end)
  local tsStart, tsEnd = s_start,s_end
  local item_start = reaper.GetMediaItemInfo_Value(item,"D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
  local item_dur = item_start + item_len
  if (tsStart >= item_start and tsStart <= item_dur) or -- if time selection start is in item
     (tsEnd >= item_start and tsEnd <= item_dur) or
     (tsStart <= item_start and tsEnd >= item_dur)then -- if time selection end is in the item
    return item
  end
end

local function count_items(a_tr)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems( a_tr ) do
    local item = reaper.GetTrackMediaItem( a_tr, i-1 )
    items[#items+1]= item
  end
  return items
end

local function job(key,c_start,c_end)
  for i = 1 , #area_tracks do
    local a_tr = area_tracks[i]
    local items = count_items(a_tr)
    for j = 1, #items do
      local item = items[j]
      if key == "del" then
        local as_item = get_items_in_ts(item,c_start,c_end) -- FIND IF THERE ARE ITEMS IN AREA SELECTION
        local s_item = split_item(as_item, c_start,c_end) -- SPLIT AND RETURN SPLIT ITEM
        if s_item then reaper.DeleteTrackMediaItem( a_tr, s_item ) end -- DELETE ITEM
      elseif key == "copy" then
      
      elseif key == "paste" then
      
      end
    end
  end
  reaper.UpdateArrange()  
end

local function main()
  local proj_state = reaper.GetProjectStateChangeCount( 0 ) 
  local closest_grid
  local window, segment, details = reaper.BR_GetMouseCursorContext()
  local tr = reaper.BR_GetMouseCursorContext_Track()
  local cur_m_x, cur_m_y = reaper.GetMousePosition()
  -------------------------------------------------------------------------------------------------------
  local zoom_lvl = reaper.GetHZoomLevel() -- HORIZONTAL ZOOM LEVEL
  local Arr_start_time, Arr_end_time = reaper.GetSet_ArrangeView2( 0, false,0,0) -- GET ARRANGE VIEW
  local Arr_pixel = to_pixel(Arr_start_time,zoom_lvl)-- ARRANGE VIEW POSITION CONVERT TO PIXELS
  local snap = reaper.GetToggleCommandState( 1157 )
  -------------------------------------------------------------------------------------------------------
  local m_click = reaper.JS_Mouse_GetState(0x0011) -- INTERCEPT MOUSE CLICK
  local mouse_time_pos = reaper.BR_PositionAtMouseCursor( false ) -- GET MOUSE POSITION (TIME)
  -------------------------------------------------------------------------------------------------------
  if snap == 1 then closest_grid = reaper.BR_GetClosestGridDivision( mouse_time_pos ) else closest_grid = nil end
  -------------------------------------------------------------------------------------------------------
  local _, scroll, _, _, _ = reaper.JS_Window_GetScrollInfo(track_window, "SB_VERT") -- GET VERTICAL SCROLL
  local _, x_view_start, y_view_start, _, y_view_end = reaper.JS_Window_GetRect(track_window) -- GET TRACK VIEW Y COORDINATES 
  ------------------------------------------------------------------------------------------------------- 
  local c_start,c_end = mouse_click(m_click,mouse_time_pos,tr,closest_grid) -- GET CLICKED TRACKS, MOUSE TIME RANGE
  -------------------------------------------------------------------------------------------------------
  local tr_y_start,tr_y_end = get_track_y_range(y_view_start,scroll,area_tracks[1])  -- GET CLICKED TRACK Y RANGE (FIRST_TRACK)
  local last_tr_y_start,last_tr_y_end = get_track_y_range(y_view_start,scroll,area_tracks[#area_tracks])  -- GET TRACK UNDER MOUSE Y RANGE (LAST_TRACK)
  -------------------------------------------------------------------------------------------------------
  local mouse_in = get_mouse_y_pos_in_track(area_tracks[1], x_view_start, cur_m_x, cur_m_y, tr_y_start, tr_y_end) -- CHECKS THE MOUSE POSITION IN THE TRA 
   ------------------ CURRENT HORRIBLE! WORKAROUND TO MAKE NORMAL BLITTING AND DRAWING
  
  draw = status(c_end,Arr_start_time,Arr_end_time) -- CHECK IF X,Y,ARRANGE VIEW ETC CHANGED IN PROJECT (WOULD BE USED FOR DRAWING ONLY WHEN THERE IS A CHANGE IN THE PROJECT)
   
  --if change then reaper.JS_GDI_Blit(ASbmpDC, 0, 0, track_window_dc, 0, 0, 5000, 5000) end -- BLIT HERE ONLY ON CHANGE
  local press = keys()
  
  local area_W,area_H,area_X,area_Y = area_coordinates(c_start, c_end, zoom_lvl, Arr_pixel, last_tr_y_end, tr_y_start ,y_view_start ,last_tr_y_start , tr_y_end)  
  
  if #area_tracks ~= 0 and draw then
    draw_area_selection(area_X,area_Y,area_W,area_H)
  end
  
  if press then job("del",c_start,c_end) end
  reaper.defer(main)
end

function exit()
    reaper.JS_Composite_Unlink(track_window, combineBmp)
    -- The extension will automatically unlink any destroyed bitmap,
    --    and will destroy any remaining bitmap when REAPER quits,
    --    so there shouldn't be memory leaks.
    reaper.JS_LICE_DestroyBitmap(ASbmp) 
    reaper.JS_LICE_DestroyBitmap(combineBmp)
    -- Re-paint to clear the window
    if reaper.ValidatePtr(track_window, "HWND") then 
        reaper.JS_Window_InvalidateRect(track_window, 0, 0, W, H, true) 
    end
end

reaper.atexit(exit)

local cOK = reaper.JS_Composite(track_window, 0, 0, W, H, combineBmp, 0, 0, W, H)
main()