local update
local refresh_tracks

function Delete(tr, data, t_start, t_end, t_offset, job, src_tr)
	if not data then return end
	split_or_delete_items(tr, data, t_start, t_end, job)
	del_env(tr, t_start, t_end, 0, job)
	update = true
end

function Split(tr, data, t_start, t_end, t_offset, job, src_tr)
	if not data then return end
	split_or_delete_items(tr, data, t_start, t_end, job)
	update = true
end

function Paste(tr, data, t_start, t_end, t_offset, job, src_tr)
  if not data then return end
  create_item(tr, data, t_start, t_end, t_offset)
  paste_env(tr, data, t_start, t_end, t_offset, job, src_tr)
end

function Duplicate(tr, data, t_start, t_end, t_offset, job, src_tr)
  if not data then return end
  create_item(tr, data, t_start, t_end, t_offset, job)
  paste_env(tr, data, t_start, t_end, t_offset, job, src_tr)
  update = true
end

function Area_function(tbl,func)
  if #tbl == 0 then return end
	reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
	for a = 1, #tbl do
		local tbl_t = tbl[a]
		local pos_offset = 0

		pos_offset = pos_offset + (tbl_t.time_start - lowest_start()) --  OFFSET AREA SELECTIONS TO MOUSE POSITION
    local tr_offset = copy and Mouse_tr_offset() or 0

		local as_start, as_end = tbl_t.time_start, tbl_t.time_start + tbl_t.time_dur

		for i = 1, #tbl_t.sel_info do	-- LOOP THRU AREA DATA
			local sel_info_t = tbl_t.sel_info[i]
			local target_track = sel_info_t.track -- AREA TRACK

      local new_tr, under = Track_from_offset(target_track, tr_offset)
      new_tr = under and Insert_track(under) or new_tr
      local new_env_tr, mode = Env_Mouse_Match_Override_offset(tbl_t.sel_info[1].track, new_tr, i-1, tbl_t.sel_info[i].env_name)-- ENVELOPE COPY MODE OFFSET
      local off_tr = mode and new_env_tr or new_tr -- OVERRIDE MODE IS ACTIVE ONLY ON SIGNLE ACTIVE AREAS OTHERWISE IT REVERTS TO MATCH MODE

      off_tr = copy and off_tr or target_track -- OFFSET TRACK ONLY IF WE ARE IN COPY MODE

      if sel_info_t.items then	-- ITEMS
				-- function name ( track, data table, time_start, time_end, time_offset, function name (as job))
				_G[func](off_tr, sel_info_t.items, as_start, as_end, pos_offset + mouse.p, func, target_track)
			elseif sel_info_t.env_name then -- ENVELOPES
        _G[func](off_tr, sel_info_t.env_points, as_start, as_end, pos_offset + mouse.p, func, target_track)
			end
		end

    if update then
      tbl_t.time_start = (func == "Duplicate") and tbl_t.time_start + tbl_t.time_dur or tbl_t.time_start
      tbl_t.sel_info = GetSelectionInfo(tbl_t)
			update = nil
    end
    if refresh_tracks then
      GetTracksXYH()
      refresh_tracks = false
    end

	end
  reaper.Undo_EndBlock("AREA51 " .. func, 4)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
end

function del_env(env_track, as_start, as_end, pos_offset, job)
  if reaper.ValidatePtr(env_track, "MediaTrack*") then return end
	local first_env = reaper.GetEnvelopePointByTime(env_track, as_start)
	local last_env = reaper.GetEnvelopePointByTime(env_track, as_end) + 1

	local retval1, time1, value1, shape1, tension1, selected1 = reaper.GetEnvelopePoint(env_track, first_env)
	local retval2, time2, value2, shape2, tension2, selected2 = reaper.GetEnvelopePoint(env_track, last_env)

	if value1 == 0 or value2 == 0 then
		reaper.DeleteEnvelopePointRange(env_track, as_start, as_end)
	else
		insert_edge_points(env_track, as_start, as_end, pos_offset, job)
	end
	reaper.Envelope_SortPoints(env_track)
end

function split_or_delete_items(as_tr, as_items_tbl, as_start, as_end, job)
	if not reaper.ValidatePtr( as_items_tbl[1], "MediaItem*") then return end
	for i = #as_items_tbl, 1, -1 do
		local item = as_items_tbl[i]
		if job == "Delete" or job == "Split" then
		local s_item_first = reaper.SplitMediaItem(item, as_end)
		local s_item_last = reaper.SplitMediaItem(item, as_start)
		if job == "Delete" then
			if s_item_first and s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( s_item_last ), s_item_last) --reaper.DeleteTrackMediaItem(as_tr, s_item_last)
			elseif s_item_last and not s_item_first then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( s_item_last ), s_item_last) -- reaper.DeleteTrackMediaItem(as_tr, s_item_last)
			elseif s_item_first and not s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( item ), item) -- reaper.DeleteTrackMediaItem(as_tr, item)
			elseif not s_item_first and not s_item_last then
				reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track( item ), item) -- reaper.DeleteTrackMediaItem(as_tr, item)
			end
		end
		end
	end
