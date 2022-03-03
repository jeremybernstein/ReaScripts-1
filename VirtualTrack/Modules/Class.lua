--[[
   * Author: SeXan
   * Licence: GPL v3
   * Version: 0.06
	 * NoIndex: true
--]]
local reaper = reaper
local gfx = gfx
local main_wnd = reaper.GetMainHwnd() -- GET MAIN WINDOW
local track_window = reaper.JS_Window_FindChildByID(main_wnd, 0x3E8)
local BUTTON_UPDATE
local mouse
local Element = {}

local menu_options = {
    [1] = { name = "",                      fname = "" },
    [2] = { name = "Create New Variant",    fname = "CreateNew" },
    [3] = { name = "Duplicate Variant",     fname = "Duplicate" },
    [4] = { name = "Delete Variant",        fname = "Delete" },
    [5] = { name = "Clear Variant",         fname = "Clear" },
    [6] = { name = "Rename Variants",       fname = "Rename" },
    [7] = { name = "Show All Variants",     fname = "ShowAll" }
}

function Get_class_tbl(tbl)
    return Element
end

local function ConcatMenuNames(track)
    local concat, fimp = "", ""
    local options = reaper.ValidatePtr(track, "MediaTrack*") and #menu_options or #menu_options-1
    if reaper.ValidatePtr(track, "MediaTrack*") then
        if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 2 then
            fimp = "!"
        end
    end
    for i = 1, options do
        concat = concat .. (i ~= 7 and menu_options[i].name or fimp .. menu_options[i].name) .. (i ~= options and "|" or "")
    end
    return concat
end

local function Update_tempo_map()
    if reaper.CountTempoTimeSigMarkers(0) then
        local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo = reaper.GetTempoTimeSigMarker(0, 0)
        reaper.SetTempoTimeSigMarker(0, 0, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo)
    end
    reaper.UpdateTimeline()
end

