package.path = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]] .. "?.lua;" -- GET DIRECTORY FOR REQUIRE
package.cursor = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]] .. "Cursors\\" -- GET DIRECTORY FOR CURSORS

require("Area_51_class")      -- AREA FUNCTIONS SCRIPT
require("Area_51_ghosts")     -- AREA MOUSE INPUT HANDLING
require("Area_51_keyboard")      -- AREA KEYBOARD INPUT HANDLING
require("Area_51_mouse")      -- AREA MOUSE INPUT HANDLING
require("Area_51_functions")  -- AREA CLASS SCRIPT
require("Area_51_key_functions")  -- AREA CLASS SCRIPT

local main_wnd = reaper.GetMainHwnd() -- GET MAIN WINDOW
local track_window = reaper.JS_Window_FindChildByID(main_wnd, 0x3E8) -- GET TRACK VIEW
local last_proj_change_count = reaper.GetProjectStateChangeCount(0)
local WML_intercept = reaper.JS_WindowMessage_Intercept(track_window, "WM_LBUTTONDOWN", false) -- INTERCEPT MOUSE L BUTTON

local Areas_TB = {}
local active_as
copy = false

UNDO_BUFFER = {}

local crash = function(errObject)
   local byLine = "([^\r\n]*)\r?\n?"
   local trimPath = "[\\/]([^\\/]-:%d+:.+)$"
   local err = errObject and string.match(errObject, trimPath) or "Couldn't get error message."

   local trace = debug.traceback()
   local stack = {}
   for line in string.gmatch(trace, byLine) do
      local str = string.match(line, trimPath) or line
      stack[#stack + 1] = str
   end

   local name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)$")

   local ret =
      reaper.ShowMessageBox(
      name .. " has crashed!\n\n" .. "Would you like to have a crash report printed " .. "to the Reaper console?",
      "Oops",
      4
   )

   if ret == 6 then
      reaper.ShowConsoleMsg(
         "Error: " ..
            err ..
               "\n\n" ..
                  "Stack traceback:\n\t" ..
                     table.concat(stack, "\n\t", 2) ..
                        "\n\n" ..
                           "Reaper:       \t" .. reaper.GetAppVersion() .. "\n" .. "Platform:     \t" .. reaper.GetOS()
      )
   end
   Release_reaper_keys()
   reaper.JS_WindowMessage_Release(track_window, "WM_LBUTTONDOWN")
   --Exit()
end

function Msg(m)
   reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

local ceil, floor = math.ceil, math.floor
function Round(n)
   return n % 1 >= 0.5 and ceil(n) or floor(n)
end

function To_screen(x,y)
   local sx, sy = reaper.JS_Window_ClientToScreen( track_window, x, y )
   return sx, sy
end

function To_client(x,y)
   local cx, cy = reaper.JS_Window_ScreenToClient( track_window, x, y )
   return cx, cy
end

function Get_window_under_mouse()
   if mouse.l_down then
      local windowUnderMouse = reaper.JS_Window_FromPoint(mouse.x, mouse.y)
      local old_windowUnderMouse = reaper.JS_Window_FromPoint(mouse.ox, mouse.oy)
      if windowUnderMouse then
         if windowUnderMouse ~= track_window then
            return true
         elseif old_windowUnderMouse then
            if old_windowUnderMouse ~= track_window then
               return true
            end
         end
      end
   end
   return false
end

function Has_val(tab, val, guid)
   local val_n = guid and guid or val
   for i = 1, #tab do
      local in_table = guid and tab[i].guid or tab[i]
      if in_table == val_n then
         return tab[i]
      end
   end
end

-- FIND AREA WHICH HAS LOWEST TIME START
function lowest_start()
   local as_tbl = active_as and {active_as} or Areas_TB
   local min = as_tbl[1].time_start
   for i = 1, #as_tbl do
      if as_tbl[i].time_start < min then
         min = as_tbl[i].time_start
      end -- FIND LOWEST (FIRST) TIME SEL START
   end
   return min
