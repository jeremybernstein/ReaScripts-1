--[[
 * ReaScript Name: Virtual Tracks
 * Author: Sexan
 * Licence: GPL v3
 * REAPER: 6.0
 * Extensions: None
 * Version: 0.48
 * Provides: Modules/*.lua
--]]

--[[
 * Changelog:
 * v0.48 (2022-03-01)
   + Added new and efficient way to check track visibility (reaper bug is resolved with it)
   + Added few optimizations
   + Added proper check if window is in front of reaper (fixes clicking thru windows)
--]]

local reaper = reaper
package.path = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]] .. "?.lua;" -- GET DIRECTORY FOR REQUIRE

if not reaper.APIExists("JS_ReaScriptAPI_Version") then
  reaper.MB( "JS_ReaScriptAPI is required for this script", "Please download it from ReaPack", 0 )
  return reaper.defer(function() end)
 else
   local version = reaper.JS_ReaScriptAPI_Version()
   if version < 1.002 then
     reaper.MB( "Your JS_ReaScriptAPI version is " .. version .. "\nPlease update to latest version.", "Older version is installed", 0 )
     return reaper.defer(function() end)
   end
end

require("Modules/VTCommon")
require("Modules/Class")
require("Modules/Mouse")
require("Modules/Utils")

local function RunLoop()
    Create_VT_Element()
    Draw(Get_VT_TB())
    reaper.defer(RunLoop)
end

local function Main()
    xpcall(RunLoop, GetCrash())
end

function Exit()
    StoreInProject()
    local VT_TB = Get_VT_TB()
    for k, v in pairs(VT_TB) do
        reaper.JS_LICE_DestroyBitmap(v.bm)
    end
end

reaper.atexit(Exit)
Main()
