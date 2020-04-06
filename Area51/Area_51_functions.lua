local refresh_tracks, update, update_all
--local AI_info

function Delete(tr, src_tr, data, t_start, t_dur, t_offset, job)
	if not data then return end
	split_or_delete_items(data, t_start, t_dur, job)
	del_env(tr, t_start, t_dur, 0)
	update_all = true
end

function Split(tr, src_tr, data, t_start, t_dur, t_offset, job)
	if not data then return end
	split_or_delete_items(data, t_start, t_dur, job)
	update_all = true
end

function Paste(tr, src_tr, data, t_start, t_dur, t_offset, job)
  if not data then return end
  local item_offset = t_offset
  local env_offset = t_offset - t_start
  local AI_offset = t_offset
  create_item(tr, data, t_start, t_dur, item_offset, job)
  paste_env(tr, src_tr, data, t_start, t_dur, env_offset, job)
  --Paste_AI(tr, src_tr, data, t_start ,AI_offset, job)
  refresh_tracks = true
end

function Duplicate(tr, src_tr, data, t_start, t_dur, t_offset, job)
  if not data then return end
  local item_offset = t_start + t_dur
  local env_offset = t_dur
  create_item(tr, data, t_start, t_dur, item_offset, job)
  paste_env(tr, src_tr, data, t_start, t_dur, env_offset, job)
  update = true
end
---------------------------------------------------------------
-------------------DRAGGING FUNCTIONS--------------------------
function Split_for_move(tr, src_tr, data, t_start, t_dur, t_offset, job)
  if not data then return end
  split_or_delete_items(data, t_start, t_dur, job)
  update_all = true
end

function Drag_Paste(tr, src_tr, data, t_start, t_dur, t_offset, job)
  -- WE DO NOT USE HERE "t_offset" SINCE WE ARE MOVING SINGLE AREA AND NOT IN COPY MODE, OFFSET INCLUDES DELTA BETWEEN AREAS COMBINED WITH MOUSE.P WHICH IS USED WHEN IN COPY MODE
  if not data then return end
  local org_start_time = t_start - mouse.dp  -- DRAGING ITEMS UPDATE TABLE VALUES, BUT ITEM FUNCTION BELOW IS LOOKING FOR ITEMS AT ORIGINAL LOCATION WE NEED TO SUBTRACT DRAG OFFSET WITH FINAL POSITION TO GET ORIGINAL
  local item_offset = t_start                 -- THIS IS FINAL UPDATED POSITION OF AREA WHERE ITEMS WILL PASTE
  local env_offset = mouse.dp
  create_item(tr, data, org_start_time, t_dur, item_offset, job)
  paste_env(tr, src_tr, data, org_start_time, t_dur, env_offset, job)
end

