-- Seeking the Soulstones
-- Map pins for the four soulstone fragments in the warlock green fire quest.
-- Uses only the public game API.

local ADDON_NAME, ns = ...

local PLUGIN_NAME   = "SeekingTheSoulstones"
local QUEST_ID      = 32317            -- Seeking the Soulstones
local ICON_ITEM_ID  = 92494            -- Hellfire Fragment (used for the pin icon)
local FALLBACK_ICON = 134400           -- question mark, in case the item icon isn't available
local OUTLAND_MAP   = 101

local parent = LibStub("AceAddon-3.0"):GetAddon("HandyNotes", true)
if not parent then return end

---------------------------------------------------------------------------
-- Node data
-- Coordinates are packed as XXXXYYYY (e.g. 61.91, 37.31 -> 61913731).
-- "objective" is the quest objective index the fragment fills, in the
-- order the quest lists them: Hellfire, Netherstorm, Blade's Edge, Shadowmoon.
---------------------------------------------------------------------------
local nodes = {
    [100] = { -- Hellfire Peninsula
        [61913731] = {
            objective = 1,
            label = "Hellfire Fragment",
            hint  = "Felspark Ravine, just east of Thrallmar among the imps and infernals. A small purple shard on the ground.",
        },
        [67045671] = {
            objective = 1,
            label = "Hellfire Fragment (alternate spot)",
            hint  = "Some players find it here instead, near the Legion Front. Check here if the first spot comes up empty.",
        },
    },
    [109] = { -- Netherstorm
        [53452103] = {
            objective = 2,
            label = "Netherstorm Fragment",
            hint  = "Ruins of Farahlon, near the tallest ruin with the demons.",
        },
    },
    [105] = { -- Blade's Edge Mountains
        [77543141] = {
            objective = 3,
            label = "Blade's Edge Fragment",
            hint  = "Vim'gol's Circle, tucked between the spires near the bridge to Netherstorm.",
        },
    },
    [104] = { -- Shadowmoon Valley (Outland)
        [42894491] = {
            objective = 4,
            label = "Shadowmoon Fragment",
            hint  = "Hand of Gul'dan, by the summoning circle with two white statues. Grab this one last - the next step is at the Black Temple.",
        },
    },
}