end

function paste_env(tr, env_data, as_start, as_end, mouse_offset, job, env_name) -- drag offset is not used, only as a flag for drag move here
  if reaper.ValidatePtr( env_data[1], "MediaItem*") then return end
  local env_paste_offset = job == "Duplicate" and as_end - as_start or mouse_offset - as_start -- OFFSET BETWEEN ENVELOPE START AND MOUSE POSITION
  if tr and reaper.ValidatePtr(tr, "TrackEnvelope*") then -- IF TRACK HAS ENVELOPES PASTE THEM
    insert_edge_points(tr, as_start, as_end, env_paste_offset) -- INSERT EDGE POINTS AT CURRENT ENVELOE VALUE AND DELETE WHOLE RANGE INSIDE (DO NOT ALLOW MIXING ENVELOPE POINTS AND THAT WEIRD SHIT)
    for i = 1, #env_data do
      local env = env_data[i]
      reaper.InsertEnvelopePoint(
        tr,
        env.time +  env_paste_offset,
        env.value,
        env.shape,
        env.tension,
        env.selected,
        true
      )
    end
    reaper.Envelope_SortPoints(tr)
  elseif tr and reaper.ValidatePtr(tr, "MediaTrack*") then
    get_set_envelope_chunk(tr, env_name, as_start, as_end, env_paste_offset)
    refresh_tracks = true
  end
end

function create_item(tr, data, as_start, as_end, mouse_time_pos, job)
  if not reaper.ValidatePtr( data[1], "MediaItem*") or tr == reaper.GetMasterTrack(0) then return end -- do not allow envelope data here, and do not allow pasting items on master track
  local time_offset = job == "Duplicate" and as_start + (as_end - as_start) or mouse_time_pos
  for i = 1, #data do
    local item = data[i]
    local filename, clonedsource
    local take = reaper.GetMediaItemTake(item, 0)
    local source = reaper.GetMediaItemTake_Source(take)
    local m_type = reaper.GetMediaSourceType(source, "")
    local item_volume = reaper.GetMediaItemInfo_Value(item, "D_VOL")
    local new_Item = reaper.AddMediaItemToTrack(tr)
    local new_Take = reaper.AddTakeToMediaItem(new_Item)

    if m_type:find("MIDI") then -- MIDI COPIES GET INTO SAME POOL IF JUST SETTING CHUNK SO WE NEED TO SET NEW POOL ID TO NEW COPY
      local _, chunk = reaper.GetItemStateChunk(item, "")
      local pool_guid = string.match(chunk, "POOLEDEVTS {(%S+)}"):gsub("%-", "%%-")
      local new_pool_guid = reaper.genGuid():sub(2, -2) -- MIDI ITEM
      chunk = string.gsub(chunk, pool_guid, new_pool_guid)
      reaper.SetItemStateChunk(new_Item, chunk, false)
    else -- NORMAL TRACK ITEMS
      filename = reaper.GetMediaSourceFileName(source, "")
      clonedsource = reaper.PCM_Source_CreateFromFile(filename)
    end

    local new_item_start, new_item_lenght, offset = as_item_position(item, as_start, as_end, time_offset)
    reaper.SetMediaItemInfo_Value(new_Item, "D_POSITION", new_item_start)
    reaper.SetMediaItemInfo_Value(new_Item, "D_LENGTH", new_item_lenght)
    local newTakeOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    reaper.SetMediaItemTakeInfo_Value(new_Take, "D_STARTOFFS", newTakeOffset + offset)

    if m_type:find("MIDI") == nil then
      reaper.SetMediaItemTake_Source(new_Take, clonedsource)
    end

    reaper.SetMediaItemInfo_Value(new_Item, "D_VOL", item_volume)
  end
end

function Insert_track(under)
    for t = 1, under do
      reaper.InsertTrackAtIndex((reaper.GetNumTracks()), true)
    end -- IF THE TRACKS ARE BELOW LAST TRACK OF THE PROJECT CREATE HAT TRACKS
    local new_offset_tr = reaper.GetTrack(0, reaper.GetNumTracks() - 1)
    refresh_tracks = true
    return new_offset_tr
end