function Area_function(tbl,func)
  if not tbl then return end -- IF THERE IS NO TABLE OR TABLE HAS NO DATA RETURN
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    for a = 1, #tbl do
      local tbl_t = tbl[a]
      local area_pos_offset = 0

      area_pos_offset = area_pos_offset + (tbl_t.time_start - lowest_start()) --  OFFSET BETWEEN AREAS
      local total_pos_offset = mouse.p + area_pos_offset
      local tr_offset = copy and Mouse_tr_offset() or 0

      for i = 1, #tbl_t.sel_info do	-- LOOP THRU AREA DATA
        local sel_info_t = tbl_t.sel_info[i]
        local target_track = sel_info_t.track -- AREA TRACK
        ------------------------------------------------------------------------------------------------------------------------------------------------
        local new_tr, under = Track_from_offset(target_track, tr_offset)                                                                              --
        new_tr = under and Insert_track(under) or new_tr                                                                                              --
        local new_env_tr, mode = Env_Mouse_Match_Override_offset(tbl_t.sel_info, new_tr, i-1, tbl_t.sel_info[i].env_name)-- ENVELOPE COPY MODE OFFSET --  ONLY FOR COPY MODE
        local off_tr = mode and new_env_tr or new_tr -- OVERRIDE MODE IS ACTIVE ONLY ON SIGNLE ACTIVE AREAS OTHERWISE IT REVERTS TO MATCH MODE        --
        MODE = mode
        ------------------------------------------------------------------------------------------------------------------------------------------------
        off_tr = copy and off_tr or target_track -- OFFSET TRACK ONLY IF WE ARE IN COPY MODE

        if sel_info_t.items then	-- ITEMS
          _G[func](off_tr, target_track, sel_info_t.items, tbl_t.time_start, tbl_t.time_dur, total_pos_offset, func)
        elseif sel_info_t.env_name and not sel_info_t.AI then -- ENVELOPES
          _G[func](off_tr, target_track, sel_info_t.env_points, tbl_t.time_start, tbl_t.time_dur, total_pos_offset, func)
        elseif sel_info_t.env_name and sel_info_t.AI then -- ENVELOPES
          _G[func](off_tr, target_track, sel_info_t.AI, tbl_t.time_start, tbl_t.time_dur, total_pos_offset, func)
        end
      end

      if update then
        tbl_t.time_start = (func == "Duplicate") and tbl_t.time_start + tbl_t.time_dur or tbl_t.time_start
        tbl_t.sel_info = GetSelectionInfo(tbl_t)
        update = nil
      end

      if update_all then
        local areas_tbl = Get_area_table("Areas")
        Ghost_unlink_or_destroy(areas_tbl, "Delete")
        for i = 1, #areas_tbl do
          areas_tbl[i].sel_info = GetSelectionInfo(areas_tbl[i])
        end
        update_all = nil
      end

      if refresh_tracks then
        GetTracksXYH()
        refresh_tracks = false
      end

    end
    reaper.Undo_EndBlock("A51 " .. func, 4)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateTimeline()
    reaper.UpdateArrange()
end

function Drag_Paste_test(src_tbl, as_start, as_end, time_offset)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for i = 1, #src_tbl do
    local tr = src_tbl[i].track
      if src_tbl[i].items then
        create_item(tr, src_tbl[i].items, as_start, as_end, time_offset)
      elseif src_tbl[i].env_points then
        paste_env(tr, nil, src_tbl[i].env_points, as_start, as_end, time_offset)
      end
  end
  reaper.Undo_EndBlock("A51 " .. "DRAG_PASTE", 4)
  reaper.PreventUIRefresh(-1)
end

function Split_test(data, as_start, as_end, job)
  for i = 1, #data do
    local tr = data[i].track
    if data[i].items then
      split_or_delete_items(data[i].items, as_start, as_end, job)
    end
  end
end

local AI_info = {
  "D_POOL_ID",
  "D_POSITION",
  "D_LENGTH",
  "D_STARTOFFS",
  "D_PLAYRATE",
  "D_BASELINE",
  "D_AMPLITUDE",
  "D_LOOPSRC",
  "D_UISEL",
  "D_POOL_QNLEN"
}
--A = 0
function Paste_AI(tr, src_tr, data, t_start, t_offset, job)
  --AAA = data
  for i = 1, #data do
    --AAI_offset = data[i].info["D_POSITION"] - t_start
    local AI_offset = data[i].info["D_POSITION"] - t_start
    local Aidx = reaper.InsertAutomationItem( tr, -1, AI_offset + t_offset, data[i].info["D_LENGTH"])
    --local AI_pos = reaper.GetSetAutomationItemInfo(tr, i - 1, "D_POSITION", 0, false) -- AI POSITION
    --AAA = data[i].info
    for k,v in pairs(data[i].info) do
      if k ~= "D_POSITION" then
      reaper.GetSetAutomationItemInfo(tr, Aidx, k, v, true)
      end
    end
    --reaper.GetSetAutomationItemInfo(tr, Aidx, "D_POOL_ID", 10, true)
    A1, A2 = reaper.GetSetAutomationItemInfo_String(tr, Aidx, "P_POOL_NAME", "1", true )
    A3, A4 = reaper.GetSetAutomationItemInfo_String(tr, Aidx, "P_POOL_EXT", "", false )
    --reaper.GetSetAutomationItemInfo(tr, Aidx, "D_POOL_ID", 5, true)
    --reaper.GetSetAutomationItemInfo(tr, Aidx, "D_UISEL", 1, true)
    --reaper.Main_OnCommand(42084, 0)
    --reaper.GetSetAutomationItemInfo(tr, Aidx, "D_LOOPSRC", 0, true)
    --reaper.GetSetAutomationItemInfo(tr, Aidx, "D_STARTOFFS", 0, true)


    --for j = 1, #data[i].info do
      --A = A + 1
      --AAA = data[i].info[AI_info[j]]
     ---reaper.GetSetAutomationItemInfo(tr, i - 1, data[i].info[j], 0, true) -- AI POSITION
    --end

    --for j = 1, #data[i].points do
      --local ai_point = data[i].points[j]
       -- reaper.InsertEnvelopePointEx( tr, Aidx, ai_point.time + AI_pos + , ai_point.value, ai_point.shape, ai_point.tension, ai_point.selected, true )
    --end
    --reaper.Envelope_SortPointsEx( tr, i )
  end