-- Flattened list so the Outland continent map can show every pin at once.
local allNodes = {}
for mapID, zone in pairs(nodes) do
    for coord, node in pairs(zone) do
        node.mapID = mapID
        node.coord = coord
        allNodes[#allNodes + 1] = node
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local defaults = {
    icon_scale     = 1.5,
    icon_alpha     = 1.0,
    warlock_only   = true,
    hide_collected = true,
    show_when_done = false,
    show_continent = true,
}

local db

local function Refresh()
    parent:SendMessage("HandyNotes_NotifyUpdate", PLUGIN_NAME)
end

---------------------------------------------------------------------------
-- Visibility rules
---------------------------------------------------------------------------
local isWarlock = select(2, UnitClass("player")) == "WARLOCK"

local function ObjectiveDone(index)
    if not C_QuestLog.IsOnQuest(QUEST_ID) then return false end
    local objectives = C_QuestLog.GetQuestObjectives(QUEST_ID)
    local obj = objectives and objectives[index]
    return obj and obj.finished or false
end

local function ShouldShow(node)
    if db.warlock_only and not isWarlock then return false end
    if C_QuestLog.IsQuestFlaggedCompleted(QUEST_ID) and not db.show_when_done then return false end
    if db.hide_collected and ObjectiveDone(node.objective) then return false end
    return true
end

local function GetIcon()
    return C_Item.GetItemIconByID(ICON_ITEM_ID) or FALLBACK_ICON
end

---------------------------------------------------------------------------
-- Handler (the interface the map-notes framework calls into)
---------------------------------------------------------------------------
local handler = {}

-- Zone maps: walk that zone's table.
local function ZoneIter(t, prev)
    if not t then return nil end
    local coord, node = next(t, prev)
    while coord do
        if ShouldShow(node) then
            return coord, nil, GetIcon(), db.icon_scale, db.icon_alpha
        end
        coord, node = next(t, coord)
    end
end

-- Outland continent map: walk the flattened list and report each pin's own zone.
local function ContinentIter()
    local i = 0
    return function()
        i = i + 1
        local node = allNodes[i]
        while node do
            if ShouldShow(node) then
                return node.coord, node.mapID, GetIcon(), db.icon_scale, db.icon_alpha
            end
            i = i + 1
            node = allNodes[i]
        end
    end
end

function handler:GetNodes2(uiMapID, minimap)
    if uiMapID == OUTLAND_MAP then
        if minimap or not db.show_continent then return function() end end
        return ContinentIter()
    end
    return ZoneIter, nodes[uiMapID], nil
end

local function FindNode(uiMapID, coord)
    local zone = nodes[uiMapID]
    if zone and zone[coord] then return zone[coord] end
    for _, node in ipairs(allNodes) do
        if node.coord == coord then return node end
    end
end

local function QuestTitle()
    return C_QuestLog.GetTitleForQuestID(QUEST_ID) or "Seeking the Soulstones"
end

function handler:OnEnter(uiMapID, coord)
    local node = FindNode(uiMapID, coord)
    if not node then return end

    local tooltip = GameTooltip
    if self:GetCenter() > UIParent:GetCenter() then
        tooltip:SetOwner(self, "ANCHOR_LEFT")
    else
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
    end

    tooltip:AddLine(node.label, 0.56, 1, 0)
    tooltip:AddLine(node.hint, 1, 1, 1, true)
    tooltip:AddLine(" ")
    tooltip:AddLine(QuestTitle(), 1, 0.82, 0)

    if C_QuestLog.IsQuestFlaggedCompleted(QUEST_ID) then
        tooltip:AddLine("Quest already completed", 0.5, 0.5, 0.5)
    elseif not C_QuestLog.IsOnQuest(QUEST_ID) then
        tooltip:AddLine("Not on this quest yet", 1, 0.3, 0.3)
    elseif ObjectiveDone(node.objective) then
        tooltip:AddLine("Collected", 0.3, 1, 0.3)
    else
        tooltip:AddLine("Watch for the cold / warm / hot debuff as you get close.", 0.8, 0.8, 0.8, true)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Right-click to set a map waypoint", 0.6, 0.6, 0.6)
    tooltip:Show()
end

function handler:OnLeave()
    GameTooltip:Hide()
end

function handler:OnClick(button, down, uiMapID, coord)
    if button ~= "RightButton" or down then return end
    local node = FindNode(uiMapID, coord)
    if not node then return end

    local x, y = parent:getXY(node.coord)
    if C_Map.CanSetUserWaypointOnMap(node.mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(node.mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------
local options = {
    type = "group",
    name = "Seeking the Soulstones",
    desc = "Pins for the four soulstone fragments in the warlock green fire quest.",
    get  = function(info) return db[info[#info]] end,
    set  = function(info, value)
        db[info[#info]] = value
        Refresh()
    end,
    args = {
        about = {
            type = "description", order = 0,
            name = "Shows where each soulstone fragment for \"Seeking the Soulstones\" can be found in Outland. Right-click a pin to drop a waypoint.\n",
        },
        icon_scale = {
            type = "range", order = 1, name = "Icon Scale",
            desc = "Size of the map pins.",
            min = 0.25, max = 3, step = 0.05,
        },
        icon_alpha = {
            type = "range", order = 2, name = "Icon Alpha",
            desc = "Transparency of the map pins.",
            min = 0, max = 1, step = 0.01,
        },
        warlock_only = {
            type = "toggle", order = 3, width = "full",
            name = "Only show on warlocks",
        },
        hide_collected = {
            type = "toggle", order = 4, width = "full",
            name = "Hide fragments you've already collected",
        },
        show_when_done = {
            type = "toggle", order = 5, width = "full",
            name = "Keep showing pins after the quest is turned in",
        },
        show_continent = {
            type = "toggle", order = 6, width = "full",
            name = "Show pins on the Outland continent map",
        },
    },
}

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local pending = false
local function QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Refresh()
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")

        HandyNotes_SeekingTheSoulstonesDB = HandyNotes_SeekingTheSoulstonesDB or {}
        db = HandyNotes_SeekingTheSoulstonesDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end

        parent:RegisterPluginDB(PLUGIN_NAME, handler, options)

        self:RegisterEvent("QUEST_ACCEPTED")
        self:RegisterEvent("QUEST_REMOVED")
        self:RegisterEvent("QUEST_TURNED_IN")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        QueueRefresh()
    end
end)