end

function Get_folder_last_child(tr)
   if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") <= 0 then
     return
   end -- ignore tracks and last folder child
   local depth, last_child = 0
   local folderID = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
   for i = folderID + 1, reaper.CountTracks(0) - 1 do -- start from first track after folder
     local child = reaper.GetTrack(0, i)
     local currDepth = reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
     last_child = child
     depth = depth + currDepth
     if depth <= -1 then
       break
     end --until we are out of folder
   end
   return last_child -- if we only getting folder childs
 end

function Snap_val(val)
   return reaper.GetToggleCommandState(1157) == 1 and reaper.SnapToGrid(0, val) or val
end

function create_undo(tbl)
   UNDO_BUFFER[#UNDO_BUFFER+1] = tbl
end

function make_undo()
   if #UNDO_BUFFER ~= 0 then
      ALast_undo = UNDO_BUFFER[#UNDO_BUFFER]
      AArea = Has_val(Areas_TB, nil, ALast_undo.guid)
   end
end

local function Check_undo_history()
   local proj_change_count = reaper.GetProjectStateChangeCount(0)
   if proj_change_count > last_proj_change_count then
      local last_action = reaper.Undo_CanUndo2(0)
      if not last_action then
         return
      end
      last_action = last_action:lower()
      if last_action:find("A51") then
         make_undo()
      elseif last_action:find("remove tracks") then --or last_action:find("area51") then
         ValidateRemovedTracks()
      elseif
         last_action:find("toggle track volume/pan/mute envelopes") or
         last_action:find("track envelope active/visible/armed change")
       then
      -- TO DO
      -- CHECK ENVELOPES
      end
      last_proj_change_count = proj_change_count
   end
end

-- MAIN FUNCTION FOR FINDING TRACKS COORDINATES (RETURNS CLIENTS COORDINATES)
local TBH
function GetTracksXYH()
   TBH = {}
   -- ONLY ADD MASTER TRACK IF VISIBLE IN TCP
   local master_tr_visibility = reaper.GetMasterTrackVisibility()
   if master_tr_visibility == 1 or master_tr_visibility == 3 then
      local master_tr = reaper.GetMasterTrack(0)
      local m_tr_h = reaper.GetMediaTrackInfo_Value(master_tr, "I_TCPH")
      local m_tr_t = reaper.GetMediaTrackInfo_Value(master_tr, "I_TCPY")
      local m_tr_b = m_tr_t + m_tr_h
      TBH[master_tr] = {t = m_tr_t, b = m_tr_b, h = m_tr_h}
      for j = 1, reaper.CountTrackEnvelopes(master_tr) do
         local m_env = reaper.GetTrackEnvelope(master_tr, j - 1)
         local m_env_h = reaper.GetEnvelopeInfo_Value(m_env, "I_TCPH")
         local m_env_t = reaper.GetEnvelopeInfo_Value(m_env, "I_TCPY") + m_tr_t
         local m_env_b = m_env_t + m_env_h
         TBH[m_env] = {t = m_env_t, b = m_env_b, h = m_env_h}
      end
   end
   for i = 1, reaper.CountTracks(0) do
      local tr = reaper.GetTrack(0, i - 1)
      local tr_h = reaper.GetMediaTrackInfo_Value(tr, "I_TCPH")
      local tr_t = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY")
      local tr_b = tr_t + tr_h
      TBH[tr] = {t = tr_t, b = tr_b, h = tr_h}
      for j = 1, reaper.CountTrackEnvelopes(tr) do
         local env = reaper.GetTrackEnvelope(tr, j - 1)
         local env_h = reaper.GetEnvelopeInfo_Value(env, "I_TCPH")
         local env_t = reaper.GetEnvelopeInfo_Value(env, "I_TCPY") + tr_t
         local env_b = env_t + env_h
         TBH[env] = {t = env_t, b = env_b, h = env_h}
      end
   end
end

function Get_tr_TBH(tr)
   if TBH[tr] then
      return TBH[tr].t, TBH[tr].h
   end
end

function Set_active_as(act)
   active_as = act and act or nil
end

function Get_area_table(name)
   if name == "Areas" then return Areas_TB end
   if name == "Active" then return active_as end
   local tbl = active_as and {active_as} or Areas_TB
   return #tbl ~= 0 and tbl
end

-- FINDS TRACKS THAT ARE IN AREA OR MOUSE SWIPED RANGE
function GetTracksFromRange(y_t, y_b)
   local range_tracks = {}
   -- FIND TRACKS IN THAT RANGE
   for track, coords in pairs(TBH) do
      if coords.t >= y_t and coords.b <= y_b and coords.h ~= 0 then
         range_tracks[#range_tracks+1] = {track = track, v = coords.t}
      end
   end
   -- WE NEED TO SORT TRACKS FROM TOP TO BOTTOM BECAUSE PAIRS DOES NOT HAVE ORDER (TRACK 1 CAN BE AT 5th POSITION, TRACK 3 AT 1st POSITION ETC)
   table.sort(
      range_tracks,
      function(a, b)
         return a.v < b.v
      end
   )
   for i = 1, #range_tracks do
      range_tracks[i] = {track = range_tracks[i].track}
   end
   return range_tracks
end

-- FINDS TRACK THAT IS UNDER MOUSE AND RETURNS ITS POSITION AND VALUES
local function Get_track_under_mouse(x, y)
   local _, cy = To_client(x, y)
   local track, env_info = reaper.GetTrackFromPoint(x, y)
   if track == reaper.GetMasterTrack( 0 ) and reaper.GetMasterTrackVisibility() == 0 then return end -- IGNORE DOCKED MASTER TRACK
   if track and env_info == 0 then
      return track, TBH[track].t, TBH[track].b, TBH[track].h
     -- return track, TBH[track].t, TBH[Get_folder_last_child(track)].b -- reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
   elseif track and env_info == 1 then
      for i = 1, reaper.CountTrackEnvelopes(track) do
         local env = reaper.GetTrackEnvelope(track, i - 1)
         if TBH[env].t <= cy and TBH[env].b >= cy then
            return env, TBH[env].t, TBH[env].b, TBH[env].h
         end
      end
   end
end

function Get_zoom_and_arrange_start(x, w)
   local zoom_lvl = reaper.GetHZoomLevel() -- HORIZONTAL ZOOM LEVEL
   local Arr_start_time = reaper.GetSet_ArrangeView2(0, false, 0, 0) -- GET ARRANGE VIEW
   return zoom_lvl, Arr_start_time
end

-- GET PROJECT CHANGES, WE USE THIS TO PREVENT DRAW LOOPING AND REDUCE CPU USAGE
local prev_Arr_end_time, prev_proj_state, last_scroll, last_scroll_b, last_pr_t, last_pr_h
function Arrange_view_info()
   local last_pr_tr = Get_last_visible_track()
   local proj_state = reaper.GetProjectStateChangeCount(0) -- PROJECT STATE
   local _, scroll, _, _, scroll_b = reaper.JS_Window_GetScrollInfo(track_window, "SB_VERT") -- GET VERTICAL SCROLL
   local _, Arr_end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0) -- GET ARRANGE VIEW

   if prev_Arr_end_time ~= Arr_end_time then -- THIS ONE ALWAYS CHANGES WHEN ZOOMING IN OUT
      prev_Arr_end_time = Arr_end_time
      return true
   elseif prev_proj_state ~= proj_state then
      prev_proj_state = proj_state
      return true
   elseif last_scroll ~= scroll then
      last_scroll = scroll
      return true
   elseif last_scroll_b ~= scroll_b then
      last_scroll_b = scroll_b
      return true
   elseif last_pr_tr then -- LAST TRACK ALWAYS CHANGES HEIGHT WHEN OTHER TRACK RESIZE
      if TBH[last_pr_tr].h ~= last_pr_h or TBH[last_pr_tr].t ~= last_pr_t then
         last_pr_h = TBH[last_pr_tr].h
         last_pr_t = TBH[last_pr_tr].t
         return true
      end
   end
end

-- SINCE TRACKS CAN BE HIDDEN, LAST VISIBLE TRACK COULD BE ANY NOT NECESSARY TAST PROJECT TRACK
function Get_last_visible_track()
   if reaper.CountTracks(0) == 0 then
      return
   end
   local last_tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
   if not reaper.IsTrackVisible(last_tr, false) then
      for i = reaper.CountTracks(0), 1, -1 do
         local track = reaper.GetTrack(0, i - 1)
         if reaper.IsTrackVisible(track, false) then
            return track
         end
      end
   end
   return last_tr
end

-- TOTAL HEIGHT OF AREA SELECTION IS FIRST TRACK IN THE CURRENT AREA AND LAST TRACK IN THE CURRENT AREA (RANGE)
function GetTrackTBH(tbl)
   if not tbl then
      return
   end
   if TBH[tbl[1].track] and TBH[tbl[#tbl].track] then
      return TBH[tbl[1].track].t, TBH[tbl[#tbl].track].b - TBH[tbl[1].track].t
   end
end

-- CHECK IF VALUES ARE REVERSED AND RETURN THEM THAT WAY
local function Check_top_bot(top_start, top_end, bot_start, bot_end) -- CHECK IF VALUES GOT REVERSED
   if bot_end <= top_start then
      return bot_start, top_end
   else
      return top_start, bot_end
   end
end

-- CHECK IF VALUES ARE REVERSED AND RETURN THEM THAT WAY
local function Check_left_right(val1, val2) -- CHECK IF VALUES GOT REVERSED
   if val2 < val1 then
      return val2, val1
   else
      return val1, val2
   end
end

-- CHECK IF MOUSE IS MOVING IN X OR Y DIRRECTION (USING TO REDUCE CPU USAGE)
local prev_s_start, prev_s_end, prev_r_start, prev_r_end
local function Check_change(s_start, s_end, r_start, r_end)
   if s_start == s_end then
      return
   end
   if prev_s_end ~= s_end or prev_s_start ~= s_start then
      prev_s_start, prev_s_end = s_start, s_end
      return "TIME X"
   elseif prev_r_start ~= r_start or prev_r_end ~= r_end then
      prev_r_start, prev_r_end = r_start, r_end
      return "RANGE Y"
   end
end

-- DELETE AREA
function RemoveAsFromTable(tab, val, job)
   for i = #tab, 1, -1 do
      local in_table = tab[i].guid
      if job == "==" then
         if in_table == val then
            reaper.JS_LICE_DestroyBitmap(tab[i].bm) -- DESTROY BITMAPS FROM AS THAT WILL BE DELETED
            table.remove(tab, i) -- REMOVE AS FROM TABLE
         end
      elseif job == "~=" then
         if in_table ~= val then -- REMOVE ANY AS THAT HAS DIFFERENT GUID
            reaper.JS_LICE_DestroyBitmap(tab[i].bm) -- DESTROY BITMAPS FROM AS THAT WILL BE DELETED
            table.remove(tab, i) -- REMOVE AS FROM TABLE
         end
      end
   end
end

-- DELETE OR UNLINK GHOSTS
function Ghost_unlink_or_destroy(tbl, job)
   if not tbl then return end
   for a = 1, #tbl do
      for i = 1, #tbl[a].sel_info do
         if tbl[a].sel_info[i].ghosts then
            for j = 1, #tbl[a].sel_info[i].ghosts do
               local ghost = tbl[a].sel_info[i].ghosts[j]
               if job == "Delete" then
                  reaper.JS_LICE_DestroyBitmap(ghost.bm)
               elseif job == "Unlink" then
                  reaper.JS_Composite_Unlink(track_window, ghost.bm)
               end
            end
         end
      end
   end
   Refresh_reaper()
end

-- CREATE TABLE WITH ALL AREA INFORMATION NEEDED
local function CreateAreaTable(x, y, w, h, guid, time_start, time_end)
   if not Has_val(Areas_TB, nil, guid) then
      Areas_TB[#Areas_TB + 1] = AreaSelection:new(x, y, w, h, guid, time_start, time_end - time_start) -- CREATE NEW CLASS ONLY IF DOES NOT EXIST
   else
      Areas_TB[#Areas_TB].time_start = time_start
      Areas_TB[#Areas_TB].time_dur = time_end - time_start
      Areas_TB[#Areas_TB].x = x
      Areas_TB[#Areas_TB].y = y
      Areas_TB[#Areas_TB].w = w
      Areas_TB[#Areas_TB].h = h
   end
end

-- CONVERTS TIME TO PIXELS
function Convert_time_to_pixel(t_start, t_end)
   local zoom_lvl, Arr_start_time = Get_zoom_and_arrange_start()
   local x = Round((t_start - Arr_start_time) * zoom_lvl) -- convert time to pixel
   local w = Round(t_end * zoom_lvl) -- convert time to pixel
   return x, w
end

-- GET ITEMS, ENVELOPES, ENVELOPE POINTS, AI IF ANY EXIST
local function GetTrackData(tbl, as_start, as_end)
   for i = 1, #tbl do
      if reaper.ValidatePtr(tbl[i].track, "MediaTrack*") then
         tbl[i].items = get_items_in_as(tbl[i].track, as_start, as_end) -- TRACK MEDIA ITEMS
         tbl[i].ghosts = Get_item_ghosts(tbl[i].track, tbl[i].items, as_start, as_end)
      elseif reaper.ValidatePtr(tbl[i].track, "TrackEnvelope*") then
         local _, env_name = reaper.GetEnvelopeName(tbl[i].track)
         tbl[i].env_name = env_name -- ENVELOPE NAME
         tbl[i].env_points = get_as_tr_env_pts(tbl[i].track, as_start, as_end) -- ENVELOPE POINTS
         tbl[i].AIs = get_as_tr_AI(tbl[i].track, as_start, as_end) -- AUTOMATION ITEMS
         tbl[i].ghosts = Get_env_ghosts(tbl[i].track, tbl[i].env_points)
      end
   end
   return tbl
end

-- ALL DATA FROM THAT TRACKS (ITEMS,ENVELOPES,AIS)
function GetSelectionInfo(tbl)
   if not tbl then
      return
   end
   local area_top, area_bot, area_start, area_end = tbl.y, tbl.y + tbl.h, tbl.time_start, tbl.time_start + tbl.time_dur
   local tracks = GetTracksFromRange(area_top, area_bot) -- GET TRACK RANGE
   local data = GetTrackData(tracks, area_start, area_end) -- GATHER ALL INFO
   return data
end

function Change()
   local as_top, as_bot = Check_top_bot(mouse.ort, mouse.orb, mouse.last_r_t, mouse.last_r_b) -- RANGE ON MOUSE CLICK HOLD AND RANGE WHILE MOUSE HOLD
   local as_left, as_right = Check_left_right(mouse.op, mouse.p) -- CHECK IF START & END TIMES ARE REVERSED
   return Check_change(as_left, as_right, as_top, as_bot)
end

-- MAIN FUNCTION FOR CREATING AREAS FROM MOUSE MOVEMENT
local function CreateAreaFromSelection()
   if not ARRANGE and not CREATING then return end
   local as_top, as_bot = Check_top_bot(mouse.ort, mouse.orb, mouse.last_r_t, mouse.last_r_b) -- RANGE ON MOUSE CLICK HOLD AND RANGE WHILE MOUSE HOLD
   local as_left, as_right = Check_left_right(mouse.op, mouse.p) -- CHECK IF START & END TIMES ARE REVERSED
   DRAWING = CHANGE

   if mouse.l_down then
      if DRAWING then
         CREATING = true
         if not guid then
            guid = reaper.genGuid()--mouse.Ctrl_Shift_Alt() and reaper.genGuid() or "single"
         end

         local x, w = Convert_time_to_pixel(as_left, as_right - as_left)
         local y, h = as_top, as_bot - as_top
         CreateAreaTable(x, y, w, h, guid, as_left, as_right)
      end
   elseif mouse.l_up and CREATING then
      Areas_TB[#Areas_TB].sel_info = GetSelectionInfo(Areas_TB[#Areas_TB])
      table.sort(
         Areas_TB,
         function(a, b)
            return a.y < b.y
         end
      ) -- SORT AREA TABLE BY Y POSITION (LOWEST TO HIGHEST)
      CREATING, guid, DRAWING = nil, nil, nil
   end
end

-- IF TRACK IS DELETED FROM PROJECT REMOVE IT FROM AREAS TABLE
function ValidateRemovedTracks()
   if #Areas_TB == 0 then
      return
   end
   for i = #Areas_TB, 1, -1 do
      for j = #Areas_TB[i].sel_info, 1, -1 do
         if not reaper.ValidatePtr(Areas_TB[i].sel_info[j].track, "MediaTrack*") or reaper.ValidatePtr(Areas_TB[i].sel_info[j].track, "TrackEnvelope*") then
            for k = 1, #Areas_TB[i].sel_info[j].ghosts do
               local ghost = Areas_TB[i].sel_info[j].ghosts[k]
               reaper.JS_LICE_DestroyBitmap(ghost.bm)
            end
            table.remove(Areas_TB[i].sel_info, j)
            if #Areas_TB[i].sel_info == 0 then
               reaper.JS_LICE_DestroyBitmap(Areas_TB[i].bm)
               Refresh_reaper()
               table.remove(Areas_TB, i)
            end
         end
      end
   end
end

-- GET ENVELOPE ID
function GetEnvNum(env)
   if reaper.ValidatePtr(env, "MediaTrack*") then return end
   local par_tr = reaper.Envelope_GetParentTrack( env )
   for i = 1, reaper.CountTrackEnvelopes(par_tr) do
      local tr_env = reaper.GetTrackEnvelope(par_tr, i - 1)
      if tr_env == env then
         return i-1 -- MATCH MODE
      end
   end
end

-- GET MEDIA TRACK OR PARENT OF ENVELOPE
function Convert_to_track(tr)
   return reaper.ValidatePtr(tr, "TrackEnvelope*") and reaper.Envelope_GetParentTrack(tr) or tr
end

function Validate_tracks_type(tbl,tr_type)
   for i = 1, #tbl do
      if reaper.ValidatePtr(tbl[i].track, tr_type .. "*") then return true end
   end
   return false
end

-- ENVELOPE OFFSET FOR MOVE ZONE
function Env_offset(src_tbl, dest_tbl)
   local cur_m_tr = mouse.last_tr
   local first_m_tr = mouse.otr

   if reaper.ValidatePtr(first_m_tr, "MediaTrack*") then return end
   if Validate_tracks_type(src_tbl,"MediaTrack") then return end -- IF MEDIA TRACK IS IN THE SELECTION BREAK

   local f_env_par_tr = reaper.Envelope_GetParentTrack(first_m_tr)

   if reaper.ValidatePtr(cur_m_tr, "TrackEnvelope*") then
      local cur_m_tr_num = GetEnvNum(cur_m_tr)
      local first_m_tr_num = GetEnvNum(first_m_tr)

      local first_area_tr_num = GetEnvNum(src_tbl[1].track)
      local last_area_tr_num = GetEnvNum(src_tbl[#src_tbl].track)

      local mouse_delta = cur_m_tr_num - first_m_tr_num
      for i = #src_tbl, 1, -1 do
         local tr = src_tbl[i].track
         local tr_num = GetEnvNum(tr)
         local offset_num = tr_num + mouse_delta
         local new_env_tr = reaper.GetTrackEnvelope(f_env_par_tr, offset_num)
         if (mouse_delta + last_area_tr_num) < reaper.CountTrackEnvelopes(f_env_par_tr) and (mouse_delta + first_area_tr_num) >= 0 then
            dest_tbl[i].track = new_env_tr
         end
      end
   end

end

-- TRACK OFFSET FOR MOVE ZONE
function Track_offset(src_tbl, dest_tbl)
   local cur_m_tr = mouse.last_tr
   local first_m_tr = mouse.otr
   if reaper.ValidatePtr(first_m_tr, "TrackEnvelope*") then return end
   if Validate_tracks_type(src_tbl,"TrackEnvelope") then return end -- IF ENVELOPE TRACK IS IN THE SELECTION BREAK

   local cur_m_tr_num = reaper.CSurf_TrackToID(Convert_to_track(cur_m_tr), false)
   local first_m_tr_num = reaper.CSurf_TrackToID(Convert_to_track(first_m_tr), false)

   local mouse_delta = cur_m_tr_num - first_m_tr_num

   local last_project_tr = Get_last_visible_track()
   local last_project_tr_id = reaper.CSurf_TrackToID(last_project_tr, false)

   local last_area_tr = Convert_to_track(src_tbl[#src_tbl].track)
   local last_area_tr_num = reaper.CSurf_TrackToID(last_area_tr, false)

   local first_area_tr = Convert_to_track(src_tbl[1].track)
   local first_area_tr_num = reaper.CSurf_TrackToID(first_area_tr, false)

   for i = #src_tbl, 1, -1 do
      local tr = src_tbl[i].track
      local new_tr, under = Track_from_offset(tr, mouse_delta)
      --local tr_num = reaper.CSurf_TrackToID(tr, false)
      --local offset_num = tr_num + mouse_delta
      --local new_tr = reaper.CSurf_TrackFromID(offset_num, false)

      if (mouse_delta + first_area_tr_num) > 0 and (mouse_delta + last_area_tr_num) <= last_project_tr_id then
         dest_tbl[i].track = new_tr
      end
   end
end

-- CALCULATE MOUSE DELTA FOR MEDIA TRACKS OR ENVELOPE PARENTS
function Mouse_tr_offset()
   if not mouse.last_tr then return end
   local _, m_cy = To_client(0,mouse.y)
   local m_tr_num = reaper.CSurf_TrackToID(Convert_to_track(mouse.last_tr), false)

   local first_area_tr = active_as and active_as.sel_info[1].track or Areas_TB[1].sel_info[1].track -- GET FIRST AREA (ACTIVE SELECTED AREA OR FIRST AREA IF MULTI AREAS)
   local first_area_tr_num = reaper.CSurf_TrackToID(Convert_to_track(first_area_tr), false) --

   local mouse_delta = m_tr_num - first_area_tr_num
   mouse_delta = m_cy > TBH[Get_last_visible_track()].b and mouse_delta + 1 or mouse_delta   -- IF MOUSE IS BELLOW LAST TRACK ADD 1 (SO ALL TRACKS ARE BELLOW LAST TRACK)

   return mouse_delta
end

-- ENVELOPE TRACK OFFSET MATCH AND OVERRIDE MODE (COPY MODE)
function Env_Mouse_Match_Override_offset(src_tr_tbl, tr, num, env_name)
   local m_env = reaper.ValidatePtr(mouse.last_tr, "TrackEnvelope*") and mouse.last_tr or nil
   if m_env and (#Areas_TB == 1 or active_as) and not Validate_tracks_type(src_tr_tbl,"MediaTrack") then --not reaper.ValidatePtr(first_tr, "MediaTrack*") then -- OVERRIDE MODE ONLY IF THERE IS ONE AREA ACTIVE (CREATED OR SELECTED) AND NO MEDIA TRACK IS SELECTED
      local m_num = GetEnvNum(m_env)
      local mouse_delta = m_num + num
      local new_env_tr = reaper.GetTrackEnvelope(tr, mouse_delta)
      return new_env_tr, "OVERRIDE"
   else                                            -- MATCH MODE
      local par_tr = Convert_to_track(tr)
      for i = 1, reaper.CountTrackEnvelopes(par_tr) do
         local tr_env = reaper.GetTrackEnvelope(par_tr, i - 1)
         local _, tr_env_name = reaper.GetEnvelopeName(tr_env)
         if tr_env_name == env_name then
            return tr_env, "MATCH"
         end
      end
   end
end

-- RETURN FIRST VISIBLE TRACK
local function find_visible_tracks(cur_offset_id)
   if cur_offset_id == 0 then
      return 1
   end -- TO DO FIX
   for i = cur_offset_id, reaper.CountTracks(0) do
      local track = reaper.GetTrack(0, i - 1)
      if track and reaper.IsTrackVisible(track, false) then
         return i
      else
      end
   end
end

-- CONVERT OFFSET TO TRACK AND CALCULATE HOW MANY TRACKS IS THE NEW TRACK UNDER LAST PROJECT TRACK
function Track_from_offset(tr, offset)
   local tr_num = reaper.CSurf_TrackToID(Convert_to_track(tr), false)
   local last_vis_tr = Get_last_visible_track()
   local last_num = reaper.CSurf_TrackToID(last_vis_tr, false) 
   local under = tr_num + offset > last_num and (tr_num + offset) - last_num or nil
   local offset_tr = find_visible_tracks(tr_num + offset) or tr_num + offset -- FIND FIRST AVAILABLE VISIBLE TRACK IF HIDDEN
   local new_tr = under and last_vis_tr or reaper.CSurf_TrackFromID(offset_tr, false) --local new_tr = under and last_vis_tr or reaper.CSurf_TrackFromID(tr_num + offset, false)
   return new_tr, under
end

local function Main()
   xpcall(
      function()
         GetTracksXYH() -- GET XYH INFO OF ALL TRACKS
         Check_undo_history()

         mouse = MouseInfo()
         mouse.tr, mouse.r_t, mouse.r_b = Get_track_under_mouse(mouse.x, mouse.y)
         CHANGE = ARRANGE and Change() or false

         WINDOW_IN_FRONT = Get_window_under_mouse()
         Track_keys()
         Intercept_reaper_key(Areas_TB) -- WATCH TO INTERCEPT KEYS WHEN AREA IS DRAWN (ON SCREEN)
         Pass_thru()

         if not BLOCK then
            if mouse.Ctrl_Shift() or CREATING then --and mouse.Shift() then
               CreateAreaFromSelection()
            end
            if mouse.Ctrl_Shift() and not mouse.Ctrl_Shift_Alt() and mouse.l_click then -- REMOVE AREAS ON CLICK
              if #Areas_TB ~= 0 then
                  Remove()
              end
            end
         end -- CREATE AS IF IN ARRANGE WINDOW AND NON AS ZONES ARE CLICKED
         Draw(Areas_TB) -- DRAWING CLASS
         reaper.defer(Main)
      end,
      crash
   )
end

function Exit() -- DESTROY ALL BITMAPS ON REAPER EXIT
   Ghost_unlink_or_destroy(Areas_TB, "Delete")
   RemoveAsFromTable(Areas_TB, "Delete", "~=")
   if reaper.ValidatePtr(track_window, "HWND") then
      Refresh_reaper()
   end
   Release_reaper_keys()
   reaper.JS_WindowMessage_Release(track_window, "WM_LBUTTONDOWN")
end

reaper.atexit(Exit)
Main()