end

function del_env(env_track, as_start, as_dur, offset)
  if reaper.ValidatePtr(env_track, "MediaTrack*") then return end
	local first_env = reaper.GetEnvelopePointByTime(env_track, as_start)
	local last_env = reaper.GetEnvelopePointByTime(env_track, as_start + as_dur) + 1

	local retval1, time1, value1, shape1, tension1, selected1 = reaper.GetEnvelopePoint(env_track, first_env)
	local retval2, time2, value2, shape2, tension2, selected2 = reaper.GetEnvelopePoint(env_track, last_env)

  reaper.DeleteEnvelopePointRange(env_track, as_start + offset, as_start + as_dur + offset)
	reaper.Envelope_SortPoints(env_track)
end

function split_or_delete_items(as_items_tbl, as_start, as_dur, job)
	if not reaper.ValidatePtr( as_items_tbl[1], "MediaItem*") then return end
	for i = #as_items_tbl, 1, -1 do
		local item = as_items_tbl[i]
		if job == "Delete" or job == "Split" or job == "Split_for_move" then
		local s_item_first = reaper.SplitMediaItem(item, as_start + as_dur)
		local s_item_last = reaper.SplitMediaItem(item, as_start)
		if job == "Delete" then
			if s_item_first and s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( s_item_last ), s_item_last)
			elseif s_item_last and not s_item_first then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( s_item_last ), s_item_last)
			elseif s_item_first and not s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( item ), item)
			elseif not s_item_first and not s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( item ), item)
			end
		end
		end
	end
end

function paste_env(tr, env_name, env_data, as_start, as_dur, time_offset, job)
  if reaper.ValidatePtr( env_data[1], "MediaItem*") then return end
  if tr and reaper.ValidatePtr(tr, "TrackEnvelope*") then -- IF TRACK HAS ENVELOPES PASTE THEM
    insert_edge_points(tr, as_start, as_dur, time_offset, job) -- INSERT EDGE POINTS AT CURRENT ENVELOE VALUE AND DELETE WHOLE RANGE INSIDE (DO NOT ALLOW MIXING ENVELOPE POINTS AND THAT WEIRD SHIT)
    del_env(tr, as_start, as_dur, time_offset)
    for i = 1, #env_data do
      local env = env_data[i]
      reaper.InsertEnvelopePoint(
        tr,
        env.time +  time_offset,
        env.value,
        env.shape,
        env.tension,
        env.selected,
        true
      )
    end
    reaper.Envelope_SortPoints(tr)
  elseif tr and reaper.ValidatePtr(tr, "MediaTrack*") and not MODE then
    get_set_envelope_chunk(tr, env_name, as_start, as_start + as_dur, time_offset)
  end
end