function move_items_envs(src_tbl, dst_tbl, src_t, dst_t, offset)
  reaper.Undo_BeginBlock()
  for i = 1, #dst_tbl do
    if dst_tbl[i].items then
      for j = 1, #dst_tbl[i].items do
        local as_track = dst_tbl[i].track
        local as_item = dst_tbl[i].items[j]
        local as_item_pos = reaper.GetMediaItemInfo_Value(as_item, "D_POSITION")
        reaper.SetMediaItemInfo_Value(as_item, "D_POSITION", as_item_pos + offset)
        reaper.MoveMediaItemToTrack(as_item, as_track)
      end
    end
  end
  for j = 1, #dst_tbl do
    if reaper.ValidatePtr(src_tbl[j].track, "TrackEnvelope*") and reaper.ValidatePtr(dst_tbl[j].track, "TrackEnvelope*") then
      reaper.DeleteEnvelopePointRange(src_tbl[j].track, src_t[1], src_t[1] + src_t[2])
      reaper.DeleteEnvelopePointRange(dst_tbl[j].track, dst_t[1], dst_t[1] + dst_t[2])
    end
  end
  for i = 1, #dst_tbl do
    if dst_tbl[i].env_points then
      local env_tr = dst_tbl[i].track
        for j = 1, #dst_tbl[i].env_points do
          local env = dst_tbl[i].env_points[j]
          env.time = env.time + offset
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
  reaper.Undo_EndBlock("AREA51 MOVE", 4)
end

function get_item_time_in_area(item, as_start, as_end)
  local tsStart, tsEnd = as_start, as_end
  local item_lenght = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
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

function as_item_position(item, as_start, as_end, mouse_time_pos, job)
  local cur_pos = mouse_time_pos

  if job == "duplicate" then
    cur_pos = as_end
  end

  local tsStart, tsEnd = as_start, as_end
  local item_lenght = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_dur = item_lenght + item_start

  local new_start, new_item_lenght, offset
  if tsStart < item_start and tsEnd > item_start and tsEnd < item_dur then
    ----- IF TS START IS OUT OF ITEM BUT TS END IS IN THEN COPY ONLY PART FROM TS START TO ITEM END
    local new_start, new_item_lenght, offset = (item_start - tsStart) + cur_pos, tsEnd - item_start, 0
    return new_start, new_item_lenght, offset, item
  elseif tsStart < item_dur and tsStart > item_start and tsEnd > item_dur then
    ------ IF START IS IN ITEM AND TS END IS OUTSIDE ITEM COPY PART FROM TS START TO TS END
    local new_start, new_item_lenght, offset = cur_pos, item_dur - tsStart, (tsStart - item_start)
    return new_start, new_item_lenght, offset, item
  elseif tsStart >= item_start and tsEnd <= item_dur then
    ------ IF BOTH TS START AND TS END ARE IN ITEM
    local new_start, new_item_lenght, offset = cur_pos, tsEnd - tsStart, (tsStart - item_start)
    return new_start, new_item_lenght, offset, item
  elseif tsStart <= item_start and tsEnd >= item_dur then -- >= NEW
    ------ IF BOTH TS START AND END ARE OUTSIDE OF THE ITEM
    local new_start, new_item_lenght, offset = (item_start - tsStart) + cur_pos, item_lenght, 0
    return new_start, new_item_lenght, offset, item
  end
end

