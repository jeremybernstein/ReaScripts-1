function Remove()
  local tbl = Get_area_table("Areas")
  if copy then
     Copy_mode()
  end -- DISABLE COPY MODE
  Ghost_unlink_or_destroy(tbl, "Delete")
  RemoveAsFromTable(tbl, "Delete", "~=")
  BLOCK = nil
  Set_active_as(nil)
  Refresh_reaper()
end

function Copy_mode()
  local tbl = Get_area_table("Areas")
  copy = next(tbl) ~= nil and not copy
    if not copy then
      Ghost_unlink_or_destroy(tbl, "Unlink")
      Refresh_reaper()
    end
end

function Copy_Paste()
  if copy then 
    local tbl = Get_area_table()
    Area_function(tbl, "Paste")
  end
end

function Duplicate_area()
  local tbl = Get_area_table()
  Area_function(tbl, "Duplicate")
end

function Del()
  local tbl = Get_area_table()
  Area_function(tbl, "Delete")
end

function As_split()
  local tbl = Get_area_table()
  Area_function(tbl, "Splita")
end

function Select_as(num)
  local tbl = Get_area_table("Areas")
  local active_as = tbl[num] and tbl[num] or nil
  Ghost_unlink_or_destroy(tbl, "Unlink")
  Set_active_as(active_as)
  Refresh_reaper()
end