function create_item(tr, data, as_start, as_dur, time_offset, job)
  if not reaper.ValidatePtr( data[1], "MediaItem*") or tr == reaper.GetMasterTrack(0) then return end -- do not allow envelope data here, and do not allow pasting items on master track
  for i = 1, #data do
    local item = data[i]
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_lenght = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    local filename, clonedsource
    local take = reaper.GetMediaItemTake(item, 0)
    local item_volume = reaper.GetMediaItemInfo_Value(item, "D_VOL")
    local new_Item = reaper.AddMediaItemToTrack(tr)

    local chunk = Change_item_guids(item)
    reaper.SetItemStateChunk(new_Item, chunk, false)

    local new_item_start, new_item_lenght, offset = Offset_items_positions_and_start_offset(as_start, as_dur, item_start, item_lenght, time_offset)
    reaper.SetMediaItemInfo_Value(new_Item, "D_POSITION", new_item_start)
    reaper.SetMediaItemInfo_Value(new_Item, "D_LENGTH", new_item_lenght)
    reaper.SetMediaItemInfo_Value(new_Item, "D_VOL", item_volume)
  end
end

function Insert_track(under)
    for t = 1, under do
      reaper.InsertTrackAtIndex((reaper.GetNumTracks()), true)
    end -- IF THE TRACKS ARE BELOW LAST TRACK OF THE PROJECT CREATE HAT TRACKS
    local new_offset_tr = reaper.GetTrack(0, reaper.GetNumTracks() - 1)
    return new_offset_tr
end

function Move_items_envs(src_tbl, dst_tbl, src_t, dst_t, time_offset)
  reaper.Undo_BeginBlock()
  for i = 1, #dst_tbl do
    if dst_tbl[i].items then
      for j = 1, #dst_tbl[i].items do
        local as_track = dst_tbl[i].track
        local as_item = dst_tbl[i].items[j]
        local as_item_pos = reaper.GetMediaItemInfo_Value(as_item, "D_POSITION")
        reaper.SetMediaItemInfo_Value(as_item, "D_POSITION", as_item_pos + time_offset)
        reaper.MoveMediaItemToTrack(as_item, as_track)
      end
    end
  end
  for j = 1, #dst_tbl do
    if reaper.ValidatePtr(src_tbl[j].track, "TrackEnvelope*") and reaper.ValidatePtr(dst_tbl[j].track, "TrackEnvelope*") then
      insert_edge_points(dst_tbl[j].track, dst_t[1], dst_t[2], 0)
      reaper.DeleteEnvelopePointRange(src_tbl[j].track, src_t[1], src_t[1] + src_t[2])
      reaper.DeleteEnvelopePointRange(dst_tbl[j].track, dst_t[1], dst_t[1] + dst_t[2])
    end
  end
  for i = 1, #dst_tbl do
    if dst_tbl[i].env_points then
      local env_tr = dst_tbl[i].track
        for j = 1, #dst_tbl[i].env_points do
          local env = dst_tbl[i].env_points[j]
          env.time = env.time + time_offset
          reaper.InsertEnvelopePoint(
            env_tr,
            env.time,
            env.value,
            env.shape,
            env.tension,
            env.selected,
            true
          )
        end
      reaper.Envelope_SortPoints( dst_tbl[i].track )
    end
  end
  reaper.Undo_EndBlock("A51 MOVE", 4)
end

function New_items_position_in_area(as_start, as_end, item_start, item_lenght)
  local tsStart, tsEnd = as_start, as_end
  local item_dur = item_lenght + item_start

  if tsStart < item_start and tsEnd > item_start and tsEnd < item_dur then
    ----- IF TS START IS OUT OF ITEM BUT TS END IS IN THEN COPY ONLY PART FROM TS START TO ITEM END
    local new_start, new_item_lenght = item_start, tsEnd - item_start
    return new_start, new_item_lenght
  elseif tsStart < item_dur and tsStart > item_start and tsEnd > item_dur then
    ------ IF START IS IN ITEM AND TS END IS OUTSIDE ITEM COPY PART FROM TS START TO TS END
    local new_start, new_item_lenght = tsStart, item_dur - tsStart
    return new_start, new_item_lenght
  elseif tsStart >= item_start and tsEnd <= item_dur then
    ------ IF BOTH TS START AND TS END ARE IN ITEM
    local new_start, new_item_lenght = tsStart, tsEnd - tsStart
    return new_start, new_item_lenght
  elseif tsStart <= item_start and tsEnd >= item_dur then -- >= NEW
    ------ IF BOTH TS START AND END ARE OUTSIDE OF THE ITEM
    local new_start, new_item_lenght = item_start, item_lenght
    return new_start, new_item_lenght
  end