function env_prop(env)
  br_env = reaper.BR_EnvAlloc(env, false)
  local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling =
    reaper.BR_EnvGetProperties(br_env, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
end

--insert_edge_points(env_track, as_start, as_end, 0, nil, job)
function insert_edge_points(env, as_start, as_end, offset, job)
  if not reaper.ValidatePtr(env, "TrackEnvelope*") then
    return
  end -- DO NOT ALLOW MEDIA TRACK HERE
  local edge_pts = {}

  local retval, value_st, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(env, as_start + offset, 0, 0) -- DESTINATION START POINT
  reaper.InsertEnvelopePoint(env, as_start + offset - 0.001, value_st, 0, 0, true, true)
  local retval, value_et, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(env, as_end + offset, 0, 0) -- DESTINATION END POINT
  reaper.InsertEnvelopePoint(env, as_end + offset + 0.001, value_et, 0, 0, true, true)

  reaper.DeleteEnvelopePointRange(env, as_start + offset, as_end + offset)
  --[[
  if job == "Delete" then
    return
  end

  local retval, value_s, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(src_tr, as_start, 0, 0) -- SOURCE START POINT
  reaper.InsertEnvelopePoint(env, as_start + offset + 0.001, value_s, 0, 0, true, false)

  local retval, value_e, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(src_tr, as_end, 0, 0) -- SOURCE END POINT
  reaper.InsertEnvelopePoint(env, as_end + offset - 0.001, value_e, 0, 0, true, false)
  ]]
end

function get_items_in_as(as_tr, as_start, as_end, as_items)
  local as_items = {}

  for i = 1, reaper.CountTrackMediaItems(as_tr) do
    local item = reaper.GetTrackMediaItem(as_tr, i - 1)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_len

    if
      (as_start >= item_start and as_start < item_end) and (as_end <= item_end and as_end > item_start) or -- IF SELECTION START & END ARE "IN" OR "ON" ITEM (START AND END ARE IN ITEM OR START IS ON ITEM START,END IS ON ITEM END)
        (as_start < item_start and as_end > item_end)
     then -- IF SELECTION START & END ARE OVER ITEM (SEL STARTS BEFORE ITEM END IS AFTER ITEM
      as_items[#as_items + 1] = item
    elseif (as_start >= item_start and as_start < item_end) and (as_end >= item_end) then -- IF SEL START IS IN THE ITEM
      as_items[#as_items + 1] = item
    elseif (as_end <= item_end and as_end > item_start) and (as_start <= item_start) then -- IF SEL END IS IN THE ITEM
      as_items[#as_items + 1] = item
    end
  end

  if #as_items ~= 0 then
    return as_items
  end
end

function get_env(as_tr, as_start, as_end)
  local env_points = {}

  for i = 1, reaper.CountTrackEnvelopes(as_tr) do
    local tr = reaper.GetTrackEnvelope(as_tr, i - 1)

    for j = 1, reaper.CountEnvelopePoints(tr) do
      local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(tr, j - 1)

      if time >= as_start and time <= as_end then
        reaper.SetEnvelopePoint(tr, j - 1, _, _, _, _, true, _)

        env_points[#env_points + 1] = {
          id = j - 1,
          retval = retval,
          time = time,
          value = value,
          shape = shape,
          tension = tension,
          selected = true
        }
      end
    end
  end

  if #env_points ~= 0 then
    return env_points
  end
end

function get_as_tr_env_pts(as_tr, as_start, as_end)
  local retval, env_name = reaper.GetEnvelopeName(as_tr)
  local env_points = {}

  for i = 1, reaper.CountEnvelopePoints(as_tr) do
    local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(as_tr, i - 1)

    if time >= as_start and time <= as_end then
      reaper.SetEnvelopePoint(as_tr, i - 1, time, value, shape, tension, true, true)

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
      reaper.SetEnvelopePoint(as_tr, i - 1, time, value, shape, tension, false, true)
    end
  end

  if #env_points ~= 0 then
    return env_points
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
function get_as_tr_AI(as_tr, as_start, as_end)
  local as_AI = {}

  for i = 1, reaper.CountAutomationItems(as_tr) do
    local AI = reaper.GetSetAutomationItemInfo(as_tr, i - 1, AI_info[2], 0, false) -- GET AI POSITION

    if AI >= as_start and AI <= as_end then
      as_AI[#as_AI + 1] = {} -- MAKE NEW TABLE FOR AI

      for j = 1, #AI_info do
        as_AI[#as_AI][AI_info[j]] = reaper.GetSetAutomationItemInfo(as_tr, i - 1, AI_info[j], 0, false) -- ADD AI INFO TO AI TABLE
      end
    end
  end

  if #as_AI ~= 0 then
    return as_AI
  end
end

function validate_as_items(tbl)
  for i = 1, #tbl.items do
    if not reaper.ValidatePtr(tbl.items[i], "MediaItem*") then
      tbl.items[i] = nil
    end -- IF ITEM DOES NOT EXIST REMOVE IT FROM TABLE
  end

  if #tbl.items == 0 then
    tbl.items = nil
  end -- IF ITEM TABLE IS EMPTY REMOVE TABLE
end

function split_by_line(str)
  local t = {}
  for line in string.gmatch(str, "[^\r\n]+") do
      t[#t + 1] = line
  end
  return t
end

-- FOR CHUNK EDITING
local function edit_chunk(str, org, new)
  local chunk = string.gsub(str, org, new)
  return chunk
end

-- WHEN WE PASTE ENVELOPE TO TRACK THAT HAS NOT ANY, WE NEED TO PASTE THE CHUNK FROM PREVIOUS TRACK
-- GET PREVIOUS TRACK CHUNK 
-- EXTRACT ONLY DATA WE NEED (ENVELOPE POINTS IN AREA)
-- COPY ENV PART OF THE CHUNK TO TRACK WE ARE PASTING INTO
function get_set_envelope_chunk(track, env, as_start, as_end, mouse_offset)
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
                  local new_time = time + mouse_offset
                  env_chunk[i] = edit_chunk(env_chunk[i], time, new_time)
                  table.insert(chunk, #chunk, env_chunk[i])
              end
          end
      end
  end

  local new_chunk = table.concat(chunk, "\n")
  reaper.SetTrackStateChunk(track, new_chunk, true)
end