function Show_menu(tbl)
    reaper.PreventUIRefresh(1)
    local title = "supper_awesome_mega_menu"
    gfx.init( title, 0, 0, 0, 0, 0 )
    local hwnd = reaper.JS_Window_Find( title, true )
    if hwnd then
        reaper.JS_Window_Show( hwnd, "HIDE" )
    end
    gfx.x = gfx.mouse_x
    gfx.y = gfx.mouse_y

    local update_tempo = tbl.rprobj == reaper.GetMasterTrack(0) and true or false
    tbl = tbl.rprobj == reaper.GetMasterTrack(0) and Get_VT_TB()[reaper.GetTrackEnvelopeByName( tbl.rprobj, "Tempo map" )] or tbl

    local gray_out = ""
    if reaper.ValidatePtr(tbl.rprobj, "MediaTrack*") then
        if reaper.GetMediaTrackInfo_Value(tbl.rprobj, "I_FREEMODE") == 2 then
            gray_out = "#"
        end
    end

    local versions = {}
    for i = 1, #tbl.info do
        versions[#versions+1] = i == tbl.idx and gray_out .. "!" .. i .. " - ".. tbl.info[i].name or gray_out .. i .. " - " .. tbl.info[i].name
    end

    menu_options[1].name = ">" .. math.floor(tbl.idx) .. " Virtual TR : " .. tbl.info[tbl.idx].name .. "|" .. table.concat(versions, "|") .."|<|"

    local m_num = gfx.showmenu(ConcatMenuNames(tbl.rprobj))

    if m_num > #tbl.info then
        m_num = (m_num - #tbl.info) + 1
        _G[menu_options[m_num].fname](tbl.rprobj, tbl, tbl.idx)
    else
        if m_num ~= 0 then
            Set_Virtual_Track(tbl.rprobj, tbl, m_num)
        end
    end
    UPDATE_DRAW = true
    tbl:draw_text()
    gfx.quit()

    reaper.PreventUIRefresh(-1)
    if update_tempo then Update_tempo_map() end
    reaper.UpdateArrange()
end

function Element:new(rprobj, info, direct)
    local elm = {}
    elm.rprobj = rprobj
    elm.bm = reaper.JS_LICE_LoadPNG(image_path)
    elm.x, elm.y, elm.w, elm.h = 0, 0, reaper.JS_LICE_GetWidth(elm.bm), reaper.JS_LICE_GetHeight(elm.bm)
    elm.font_bm = reaper.JS_LICE_CreateBitmap(true, elm.w, elm.h)
    elm.font = reaper.JS_LICE_CreateFont()
    reaper.JS_LICE_SetFontColor(elm.font, 0xFFFFFFFF)
    reaper.JS_LICE_Clear(self.font_bm, 0x00000000)
    elm.info = info
    elm.idx = 1
    setmetatable(elm, self)
    self.__index = self
    if direct == 1 then -- unused
        self:cleanup()
    end
    return elm
end

function Element:cleanup()
    if self.bm then reaper.JS_LICE_DestroyBitmap(self.bm) end
    self.bm = nil
    if self.font_bm then reaper.JS_LICE_DestroyBitmap(self.font_bm) end
    self.font_bm = nil
    if self.font then reaper.JS_LICE_DestroyFont(self.font) end
    self.font = nil
end

function Element:update_xywh()
    local y, h = Get_TBH_Info(self.rprobj)
    self.y = math.floor(y + h/4)
    self:draw()
end

function Element:draw_text()
    reaper.JS_LICE_Clear(self.font_bm, 0x00000000)
    reaper.JS_LICE_Blit(self.font_bm, 0, 0, self.bm, 0, 0, self.w, self.h, 1, "ADD")
    reaper.JS_LICE_DrawText(self.font_bm, self.font, math.floor(self.idx), 2, self.w/4 + 2, 1, 80, 80)
end

function Element:draw()
    if Get_TBH_Info()[self.rprobj].vis then
        reaper.JS_Composite(track_window, self.x, self.y, self.w, self.h, self.font_bm, 0, 0, self.w, self.h, true)
    else
        reaper.JS_Composite_Unlink(track_window, self.font_bm, true)
    end
end

function Element:pointIN(sx, sy)
    local x, y = To_client(sx, sy)
    return x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h
end

function Element:mouseIN()
    return mouse.l_down == false and self:pointIN(mouse.x, mouse.y)
end

function Element:mouseDown()
    return mouse.l_down and self:pointIN(mouse.ox, mouse.oy)
end

function Element:mouseUp()
    return mouse.l_up --and self:pointIN(mouse.ox, mouse.oy)
end

function Element:mouseClick()
    return mouse.l_click and self:pointIN(mouse.ox, mouse.oy)
end

function Element:mouseR_Down()
    return mouse.r_down and self:pointIN(mouse.ox, mouse.oy)
end

function Element:mouseM_Down()
  --return m_state&64==64 and self:pointIN(mouse_ox, mouse_oy)
end

function Element:track()
    if not Get_TBH_Info()[self.rprobj].vis then return end
    if self:mouseClick() then
        Show_menu(self)
    end
end

local function Track(tbl)
    if Window_in_front() then return end
    for _, track in pairs(tbl) do track:track() end
end

local function Update_BTNS(tbl, update)
    if not update then return end
    for _, track in pairs(tbl) do
        if FIRST_START then track:draw_text() end
        track:update_xywh()
    end
end

local prev_Arr_end_time, prev_proj_state, last_scroll, last_scroll_b, last_pr_t, last_pr_h
local function Arrange_view_info()
    local TBH = Get_TBH_Info()
    if not TBH then return end
    local last_pr_tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
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

FIRST_START = true
function Draw(tbl)
    mouse = MouseInfo()
    mouse.tr, mouse.r_t, mouse.r_b = Get_track_under_mouse(mouse.x, mouse.y)
    Track(tbl)
    local reaper_arrange_updated = Arrange_view_info() or UPDATE_DRAW
    BUTTON_UPDATE = reaper_arrange_updated and true
    Update_BTNS(tbl, BUTTON_UPDATE)
    BUTTON_UPDATE = false
    UPDATE_DRAW = false
    FIRST_START = nil
end