end

function Offset_items_positions_and_start_offset(as_start, as_dur, item_start, item_lenght, time_offset)
  local tsStart, tsEnd = as_start, as_start + as_dur
  local item_dur = item_lenght + item_start

  local new_start, new_item_lenght, offset
  if tsStart < item_start and tsEnd > item_start and tsEnd < item_dur then
    ----- IF TS START IS OUT OF ITEM BUT TS END IS IN THEN COPY ONLY PART FROM TS START TO ITEM END
    local new_start, new_item_lenght, offset = (item_start - tsStart) + time_offset, tsEnd - item_start, 0
    return new_start, new_item_lenght, offset
  elseif tsStart < item_dur and tsStart > item_start and tsEnd > item_dur then
    ------ IF START IS IN ITEM AND TS END IS OUTSIDE ITEM COPY PART FROM TS START TO TS END
    local new_start, new_item_lenght, offset = time_offset, item_dur - tsStart, (tsStart - item_start)
    return new_start, new_item_lenght, offset
  elseif tsStart >= item_start and tsEnd <= item_dur then
    ------ IF BOTH TS START AND TS END ARE IN ITEM
    local new_start, new_item_lenght, offset = time_offset, tsEnd - tsStart, (tsStart - item_start)
    return new_start, new_item_lenght, offset
  elseif tsStart <= item_start and tsEnd >= item_dur then -- >= NEW
    ------ IF BOTH TS START AND END ARE OUTSIDE OF THE ITEM
    local new_start, new_item_lenght, offset = (item_start - tsStart) + time_offset, item_lenght, 0
    return new_start, new_item_lenght, offset
  end
end

function env_prop(env)
  local br_env = reaper.BR_EnvAlloc(env, false)
  local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type_, faderScaling = reaper.BR_EnvGetProperties(br_env, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
  reaper.BR_EnvFree( env, true )
  return minValue, maxValue, centerValue
end

function insert_edge_points(env, as_start, as_dur, time_offset)
  if not reaper.ValidatePtr(env, "TrackEnvelope*") then return end -- DO NOT ALLOW MEDIA TRACK HERE
  local edge_pts = {}
  local as_end = as_start + as_dur
  local retval, value_st, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(env, as_start + time_offset, 0, 0) -- DESTINATION START POINT
  reaper.InsertEnvelopePoint(env, as_start + time_offset - 0.001, value_st, 0, 0, true, true)
  local retval, value_et, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(env, as_end + time_offset, 0, 0) -- DESTINATION END POINT
  reaper.InsertEnvelopePoint(env, as_end + time_offset + 0.001, value_et, 0, 0, true, true)
  reaper.Envelope_SortPoints( env )
end

function is_item_in_as(as_start, as_end, item_start, item_end)
  if (as_start >= item_start and as_start < item_end) and -- IF SELECTION START & END ARE "IN" OR "ON" ITEM (START AND END ARE IN ITEM OR START IS ON ITEM START,END IS ON ITEM END)
      (as_end <= item_end and as_end > item_start) or
      (as_start < item_start and as_end > item_end)
    then -- IF SELECTION START & END ARE OVER ITEM (SEL STARTS BEFORE ITEM END IS AFTER ITEM
      return true
    elseif (as_start >= item_start and as_start < item_end) and (as_end >= item_end) then -- IF SEL START IS IN THE ITEM
      return true
    elseif (as_end <= item_end and as_end > item_start) and (as_start <= item_start) then -- IF SEL END IS IN THE ITEM
      return true
    end
end

function get_items_in_as(as_tr, as_start, as_end, as_items)
  local as_items = {}

  for i = 1, reaper.CountTrackMediaItems(as_tr) do
    local item = reaper.GetTrackMediaItem(as_tr, i - 1)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_len
    if (as_start >= item_start and as_start < item_end) and -- IF SELECTION START & END ARE "IN" OR "ON" ITEM (START AND END ARE IN ITEM OR START IS ON ITEM START,END IS ON ITEM END)
      (as_end <= item_end and as_end > item_start) or
      (as_start < item_start and as_end > item_end)
    then -- IF SELECTION START & END ARE OVER ITEM (SEL STARTS BEFORE ITEM END IS AFTER ITEM
      as_items[#as_items + 1] = item
    elseif (as_start >= item_start and as_start < item_end) and (as_end >= item_end) then -- IF SEL START IS IN THE ITEM
      as_items[#as_items + 1] = item
    elseif (as_end <= item_end and as_end > item_start) and (as_start <= item_start) then -- IF SEL END IS IN THE ITEM
      as_items[#as_items + 1] = item
    end
  end

  return #as_items ~= 0 and as_items or nil
end

function get_as_tr_env_pts(as_tr, as_start, as_end)
  local retval, env_name = reaper.GetEnvelopeName(as_tr)
  local env_points = {}

  for i = 1, reaper.CountEnvelopePoints(as_tr) do
    local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(as_tr, i - 1)

    if time >= as_start and time <= as_end then
      reaper.SetEnvelopePoint(as_tr, i - 1, time, value, shape, tension, true, true) -- SELECT POINTS IN AREA

      env_points[#env_points + 1] = {
        id = i - 1,
        retval = retval,
        time = time,
        value = value,
        shape = shape,
        tension = tension,
        selected = true
      }
    elseif (time > as_start and time > as_end) or (time < as_start and time < as_end) then
      reaper.SetEnvelopePoint(as_tr, i - 1, time, value, shape, tension, false, true) -- DESELECT POINTS OUTSIDE AREA
    end
  end

  return #env_points ~= 0 and env_points or nil
end

function get_as_tr_AI(as_tr, as_start, as_end)
  local as_AI = {}
  if reaper.CountAutomationItems(as_tr) == 0 then return end
  for i = 1, reaper.CountAutomationItems(as_tr) do
    local AI_Points = {}

    local AI_pos = reaper.GetSetAutomationItemInfo(as_tr, i - 1, AI_info[2], 0, false) -- AI POSITION
    local AI_len = reaper.GetSetAutomationItemInfo(as_tr, i - 1, AI_info[3], 0, false) -- AI LENGHT

    if is_item_in_as(as_start, as_end, AI_pos, AI_pos + AI_len) then -- IF AI IS IN AREA
      --local new_AI_start, new_AI_len = New_items_position_in_area(as_start, as_end, AI_pos, AI_len) -- GET/TRIM AI START/LENGTH IF NEEDED (DEPENDING ON AI POSITION IN AREA)
      as_AI[#as_AI + 1] = {} -- MAKE NEW TABLE FOR AI
      as_AI[#as_AI].info = {}
      for j = 1, #AI_info do
        --if j == 2 then
        --  as_AI[#as_AI][AI_info[j]] = new_AI_start
        --elseif j == 3 then
        --  as_AI[#as_AI][AI_info[j]] = new_AI_len
        --else
        A1, A2 = reaper.GetSetAutomationItemInfo_String(as_tr, i - 1, "P_POOL_NAME", "", false )
        A3, A4 = reaper.GetSetAutomationItemInfo_String(as_tr, i - 1, "P_POOL_EXT:xyz", "", false )
        as_AI[#as_AI].info[AI_info[j]] = reaper.GetSetAutomationItemInfo(as_tr, i - 1, AI_info[j], 0, false) -- ADD AI INFO TO AI TABLE
       -- end
      end
      for j = 0, reaper.CountEnvelopePointsEx( as_tr, i-1) do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx( as_tr, i-1, j)
        if time >= as_start and time <= as_end then
            AI_Points[#AI_Points + 1] = {
              id = i - 1,
              retval = retval,
              time = time,
              value = value,
              shape = shape,
              tension = tension,
              selected = true
            }
        end
        as_AI[#as_AI].points = AI_Points
      end
    end
  end
  return #as_AI ~= 0 and as_AI or nil
end

-- SPLIT CHUNK TO LLINES
function split_by_line(str)
  local t = {}
  for line in string.gmatch(str, "[^\r\n]+") do
      t[#t + 1] = line
  end
  return t
end

-- REPLACE CHUNK
local function edit_chunk(str, org, new)
  local chunk = string.gsub(str, org, new)
  return chunk
end

-- COPY ENV PART OF THE CHUNK TO TRACK WE ARE PASTING INTO
function get_set_envelope_chunk(track, env, as_start, as_end, time_offset)
  if reaper.ValidatePtr(env, "MediaTrack*") then return end
  local ret, chunk = reaper.GetTrackStateChunk(track, "", false)
  local ret2, env_chunk = reaper.GetEnvelopeStateChunk(env, "")
  chunk = split_by_line(chunk)
  env_chunk = split_by_line(env_chunk)
  for i = 1, #env_chunk do
      if i < 8 then
          table.insert(chunk, #chunk, env_chunk[i]) -- INSERT FIRST 7 LINES INTO TRACK CHUNK (DEFAULT INFO WITH FIRST POINT)
      elseif i == #env_chunk then
          table.insert(chunk, #chunk, env_chunk[i])
      else
          local time, val, something, selected = env_chunk[i]:match("([%d%.]+)%s([%d%.]+)%s([%d%.]+)%s([%d%.]+)")
          if time then
              time = tonumber(time)
              if time >= as_start and time <= as_end then
                  local new_time = time + time_offset
                  env_chunk[i] = edit_chunk(env_chunk[i], time, new_time)
                  table.insert(chunk, #chunk, env_chunk[i])
              end
          end
      end
  end
  local new_chunk = table.concat(chunk, "\n")
  reaper.SetTrackStateChunk(track, new_chunk, true)
end

function Change_item_guids(item)
  local _, chunk = reaper.GetItemStateChunk(item, '', false)
  local take = reaper.GetMediaItemTake(item, 0)
  local item_is_MIDI = reaper.TakeIsMIDI(take)
  local chunk_lines = split_by_line(chunk)

  for j = 1, #chunk_lines do
    local line = chunk_lines[j]
    if string.match(line, 'IGUID {(%S+)}') then
      local new_guid = reaper.genGuid()
      chunk_lines[j] = 'IGUID ' .. new_guid
    elseif string.match(line, "GUID {(%S+)}") then
      local new_guid = reaper.genGuid()
      chunk_lines[j] = 'GUID ' .. new_guid
    end

    if item_is_MIDI then
      if string.match(line, "POOLEDEVTS {(%S+)}") then
        local new_guid = reaper.genGuid()
        chunk_lines[j] = 'POOLEDEVTS' .. new_guid
      end

      if line == 'TAKE' then
        for k = j+1, #chunk_lines do -- scan chunk ahead to modify take chunk
          local take_line = chunk_lines[k]

          if string.match( take_line, 'POOLEDEVTS' ) then
            local new_guid = reaper.genGuid()
            chunk_lines[k] = 'POOLEDEVTS ' .. new_guid
          elseif string.match( take_line , 'GUID' ) then
            local new_guid = reaper.genGuid()
            chunk_lines[k] = 'GUID ' .. new_guid
          end

          if take_line == '>' then
            j = k
            goto take_chunk_break
          end
        end

        ::take_chunk_break::
      end
    end
  end
  chunk = table.concat(chunk_lines, "\n")
  return chunk
end