-- QIangIQ's Bell: Vermintide 2's "The Bell" (levels/honduras/bell) inside Darktide, for SoloPlay and Realms-hosted SoloPlay.
-- PERSONAL USE ONLY. Geometry and textures are converted from Fatshark's Vermintide 2 assets on this PC and must never be
-- shared, so nothing spawns outside a SoloPlay local session (singleplay) or a Realms listen-server host of one.
-- Assets: QIangIQsBell:bell_lib (134 shared materials) + 177 chunk units (bell_layout.lua), built by
-- A:\Dowloads\QIangIQsMapViewer\bell (build_bell.py, compile_bell.py).
-- Gameplay data: decoded from the level's own data chunks (bell_data.lua, gen_bell_data.py): start, main path, 9 roaming
-- patrols, boss routes, 148 pickup spawners, 47 enemy spawners, 11 boss spawners, the bell, the lever, the end zone.
-- Events: terror_events_bell.lua (canyon_bell_event, canyon_ogre_boss, canyon_escape_event) with VT2's own horde
-- compositions (bell_hordes.lua), breeds mapped to Darktide ones (BREEDS below).
-- Mission: "bell_vt2" in SoloPlay's list = a copy of the prologue mission; the map loads 300 m above the host level.
-- Commands: /bell          load the map above you and stand at its start (any SoloPlay mission)
--           /bell back     return to where you were
--           /bell debug    print state (gate, assets, navmesh, spawns)
--           /bell bake     bake the navmesh around you now
--           /bell tp N     teleport to a VT2 landmark (start, lever, bell, end)
--           /bell event X  run an event now (bell, ogre, escape)
local mod = get_mod("QIangIQsBell")
local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")
local PlayerMovement = require("scripts/utilities/player_movement")
local HOST_TYPES = MatchmakingConstants.HOST_TYPES

local Layout = mod:io_dofile("QIangIQsBell/scripts/mods/QIangIQsBell/bell_layout")
local Data = mod:io_dofile("QIangIQsBell/scripts/mods/QIangIQsBell/bell_data")
local Hordes = mod:io_dofile("QIangIQsBell/scripts/mods/QIangIQsBell/bell_hordes")
if type(Layout) ~= "table" or type(Layout.chunks) ~= "table" then
    mod:error("bell_layout.lua could not be read; the Bell map is unavailable")
    Layout = { chunks = {} }
end
if type(Data) ~= "table" or type(Data.start) ~= "table" then
    mod:error("bell_data.lua could not be read; the Bell gameplay data is unavailable")
    Data = { start = { { 0, 0, 0 } }, main_path = {}, patrols = {}, boss_routes = {}, pickups = {}, enemy_spawners = {},
        boss_spawners = {}, seeds = {}, walkable = {}, bell = { 0, 0, 0 }, lever = { 0, 0, 0 }, end_zone = { 0, 0, 0 } }
end
Hordes = type(Hordes) == "table" and Hordes or {}
local VO = mod:io_dofile("QIangIQsBell/scripts/mods/QIangIQsBell/bell_vo")
VO = type(VO) == "table" and VO or { heroes = {}, lines = {}, eyes = {} }
-- audio, VT2 stories, cutscenes, one-way planes, the AI vision blocker and Realms sync (bell_extra.lua)
local ok_extra, Extra = pcall(mod.io_dofile, mod, "QIangIQsBell/scripts/mods/QIangIQsBell/bell_extra")
if not ok_extra or type(Extra) ~= "table" then
    mod:error("bell_extra.lua could not be read (%s); audio, stories and cutscenes are off", tostring(Extra))
    local noop = function() end
    Extra = { data = { nav = {} }, extra_rows = function() return {} end, setup = noop, on_map_built = noop, reset = noop,
        update = noop, play_vo = noop, stop_vo = noop, story = noop, music = noop, emit = noop, publish = noop, flash = function() return 0 end,
        host_base = noop, sync_available = noop, cutscene_active = noop, debug = function() return "bell_extra missing" end, unload = noop }
end
local LINE_BY_ID = {}
for _, list in pairs(VO.lines) do
    for _, l in ipairs(list) do
        LINE_BY_ID[l.id] = l
    end
end

local LIB_ID = "QIangIQsBell:bell_lib"
local UNIT_PREFIX = "content/mods/qiangiq_bell/"
local MISSION_KEY = "bell_vt2"
-- host = Relay Station TRS-150 (dm_propaganda) for its sky and atmosphere (was core_research, like the Wallclimber map; the
-- prologue forces its own loadout). Both are plain coop_complete_objective missions (pacing is held off by the hook below).
local HOST_MISSION = "dm_propaganda"
local RESCUE_BELOW = 85 -- metres below the VT2 origin; the map's lowest geometry is at about z -70
local SPAWNS_PER_FRAME = 6

-- ---------------------------------------------------------------------------------------------------- mission entry
local function register_mission()
    local ok, err = pcall(function()
        local MissionTemplates = require("scripts/settings/mission/mission_templates")
        local host = MissionTemplates[HOST_MISSION]
        if not host or MissionTemplates[MISSION_KEY] then
            return
        end
        local template = table.clone(host)
        template.name = MISSION_KEY
        template.mission_name = "loc_mission_name_bell_vt2"
        template.not_available_on_mission_board = true
        MissionTemplates[MISSION_KEY] = template
        local NetworkLookup = require("scripts/network_lookup/network_lookup")
        local lookup = rawget(NetworkLookup, "missions")
        if lookup and rawget(lookup, MISSION_KEY) == nil then
            local index = #lookup + 1
            rawset(lookup, index, MISSION_KEY)
            rawset(lookup, MISSION_KEY, index)
        end
        -- Havoc mutators (e.g. mutator_monster_havoc_twins) look up prebaked spawn points per mission name and crash
        -- the mission start (table.clone(nil)) when the mission has none; the Bell has none, so give it empty lists.
        local SpawnSettings = require("scripts/settings/mutator/mutator_monster_spawner_settings")
        for _, category in pairs(SpawnSettings) do
            if type(category) == "table" and rawget(category, MISSION_KEY) == nil then
                rawset(category, MISSION_KEY, {})
            end
        end
        local DialogueSettings = require("scripts/settings/dialogue/dialogue_settings")
        if DialogueSettings.blocked_auto_load_files then
            DialogueSettings.blocked_auto_load_files[MISSION_KEY] = DialogueSettings.blocked_auto_load_files[HOST_MISSION]
        end
        if DialogueSettings.level_specific_load_files then
            DialogueSettings.level_specific_load_files[MISSION_KEY] = DialogueSettings.level_specific_load_files[HOST_MISSION]
        end
    end)
    if not ok then
        mod:error("could not add the Bell mission: %s", tostring(err))
    end
end

mod:add_global_localize_strings({
    loc_mission_name_bell_vt2 = { en = "The Bell (Vermintide 2) - QIangIQ" },
})
register_mission()

-- ---------------------------------------------------------------------------------------------------- state
local custom_assets = nil
local lib_ticket = nil
local chunk_tickets = {}
local loaded_chunks = {}
local load_state = "idle" -- idle | loading | ready
local units = {}
local unit_set = {}
local named = {}          -- chunk name -> unit
local spawn_queue = nil
local base_box = nil      -- Vector3Box: VT2 origin in the world
local return_pos = nil
local release_pending = false
local auto_enter = nil
local want_auto = false
local wall_broken = false
local map_ready = false   -- all chunks spawned and the player stands at the start
local base_wait = nil     -- Realms client: seconds left to wait for the host's map origin (SyncChannel)
-- every unit to load and spawn: the map chunks, then the story pieces and one-way slabs (bell_extra.lua)
local ALL_ROWS = {}
for _, row in ipairs(Layout.chunks) do
    ALL_ROWS[#ALL_ROWS + 1] = row
end
for _, row in ipairs(Extra.extra_rows()) do
    ALL_ROWS[#ALL_ROWS + 1] = row
end

local function say(fmt, ...)
    mod:echo("[Bell] " .. string.format(fmt, ...))
end

local function local_player()
    local players = Managers.player
    if not players then
        return nil
    end
    local ok, player = pcall(players.local_player_safe, players, 1)
    return ok and player or nil
end

local function unit_ok(unit)
    return unit ~= nil and Unit.alive(unit)
end

local function current_mission()
    local m = Managers.state and Managers.state.mission
    local ok, name = pcall(function() return m and m:mission_name() end)
    return ok and name or nil
end

local function level_world()
    return Managers.world and Managers.world:world("level_world")
end

local function is_server()
    local gs = Managers.state and Managers.state.game_session
    if not gs then
        return true
    end
    local ok, res = pcall(gs.is_server, gs)
    return not ok or res ~= false
end

local function v3(t)
    return Vector3(t[1], t[2], t[3])
end

-- VT2 level position -> world position, and back. The map is built MAP_SCALE times VT2 size (setting map_size, set when the
-- map is placed): Darktide characters are bigger than VT2's heroes and did not fit through its gates at 1:1.
local MAP_SCALE = 1.75
local function W(t)
    return base_box:unbox() + v3(t) * MAP_SCALE
end

local function to_level(world_pos)
    return (world_pos - base_box:unbox()) / MAP_SCALE
end

local function flat_dist(a, b)
    return Vector3.length(Vector3.flat(a - b))
end

-- ---------------------------------------------------------------------------------------------------- the gate
-- SoloPlay missions only: singleplay, or the listen server Realms re-hosts them as (host type "player").
local function gate()
    local soloplay = get_mod("SoloPlay")
    if not soloplay or type(soloplay.is_soloplay) ~= "function" then
        return false, "SoloPlay is not installed"
    end
    local session = Managers.multiplayer_session
    local host = session and session:host_type()
    if host ~= HOST_TYPES.singleplay and host ~= HOST_TYPES.player then
        return false, "official servers are refused (SoloPlay or Realms host only)"
    end
    if host == HOST_TYPES.singleplay then
        local ok, is_solo = pcall(soloplay.is_soloplay)
        if not ok or not is_solo then
            return false, "not in a SoloPlay mission"
        end
    elseif current_mission() ~= MISSION_KEY and not mod:get("allow_realms_any") then
        return false, "Realms host: start 'The Bell' from the SoloPlay mission list"
    end
    local game_mode = Managers.state and Managers.state.game_mode
    local mode = game_mode and game_mode:game_mode_name()
    if mode == "hub" or mode == "prologue_hub" then
        return false, "missions only (not the Mourningstar)"
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------- host level
-- The Bell is built 300 m above the host mission, and the host's tall structures reach up into it. Host level units whose
-- box reaches the Bell's space are hidden while the Bell is up; the plain ones (no extensions) also lose their collision.
-- World-sized units (the sky dome) are left alone, so the sky and atmosphere stay the host's.
local host_level = { hidden = {} }   -- hidden = { { unit, actors = { i, ... } } }; one local (main chunk local limit)

function host_level.restore()
    if host_level.on_restore then
        pcall(host_level.on_restore)
    end
    for _, h in ipairs(host_level.hidden) do
        if unit_ok(h.unit) then
            pcall(Unit.set_unit_visibility, h.unit, true)
            for _, i in ipairs(h.actors) do
                pcall(Unit.create_actor, h.unit, i)
            end
        end
    end
    host_level.hidden = {}
end

function host_level.hide()
    host_level.restore()
    local world = level_world()
    if mod:get("hide_host_level") == false or not (base_box and world) then
        return
    end
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, row in ipairs(Layout.chunks) do
        minx, maxx = math.min(minx, row[2]), math.max(maxx, row[2])
        miny, maxy = math.min(miny, row[3]), math.max(maxy, row[3])
    end
    local pad = 70
    minx, miny, maxx, maxy = minx * MAP_SCALE - pad, miny * MAP_SCALE - pad, maxx * MAP_SCALE + pad, maxy * MAP_SCALE + pad
    local b = base_box:unbox()
    local bx, by, bz = Vector3.x(b), Vector3.y(b), Vector3.z(b)
    local zlow = bz - RESCUE_BELOW * MAP_SCALE - 10
    local em = Managers.state and Managers.state.extension
    local okx, ext_units = pcall(function() return em and em:units() end)
    ext_units = okx and type(ext_units) == "table" and ext_units or {}
    local seen, n, nc = 0, 0, 0
    -- every level in the world plus all their nested levels (most of a mission's art sits in sub-levels: 0.2.4 only walked the
    -- top levels and saw 615 units of TRS-150), each unit once
    local levels, lseen, useen = {}, {}, {}
    local function add_level(level)
        if level and not lseen[level] then
            lseen[level] = true
            levels[#levels + 1] = level
            local okn, nested = pcall(Level.nested_levels, level)
            for _, sub in ipairs(okn and type(nested) == "table" and nested or {}) do
                add_level(sub)
            end
        end
    end
    for _, level in ipairs(World.levels(world) or {}) do
        add_level(level)
    end
    for _, level in ipairs(levels) do
        local oku, lunits = pcall(Level.units, level, true)
        if not (oku and type(lunits) == "table") then
            oku, lunits = pcall(Level.units, level)
        end
        for _, u in ipairs(oku and type(lunits) == "table" and lunits or {}) do
            if not useen[u] then
            useen[u] = true
            seen = seen + 1
            if unit_ok(u) and not unit_set[u] then
                local ok, pose, ext = pcall(Unit.box, u)
                if ok and pose and ext then
                    local ex, ey, ez = Vector3.x(ext), Vector3.y(ext), Vector3.z(ext)
                    if math.max(ex, ey, ez) < 1500 then
                        -- world-axis half sizes of the rotated box
                        local ax, ay, az = Matrix4x4.x(pose), Matrix4x4.y(pose), Matrix4x4.z(pose)
                        local hx = math.abs(Vector3.x(ax)) * ex + math.abs(Vector3.x(ay)) * ey + math.abs(Vector3.x(az)) * ez
                        local hy = math.abs(Vector3.y(ax)) * ex + math.abs(Vector3.y(ay)) * ey + math.abs(Vector3.y(az)) * ez
                        local hz = math.abs(Vector3.z(ax)) * ex + math.abs(Vector3.z(ay)) * ey + math.abs(Vector3.z(az)) * ez
                        local c = Matrix4x4.translation(pose)
                        local cx, cy, cz = Vector3.x(c) - bx, Vector3.y(c) - by, Vector3.z(c)
                        if cz + hz > zlow and cx + hx > minx and cx - hx < maxx and cy + hy > miny and cy - hy < maxy then
                            local h = { unit = u, actors = {} }
                            pcall(Unit.set_unit_visibility, u, false)
                            if not ext_units[u] then
                                local okn, na = pcall(Unit.num_actors, u)
                                for i = 1, okn and na or 0 do
                                    local oka, actor = pcall(Unit.actor, u, i)
                                    if oka and actor then
                                        if pcall(Unit.destroy_actor, u, i) then
                                            h.actors[#h.actors + 1] = i
                                            nc = nc + 1
                                        end
                                    end
                                end
                            end
                            host_level.hidden[#host_level.hidden + 1] = h
                            n = n + 1
                        end
                    end
                end
            end
            end
        end
    end
    mod:info("HOST: hid %d of %d host level units in %d levels reaching the Bell (%d collision actors off)", n, seen, #levels, nc)
end

-- ---------------------------------------------------------------------------------------------------- units
local function despawn_all()
    host_level.restore()
    for _, unit in ipairs(units) do
        if unit_ok(unit) then
            local world = Unit.world(unit)
            if world then
                World.destroy_unit(world, unit)
            end
        end
    end
    units, unit_set, named, spawn_queue, base_box, map_ready = {}, {}, {}, nil, nil, false
end

local function release_all()
    if custom_assets and custom_assets.release then
        for _, t in pairs(chunk_tickets) do
            custom_assets.release(t)
        end
        if lib_ticket then
            custom_assets.release(lib_ticket)
        end
    end
    chunk_tickets, loaded_chunks, lib_ticket, load_state = {}, {}, nil, "idle"
end

local function clear_fall_speed(player_unit)
    local ude = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if ude then
        pcall(function()
            ude:write_component("locomotion").velocity_current = Vector3.zero()
        end)
    end
end

-- Not on the floor: ray down (the same filter the player mover uses) to find real ground below a VT2 position.
local function ground_below(pos, from_above, length)
    local world = level_world()
    local pw = world and World.physics_world(world)
    if not pw then
        return nil
    end
    local ok, hit, hit_pos = pcall(PhysicsWorld.raycast, pw, pos + Vector3(0, 0, from_above or 4), Vector3(0, 0, -1),
        length or 14, "closest", "collision_filter", "filter_player_mover")
    if ok and hit and hit_pos then
        return hit_pos
    end
    return nil
end

local function teleport_to(pos, rot)
    local player = local_player()
    local player_unit = player and player.player_unit
    if not unit_ok(player_unit) then
        return
    end
    PlayerMovement.teleport(player, pos, rot or Unit.world_rotation(player_unit, 1))
    clear_fall_speed(player_unit)
end

local function start_point()
    local s = Data.start[1]
    local p = W({ s[1], s[2], s[3] + 0.3 })
    return p
end

local function teleport_in()
    if base_box then
        local from = start_point()
        local g = ground_below(from, 2, 8)
        teleport_to(g and (g + Vector3(0, 0, 0.2)) or from)
    end
end

-- all chunk packages are ready: queue the units and spawn a few per frame (update)
local function start_spawning()
    local player = local_player()
    local player_unit = player and player.player_unit
    local world = level_world()
    if not (unit_ok(player_unit) and world) then
        say("no player unit or level world yet")
        return
    end
    local here = Unit.world_position(player_unit, 1)
    if #units > 0 and base_box then
        if not return_pos then
            return_pos = Vector3Box(here)
        end
        teleport_in()
        say("back in the Bell. /bell back to return")
        return
    end
    if not return_pos then
        return_pos = Vector3Box(here)
    end
    -- Realms: every peer builds its own copy of the map, so all must use the same origin. The host publishes its origin
    -- through SyncChannel (bell_extra.lua); without it every peer snaps the spawn position to a 128 m grid (players start
    -- within a few metres of each other, so the snapped origin agrees).
    local hb = Extra.host_base()
    if not hb and not is_server() and Extra.sync_available() and base_wait == nil then
        base_wait = 8
        say("waiting for the host's map origin...")
        return
    end
    base_wait = nil
    local height = mod:get("spawn_height_v2") or 120   -- 0.2.15: lower (user), was 300
    local function snap(v, g)
        return math.floor(v / g + 0.5) * g
    end
    MAP_SCALE = math.max(1, math.min(2.2, (mod:get("map_size") or 175) / 100))
    -- 0.2.15: Darktide's world is +-512 m (OutOfBoundsManager hard cap; a minion at the far end crashed the game at y -526),
    -- so the playable Bell (VT2 x -130..72, y -456..5, z -35..54) is centred on the world origin instead of the player
    base_box = Vector3Box(hb or Vector3(snap(30 * MAP_SCALE, 16), snap(226 * MAP_SCALE, 16),
        math.min(snap(Vector3.z(here) + height, 16), snap(512 - 80 * MAP_SCALE, 16))))
    spawn_queue = {}
    for _, row in ipairs(ALL_ROWS) do
        if loaded_chunks[row[1]] then
            spawn_queue[#spawn_queue + 1] = row
        end
    end
    say("building the Bell: %d chunks", #spawn_queue)
end

local function load_map()
    custom_assets = custom_assets or get_mod("CustomAssets")
    if not custom_assets or not custom_assets.is_api_compatible or not custom_assets.is_api_compatible(1) then
        say("Custom Assets (API 1) is missing")
        return
    end
    load_state = "loading"
    local pending = #ALL_ROWS
    local failed = 0
    local function chunk_done()
        pending = pending - 1
        if pending == 0 then
            load_state = "ready"
            if failed > 0 then
                say("%d chunk(s) failed to load (run the custom assets patcher with the game closed)", failed)
            end
            if gate() then
                start_spawning()
            end
        end
    end
    local t, err = custom_assets.acquire(mod, LIB_ID, function(_, _, load_error)
        if load_error then
            load_state = "idle"
            say("%s failed to load: %s (run the custom assets patcher with the game closed)", LIB_ID, tostring(load_error))
            return
        end
        for _, row in ipairs(ALL_ROWS) do
            local name = row[1]
            local id = "QIangIQsBell:" .. name
            local ct, cerr = custom_assets.acquire(mod, id, function(_, _, chunk_error)
                if chunk_error then
                    failed = failed + 1
                else
                    loaded_chunks[name] = true
                end
                chunk_done()
            end, { reference_name = id })
            if ct then
                chunk_tickets[name] = ct
            else
                failed = failed + 1
                mod:info("%s could not be requested: %s", id, tostring(cerr))
                chunk_done()
            end
        end
    end, { reference_name = LIB_ID })
    if not t then
        load_state = "idle"
        say("%s could not be requested: %s", LIB_ID, tostring(err))
        return
    end
    lib_ticket = t
    say("loading the Bell (%d packages)...", #ALL_ROWS + 1)
end

local function request_enter()
    local ok, why = gate()
    if not ok then
        say("SoloPlay/Realms only: %s", why)
        return
    end
    if load_state == "ready" then
        start_spawning()
    elseif load_state == "loading" then
        say("still loading...")
    else
        load_map()
    end
end

-- ---------------------------------------------------------------------------------------------------- crash guards
-- Same guards the Wallclimber map needed (native crash after a runtime navmesh bake): the original navmesh owns the main
-- path / spawn point data, so in our map the main path update is not run and pacing is held off until the Bell has a main
-- path of its own. 0.2.8 (dtpace, below): once the navmesh is baked, Darktide's MainPathManager gets a main path built from
-- VT2's main path, fresh spawn points on the Bell's navmesh, and pacing (roamers, hordes, specials) runs as in any mission.
local function in_map()
    return current_mission() == MISSION_KEY or (map_ready and #units > 0)
end

local dtpace = { state = nil, queue_id = 0, active = {} } -- state: nil, "occluding", "live", "stale"
function dtpace.live()
    return dtpace.state == "live"
end
function dtpace.held()
    return in_map() and not dtpace.live()
end

local guard_warned = false
-- renegade snipers (bt_sniper_movement_action._set_destinations) add to ahead_unit's travel distance, which is nil while no
-- player is on a main path segment: an uncaught Lua error that ends the game. A distance of 0 keeps the maths valid.
mod:hook("MainPathManager", "ahead_unit", function(func, self, ...)
    local unit, distance = func(self, ...)
    if distance == nil then
        distance = 0
    end
    return unit, distance
end)

mod:hook("MainPathManager", "update", function(func, self, ...)
    if dtpace.live() then
        -- progress tracking on the Bell's path: a player off every spawn point group must not take the game down
        local ok, err = pcall(func, self, ...)
        if not ok and not dtpace.update_err then
            dtpace.update_err = true
            mod:error("main path progress update failed in the Bell: %s", tostring(err))
        end
        return
    end
    if not dtpace.held() then
        return func(self, ...)
    end
    if not guard_warned then
        guard_warned = true
        mod:info("MainPathManager.update is held in the Bell until its own main path is built")
    end
end)

-- 0.2.8.1: on the Bell's main path a position off the Bell's spawn point groups (a host-level unit, a player in a gap of the
-- navmesh) has no group index and PathTypeLinear errored (start_index nil, path_type_linear.lua:174, crash on 2026-10-27
-- from the respawn beacon system); such positions now count as travel distance 0.
mod:hook("PathTypeLinear", "_information_from_position", function(func, self, position, return_on_no_index, ...)
    if dtpace.held() then
        return position, 0
    end
    if not (dtpace.live() and position) then
        return func(self, position, return_on_no_index, ...)
    end
    local ok, a, b, c, d, e = pcall(func, self, position, return_on_no_index, ...)
    if ok then
        return a, b, c, d, e
    end
    if return_on_no_index then
        return nil
    end
    return position, 0
end)

-- The host level's respawn beacons are not in the Bell; they are only gathered against the host's own main path (after
-- /bell back, dtpace.occlude), so hogtied players are never moved down to the host level.
mod:hook_require("scripts/extension_systems/respawn_beacon/respawn_beacon_system", function(RespawnBeaconSystem)
    mod:hook(RespawnBeaconSystem, "_create_respawn_beacons", function(func, self, ...)
        if in_map() or dtpace.state ~= nil then
            dtpace.beacons_skipped = self
            self._sorted_beacons = self._sorted_beacons or {}
            return
        end
        return func(self, ...)
    end)
end)

mod:hook("MainPathManager", "is_main_path_ready", function(func, self, ...)
    -- 0.2.12: not while occlude() regenerates roamers (RoamerPacing.generate_roamers asks this first; a false here left
    -- the density type nil and HordePacing crashed at the first trickle horde, horde_pacing.lua:775)
    if dtpace.held() and not dtpace.generating then
        return false
    end
    return func(self, ...)
end)

-- 0.2.14: nothing of Darktide's spawning (roamers, hordes, trickle hordes, specials, monsters) inside the start building
mod:hook("PacingManager", "spawn_type_enabled", function(func, self, spawn_type, ...)
    if dtpace.quiet() then
        return false, "bell_start_building"
    end
    return func(self, spawn_type, ...)
end)

-- belt and braces: no trickle horde while roamer pacing has no density type yet (it indexes compositions with it)
mod:hook("HordePacing", "_update_trickle_horde_pacing", function(func, self, ...)
    local pm = Managers.state.pacing
    if in_map() and pm and pm:current_density_type() == nil and pm:current_stage_name() == nil then
        return
    end
    return func(self, ...)
end)

mod:hook("GameModeCoopCompleteObjective", "_set_pacing", function(func, self, enabled)
    if dtpace.held() then
        return func(self, false)
    end
    return func(self, enabled)
end)

-- Specials pacing ran on the host's main path in the Bell (0.2.4 crash: _find_spawn_position got no main-path position,
-- nav_queries.lua:73 nil Vector3), so it is skipped until the Bell's own main path and spawn points are live.
mod:hook_require("scripts/managers/pacing/specials_pacing/specials_pacing", function(SpecialsPacing)
    mod:hook(SpecialsPacing, "update", function(func, self, ...)
        if dtpace.held() then
            return
        end
        if dtpace.live() then
            local ok, err = pcall(dtpace.stagger, self)
            if not ok and not dtpace.stagger_err then
                dtpace.stagger_err = true
                mod:error("specials stagger: %s", tostring(err))
            end
        end
        return func(self, ...)
    end)
end)

-- 0.2.16 (user playtest 2026-10-27: specials came in giant waves instead of a constant pressure stream): slots whose timers
-- ran out together (spawn positions failing, travel distance jumps on the Bell's path) all spawned at once. Only one due
-- slot may spawn per special_gap seconds; the others are pushed back one gap each.
function dtpace.stagger(sp)
    local slots, n = sp._specials_slots, sp._max_alive_specials
    local gap = mod:get("special_gap") or 14
    if not (slots and n) or gap <= 0 then
        return
    end
    local now = Managers.time:time("gameplay")
    local busy, ready = 0, {}
    for i = 1, n do
        local slot = slots[i]
        if slot then
            if slot.spawned or slot.spawner_queue_id then
                busy = busy + 1
            elseif slot.spawn_timer and slot.spawn_timer <= 0 then
                ready[#ready + 1] = slot
            end
        end
    end
    if busy > (dtpace.sp_busy or 0) then
        dtpace.sp_last = now
    end
    dtpace.sp_busy = busy
    local since = now - (dtpace.sp_last or -1000)
    local keep = since >= gap and 1 or 0
    for k = keep + 1, #ready do
        ready[k].spawn_timer = math.max(gap - since, 0) + (k - keep - 1) * gap + math.random() * 3 + 0.5
    end
end

-- Darktide's ambush hordes and specials ask the minion spawner system for spawners near the target. In the Bell, VT2's own
-- spawners (bell_spawners.lua) answer as well, so enemies stream out of VT2's hidden spawn spots, windows and ledges.
mod:hook_require("scripts/extension_systems/minion_spawner/minion_spawner_system", function(MinionSpawnerSystem)
    mod:hook(MinionSpawnerSystem, "spawners_in_range", function(func, self, position, radius, ...)
        local list = func(self, position, radius, ...)
        if dtpace.live() and position and dtpace.add_in_range then
            local ok, err = pcall(dtpace.add_in_range, list, position, radius)
            if not ok then
                mod:error("VT2 spawner lookup failed: %s", tostring(err))
            end
        end
        return list
    end)
end)

-- The host level's kill volumes and soft out-of-bounds check do not know the Bell is up here: they killed players outright in
-- the Bell's streets (volume_event_functions.player_instakill, PlayerUnitLocomotionExtension._on_soft_oob). In the Bell the
-- mod's own fall rescue (update_rescue, the VT2 death zone) handles falls instead.
local function in_bell_space(unit)
    if not (map_ready and base_box and unit_ok(unit)) then
        return false
    end
    return Vector3.z(Unit.world_position(unit, 1)) > Vector3.z(base_box:unbox()) - RESCUE_BELOW * MAP_SCALE - 20
end

mod:hook_require("scripts/settings/volume_event/volume_event_functions", function(functions)
    local entry = functions and functions.player_instakill
    if entry and entry.on_enter and not entry._bell_wrapped then
        local orig = entry.on_enter
        entry.on_enter = function(entering_unit, ...)
            if in_bell_space(entering_unit) then
                return
            end
            return orig(entering_unit, ...)
        end
        entry._bell_wrapped = true
    end
end)

-- 0.2.15: a minion that still ends up past the +-512 m hard cap is removed instead of taking the game down (ferror)
mod:hook_require("scripts/managers/out_of_bounds/out_of_bounds_manager", function(OOB)
    mod:hook(OOB, "post_update", function(func, self, shared_state)
        if not (map_ready and base_box) then
            return func(self, shared_state)
        end
        local ok, err = pcall(func, self, shared_state)
        if not ok then
            local us = Managers.state.unit_spawner
            for unit in pairs(shared_state.hard_cap_out_of_bounds_units or {}) do
                if unit_ok(unit) and not (Managers.state.player_unit_spawn and
                    Managers.state.player_unit_spawn:owner(unit)) and us and not us:is_marked_for_deletion(unit) then
                    us:mark_for_deletion(unit)
                end
            end
            mod:warning("Bell out-of-bounds units removed: %s", tostring(err):sub(1, 300))
        end
    end)
end)

mod:hook("PlayerUnitLocomotionExtension", "_on_soft_oob", function(func, self, ...)
    if in_bell_space(self._unit) then
        return
    end
    return func(self, ...)
end)

-- ---------------------------------------------------------------------------------------------------- sky look
-- The Bell runs inside a host mission, so it inherits that mission's sky. After CameraManager.shading_callback has blended the
-- environment, re-tint sun / fog / skydome toward a preset (hue only, brightness is kept so exposure stays right) and move the
-- sun to the preset's elevation. VT2's Bell is the "wv_dusk_snow_01" look: low warm sun, blue-grey fog, warm-grey sky.
-- Presets are hand-matched approximations, not copies of a Darktide environment file.
local SKY_PRESETS = {
    -- 0.2.15 (user: overhead sun, tropical blue instead of desert yellow, like Archivum Sycorax); default
    tropical = { elevation = 70, sun = { 0.86, 0.94, 1.0 }, fog = { 0.52, 0.72, 0.98 }, dome = { 0.60, 0.80, 1.0 } },
    dusk = { elevation = 35.7, sun = { 1.0, 0.74, 0.52 }, fog = { 0.60, 0.68, 0.85 }, dome = { 0.95, 0.88, 0.84 } },
    sunset = { elevation = 18, sun = { 1.0, 0.62, 0.34 }, fog = { 0.96, 0.55, 0.27 }, dome = { 1.0, 0.82, 0.66 } },
    overcast = { elevation = 50, sun = { 0.85, 0.9, 1.0 }, fog = { 0.60, 0.65, 0.85 }, dome = { 0.88, 0.92, 1.0 } },
}

local function lum(r, g, b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function retint(shading_env, name, hue)
    local ok, v = pcall(ShadingEnvironment.vector3, shading_env, name)
    if not ok or not v then
        return
    end
    local r, g, b = v.x, v.y, v.z
    local l = lum(r, g, b)
    local h = lum(hue[1], hue[2], hue[3])
    if l <= 0 or h <= 0 then
        return
    end
    local k = l / h
    pcall(ShadingEnvironment.set_vector3, shading_env, name, Vector3(hue[1] * k, hue[2] * k, hue[3] * k))
end

mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env)
    if not shading_env or not in_map() then
        return
    end
    -- lightning flash (bell_extra.lua, VT2's lightning light envelopes): brighten sun, sky and fog for a moment
    local f = Extra.flash()
    if f > 0.001 then
        pcall(function()
            local k = 1 + 2.5 * f
            for _, name in ipairs({ "sun_color", "skydome_tint_color", "fog_color" }) do
                local v = ShadingEnvironment.vector3(shading_env, name)
                ShadingEnvironment.set_vector3(shading_env, name, Vector3(v.x * k, v.y * k * 1.02, v.z * k * 1.08))
            end
        end)
    end
    local look = mod:get("sky_look_v3") or "tropical"
    local preset = SKY_PRESETS[look]
    if not preset then
        return
    end
    local ok = pcall(function()
        retint(shading_env, "sun_color", preset.sun)
        retint(shading_env, "fog_color", preset.fog)
        retint(shading_env, "skydome_tint_color", preset.dome)
        local d = ShadingEnvironment.vector3(shading_env, "sun_direction")
        local hx, hy = d.x, d.y
        local hl = math.sqrt(hx * hx + hy * hy)
        if hl < 0.05 then
            hx, hy, hl = -0.95, 0.31, 1
        end
        local e = math.rad(preset.elevation)
        local c = math.cos(e)
        ShadingEnvironment.set_vector3(shading_env, "sun_direction", Vector3(c * hx / hl, c * hy / hl, -math.sin(e)))
    end)
    if not ok and mod:get("verbose") and not mod._sky_warned then
        mod._sky_warned = true
        mod:echo("Bell sky look failed (shading env API); set sky look to off")
    end
end)

-- ---------------------------------------------------------------------------------------------------- navmesh bake
-- Runtime navmesh, the calls the game makes for Expedition levels (bake_navmesh.lua push_units / generate,
-- expedition_spawner.lua:29 navgen_settings): GwNavGeneration.create, reset_current_navtag, push_unit_meshes (physics mesh of
-- the chunk collision), push_seed_point, generate_async with nav_mesh:set_async_paused(true), finish_async_generation each
-- frame, GwNavData.is_alive_in_database, nav_mesh:_make_sparse_graph_dirty().
-- The level's own 124 seedpoint units and the walkable points of its spawn data (thinned to one per 9 m) are the seeds, so
-- every bake starts from ground the original navmesh covered. The map is cut into TILE squares; every square within
-- AUTO_RADIUS of the player that is not baked yet is baked in one go, starting well before the edge of the last bake.
local BAKE_RADIUS = 34
local TILE = 40
local AUTO_RADIUS = 70
local AUTO_TRIGGER = 42
local navbake = nil
local bake_tiles = {}   -- "ix:iy" -> true once baked or queued
local bake_count = 0
local bake_wanted = {}  -- VT2 positions that need a bake (a spawn found no navmesh there)
local auto_bake_t = 2
local bake_epoch = 0

local function nav_world()
    local nm = Managers.state and Managers.state.nav_mesh
    local ok, nw = pcall(function() return nm and nm:nav_world() end)
    return ok and nw or nil
end

local function finish_navbake(msg)
    pcall(function() Managers.state.nav_mesh:set_async_paused(false) end)
    navbake = nil
    if msg then
        mod:info("%s", msg)
        if mod:get("verbose") then
            say("%s", msg)
        end
    end
end

local function seeds_near(pts)
    local out = {}
    local function add(list)
        for _, s in ipairs(list) do
            for _, p in ipairs(pts) do
                if math.abs(s[1] - p[1]) < TILE * 0.5 + BAKE_RADIUS and math.abs(s[2] - p[2]) < TILE * 0.5 + BAKE_RADIUS then
                    out[#out + 1] = s
                    break
                end
            end
        end
    end
    add(Data.seeds)
    add(Data.walkable)
    return out
end

-- pts = { {x, y, z}, ... } in VT2 coordinates (tile centres); keys = tile keys marked as baked
local function start_navbake(pts, keys)
    if navbake then
        return false
    end
    local ok, err = pcall(function()
        local Gen = rawget(_G, "GwNavGeneration")
        if not Gen then
            error("GwNavGeneration is not available in this game build")
        end
        local world, nw = level_world(), nav_world()
        if not (world and nw and #units > 0 and base_box) then
            error("build the map first (nav world: " .. tostring(nw ~= nil) .. ", units: " .. #units .. ")")
        end
        local nav_gen = Gen.create(world)
        local pushed = 0
        for _, row in ipairs(Layout.chunks) do
            local unit = named[row[1]]
            if unit_ok(unit) then
                for _, p in ipairs(pts) do
                    if math.sqrt((row[2] - p[1]) ^ 2 + (row[3] - p[2]) ^ 2) < BAKE_RADIUS + 23 then
                        Gen.reset_current_navtag(nav_gen)
                        Gen.push_unit_meshes(nav_gen, unit, true, false, true)
                        pushed = pushed + 1
                        break
                    end
                end
            end
        end
        for _, k in ipairs(keys or {}) do
            bake_tiles[k] = true
        end
        if pushed == 0 then
            Gen.destroy(nav_gen)
            error("no chunk within " .. BAKE_RADIUS .. " m of the bake points")
        end
        local pu = local_player() and local_player().player_unit
        if unit_ok(pu) then
            Gen.push_seed_point(nav_gen, Unit.local_position(pu, 1))
        end
        local nseeds = 0
        for _, s in ipairs(seeds_near(pts)) do
            local gp = ground_below(W(s), 1.5, 5)
            if gp then
                Gen.push_seed_point(nav_gen, gp + Vector3(0, 0, 0.1))
                nseeds = nseeds + 1
            end
        end
        local settings = {
            altitude_tolerance = 0.5, atomic_consume_units = true, cell_size = 3, consume_terrain = true,
            database_index = 0, entity_height = 1.6, entity_radius = 0.38, height_field_sampling = 1,
            min_navigable_surface = 0.5, output_type = 1, raster_precision = 0.1, sector_name = "world",
            slope_max = 60, step_max = 0.5, sector_id = math.uuid(),
        }
        Managers.state.nav_mesh:set_async_paused(true)
        local job_id = Gen.generate_async(nav_gen, nw, settings, { [math.uuid()] = "BellNav" })
        Gen.destroy(nav_gen)
        navbake = { job_id = job_id, t = 0, chunks = pushed, seeds = nseeds }
        mod:info("NAVBAKE started: %d chunk units, %d seed points, %d tiles", pushed, nseeds, #pts)
        if mod:get("verbose") then
            say("navmesh bake: %d chunks, %d seeds", pushed, nseeds)
        end
    end)
    if not ok then
        mod:error("navmesh bake failed to start: %s", tostring(err))
        pcall(function() Managers.state.nav_mesh:set_async_paused(false) end)
        say("navmesh bake failed: %s", tostring(err))
        return false
    end
    return true
end

local function update_navbake(dt)
    if not navbake then
        return
    end
    navbake.t = navbake.t + dt
    if navbake.t > 240 then
        local vt2 = navbake.vt2
        finish_navbake("navmesh bake gave up after 240 s")
        if vt2 and mod.on_bake_failed then
            mod.on_bake_failed("gave up after 240 s")
        end
        return
    end
    local ok, err = pcall(function()
        if not navbake.data then
            local done, navmesh = GwNavGeneration.finish_async_generation(nav_world(), navbake.job_id)
            if done then
                navbake.data = navmesh
            end
        end
        if navbake.data and GwNavData.is_alive_in_database(navbake.data) then
            local t = navbake.t
            local vt2 = navbake.vt2
            Managers.state.nav_mesh:_make_sparse_graph_dirty()
            bake_epoch = bake_epoch + 1
            bake_count = bake_count + 1
            finish_navbake(string.format("navmesh ready (%.0f s, bake %d%s)", t, bake_count, vt2 and ", VT2 navmesh" or ""))
            if mod.on_bake_done then
                mod.on_bake_done(vt2)
            end
        end
    end)
    if not ok then
        mod:error("navmesh bake failed: %s", tostring(err))
        local vt2 = navbake and navbake.vt2
        finish_navbake("navmesh bake failed: " .. tostring(err))
        if vt2 and mod.on_bake_failed then
            mod.on_bake_failed(err)
        end
    end
end

local function bake_around(here_level, radius, force)
    local hx, hy = here_level[1], here_level[2]
    local cx, cy = math.floor(hx / TILE), math.floor(hy / TILE)
    local n = math.ceil(radius / TILE)
    local pts, keys = {}, {}
    for ix = cx - n, cx + n do
        for iy = cy - n, cy + n do
            local key = ix .. ":" .. iy
            if force or not bake_tiles[key] then
                local tx, ty = (ix + 0.5) * TILE, (iy + 0.5) * TILE
                if math.sqrt((tx - hx) ^ 2 + (ty - hy) ^ 2) < radius then
                    pts[#pts + 1] = { tx, ty, here_level[3] }
                    keys[#keys + 1] = key
                end
            end
        end
    end
    if #pts == 0 then
        return false
    end
    return start_navbake(pts, keys)
end

-- bake spawns asked for (bake_wanted) first, else tiles around the player
local function auto_navbake(here, dt)
    if navbake or not here or not base_box or mod:get("auto_navmesh") == false then
        return
    end
    -- the VT2 navmesh (below) covers the whole level; tiles are only baked when it could not be used
    if mod.vt2nav_state and mod.vt2nav_state() ~= "failed" then
        return
    end
    auto_bake_t = auto_bake_t - dt
    if auto_bake_t > 0 then
        return
    end
    auto_bake_t = 1
    -- 0.2.6: one bake over the whole map first. Eight overlapping tile bakes crashed gwnav's worker thread (access
    -- violation seconds after "bake 8"); the full bake marks every tile, so no further bakes are added on top of it.
    if not mod._bell_full_bake then
        mod._bell_full_bake = true
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for _, row in ipairs(Layout.chunks) do
            x0, y0 = math.min(x0, row[2]), math.min(y0, row[3])
            x1, y1 = math.max(x1, row[2]), math.max(y1, row[3])
        end
        if x0 < x1 then
            local r = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) * 0.5 + TILE
            if bake_around({ (x0 + x1) * 0.5, (y0 + y1) * 0.5, Vector3.z(to_level(here)) }, r, true) then
                return
            end
        end
    end
    local want = table.remove(bake_wanted)
    if want then
        bake_around(want, AUTO_RADIUS * 0.8)
        return
    end
    local l = to_level(here)
    local lv = { Vector3.x(l), Vector3.y(l), Vector3.z(l) }
    local hx, hy = lv[1], lv[2]
    local cx, cy = math.floor(hx / TILE), math.floor(hy / TILE)
    local n = math.ceil(AUTO_RADIUS / TILE)
    local nearest = math.huge
    for ix = cx - n, cx + n do
        for iy = cy - n, cy + n do
            if not bake_tiles[ix .. ":" .. iy] then
                local d = math.sqrt(((ix + 0.5) * TILE - hx) ^ 2 + ((iy + 0.5) * TILE - hy) ^ 2)
                if d < AUTO_RADIUS then
                    nearest = math.min(nearest, d)
                end
            end
        end
    end
    if nearest < AUTO_TRIGGER then
        bake_around(lv, AUTO_RADIUS)
    end
end

local function want_bake(world_pos)
    if not base_box or dtpace.live() then
        return -- 0.2.8: no bakes under Darktide's live spawn points (the whole map was baked first)
    end
    local l = to_level(world_pos)
    local key = math.floor(Vector3.x(l) / TILE) .. ":" .. math.floor(Vector3.y(l) / TILE)
    if bake_tiles[key] then
        return
    end
    for _, w in ipairs(bake_wanted) do
        if math.abs(w[1] - Vector3.x(l)) < TILE and math.abs(w[2] - Vector3.y(l)) < TILE then
            return
        end
    end
    bake_wanted[#bake_wanted + 1] = { Vector3.x(l), Vector3.y(l), Vector3.z(l) }
end

-- ---------------------------------------------------------------------------------------------------- Darktide pacing (0.2.8)
-- Darktide's own spawning in the Bell. The host mission's main path and spawn points belong to the host level, so the Bell
-- gives Darktide's MainPathManager a main path of its own once the navmesh is baked: VT2's main path nodes (bell_data
-- main_path) are registered with EngineOptimized as one segment, spawn points are generated on the Bell's navmesh by
-- MainPathManager:generate_spawn_points (flood fill from the path), occluded points are generated over a few frames, and then
-- the PacingManager runs: roamers, hordes, specials and the Auric / Havoc density of the mission's own pacing templates.
-- Monster pacing stays paused (its spawn points are the host level's); the Bell's own VT2 bosses and terror events still run.
-- On /bell back the host's main path is rebuilt from its resource. Setting dt_pacing (off = the Bell's own spawn director).
dtpace.rows = (function()
    local ok, rows = pcall(mod.io_dofile, mod, "QIangIQsBell/scripts/mods/QIangIQsBell/bell_spawners")
    return ok and type(rows) == "table" and rows or {}
end)()

function dtpace.wanted()
    return mod:get("dt_pacing") ~= false
end

-- where a VT2 spawner lets its enemies out, on the navmesh: hidden spawners (kind 0) at the spawner itself (VT2 places them
-- out of sight); windows, ledges and floor holes a step in front of the spawner (+Y is the way VT2's spawn animations go)
function dtpace.spawn_pos(i)
    local mpm = Managers.state.main_path
    local nsp = mpm and mpm._nav_spawn_points
    if dtpace.cache_epoch ~= bake_epoch or dtpace.cache_nsp ~= nsp or not dtpace.cache then
        dtpace.cache, dtpace.cache_epoch, dtpace.cache_nsp = {}, bake_epoch, nsp
    end
    local c = dtpace.cache[i]
    if c ~= nil then
        return c and c:unbox() or nil
    end
    local row = dtpace.rows[i]
    local nw = nav_world()
    if not (row and nw) then
        return nil
    end
    local NavQueries = require("scripts/utilities/nav_queries")
    local found
    if row[6] == 0 then
        local p = W(row)
        found = NavQueries.position_on_mesh(nw, p, 2, 3)
            or NavQueries.position_on_mesh_with_outside_position(nw, nil, p, 2, 3, 3)
    else
        for _, step in ipairs({ 1.2, 2, -1.2 }) do
            local p = W({ row[1] + row[4] * step, row[2] + row[5] * step, row[3] })
            found = NavQueries.position_on_mesh(nw, p, 1.5, row[6] == 1 and 9 or 3)
            if found then
                break
            end
        end
    end
    -- 0.2.15: the exit must be on navmesh connected to the main path (its spawn point groups flood out from the path);
    -- a spawner on a sealed-off island lets enemies out where they can never reach the players
    if found then
        if not nsp then
            return found -- not cached: checked again once spawn points exist
        end
        local okg, g = pcall(GwNavSpawnPoints.get_group_from_position, nsp, nw, found, 2, 2)
        if not (okg and g) then
            mod:info("DTPACE VT2 spawner %d dropped: exit not connected to the main path", i)
            found = nil
        end
    end
    dtpace.cache[i] = found and Vector3Box(found) or false
    return found
end

-- a VT2 spawner that answers Darktide's spawner queries (the calls ambush_horde_template and specials_pacing make on
-- MinionSpawnerExtension); queued minions stream out one by one like VT2's spawn_rate
dtpace.Fake = {}
dtpace.Fake.__index = dtpace.Fake
function dtpace.Fake:position() return self.pos:unbox() end
function dtpace.Fake:rotation() return Quaternion.look(self.fwd:unbox(), Vector3.up()) end
function dtpace.Fake:is_excluded_from_pacing() return false end
function dtpace.Fake:is_excluded_from_specials_pacing() return false end
function dtpace.Fake:spawn_type() return "bell_vt2" end
function dtpace.Fake:spawner_groups() return {} end
function dtpace.Fake:exit_position_boxed() return self.pos end
function dtpace.Fake:request_param_table() return {} end
function dtpace.Fake:is_spawning() return #self.queue > 0 end
function dtpace.Fake:spawned_minions_by_queue_id(queue_id) return self.spawned[queue_id] end
function dtpace.Fake:add_spawns(breed_list, side_id, param)
    if not breed_list or #breed_list == 0 then
        return nil
    end
    dtpace.queue_id = dtpace.queue_id + 1
    param = param or {}
    param.spawn_side_id = side_id
    for _, breed in ipairs(breed_list) do
        self.queue[#self.queue + 1] = { breed = breed, param = param, qid = dtpace.queue_id }
    end
    self.next_t = self.next_t or 0
    dtpace.active[self] = true
    return dtpace.queue_id
end

function dtpace.make_fakes()
    dtpace.fakes = {}
    for i, row in ipairs(dtpace.rows) do
        local p = dtpace.spawn_pos(i)
        if p then
            dtpace.fakes[#dtpace.fakes + 1] = setmetatable({ pos = Vector3Box(p), fwd = Vector3Box(Vector3(row[4], row[5], 0)),
                queue = {}, spawned = {}, i = i }, dtpace.Fake)
        end
    end
    mod:info("DTPACE %d of %d VT2 spawners have a navmesh exit", #dtpace.fakes, #dtpace.rows)
end

function dtpace.add_in_range(list, position, radius)
    if not list or not dtpace.fakes then
        return
    end
    local r2 = radius * radius
    for _, sp in ipairs(dtpace.fakes) do
        local d = sp.pos:unbox() - position
        if Vector3.dot(d, d) <= r2 then
            list[#list + 1] = sp
        end
    end
end

function dtpace.spawn_one(sp, e)
    local msm = Managers.state.minion_spawn
    local PerceptionSettings = require("scripts/settings/perception/perception_settings")
    local p = e.param
    local target_unit = p.optional_group_target
    if not target_unit and p.target_side_id then
        target_unit = Managers.state.main_path:ahead_unit(p.target_side_id)
    end
    local param = msm:request_param_table()
    param.optional_aggro_state = p.aggro_state or PerceptionSettings.aggro_states.aggroed
    param.optional_target_unit = target_unit
    param.optional_group_id = p.group_id
    param.optional_health_modifier = p.max_health_modifier
    param.optional_attack_selection_template_name = p.attack_selection_template_name
    param.optional_mission_objective_id = p.mission_objective_id
    param.optional_init_toughness = p.optional_init_toughness
    param.optional_owning_auto_event_id = p.optional_owning_auto_event_id
    -- 0.2.16: spread out around the exit (user: hordes came out in one clump)
    local pos = sp.pos:unbox()
    local nw = nav_world()
    if nw then
        local a, r = math.random() * 6.283, 1 + math.random() * 3.5
        local NavQueries = require("scripts/utilities/nav_queries")
        local q = NavQueries.position_on_mesh(nw, pos + Vector3(math.cos(a) * r, math.sin(a) * r, 0), 1.5, 1.5)
        if q then
            pos = q
        end
    end
    return msm:spawn_minion(e.breed, pos, sp:rotation(), p.spawn_side_id, param)
end

function dtpace.update_spawners(dt)
    for sp in pairs(dtpace.active) do
        sp.next_t = (sp.next_t or 0) - dt
        if sp.next_t <= 0 then
            local e = table.remove(sp.queue, 1)
            if e then
                sp.next_t = 0.3
                local ok, unit = pcall(dtpace.spawn_one, sp, e)
                if ok and unit then
                    local got = sp.spawned[e.qid] or {}
                    got[#got + 1] = unit
                    sp.spawned[e.qid] = got
                elseif not ok then
                    mod:error("VT2 spawner %d: %s", sp.i, tostring(unit))
                end
            else
                sp.next_t = nil
                dtpace.active[sp] = nil
            end
        end
    end
end

-- destroys the spawn point data MainPathManager owns (host's or ours) so it can be generated again
function dtpace.drop(mpm)
    if mpm._nav_spawn_points then
        GwNavSpawnPoints.destroy(mpm._nav_spawn_points)
        mpm._nav_spawn_points = nil
    end
    if mpm._nav_triangle_group then
        GwNavTriangleGroup.destroy(mpm._nav_triangle_group)
        mpm._nav_triangle_group = nil
    end
    if mpm._spawn_point_cost_table then
        GwNavTagLayerCostTable.destroy(mpm._spawn_point_cost_table)
        mpm._spawn_point_cost_table = nil
    end
    if mpm._main_path_version then
        EngineOptimized.unregister_main_path()
        mpm._main_path_version = nil
    end
end

-- host = true rebuilds the host mission's own main path from its resource (after /bell back)
function dtpace.build(host)
    local mpm = Managers.state.main_path
    if not (mpm and Managers.state.pacing and rawget(_G, "EngineOptimized") and rawget(_G, "GwNavSpawnPoints")) then
        error("no main path manager in this game state")
    end
    local MainPathQueries = require("scripts/utilities/main_path_queries")
    local MainPathSettings = require("scripts/settings/main_path/main_path_settings")
    if not dtpace.host_type then
        dtpace.host_type = mpm._path_type or "linear"
    end
    dtpace.drop(mpm)
    if host then
        if not mpm:setup_for_level(mpm._main_path_resource_name, false) then
            error("the host mission has no main path resource")
        end
        mpm._path_type = dtpace.host_type
    else
        local nodes = {}
        for _, n in ipairs(Data.main_path) do
            nodes[#nodes + 1] = Vector3Box(W(n))
        end
        if #nodes < 2 then
            error("the Bell has no main path data")
        end
        local segs = { { nodes = nodes } }
        mpm:_calculate_travel_distances(segs)
        local path, dists, lookup, _, order = MainPathQueries.generate_unified_main_path(segs)
        EngineOptimized.register_main_path(path, dists, lookup, #segs)
        mpm.main_path_breaks_order = order
        mpm._path_markers, mpm._main_path_segments = {}, segs
        mpm._main_path_version = MainPathSettings.main_path_version
        mpm._chosen_crossroads = nil
        mpm._path_type = "linear"
    end
    mpm._spawn_points_time_slice_data = nil
    local PathClass = require(MainPathSettings.path_types[mpm._path_type] or MainPathSettings.path_types.linear)
    if mpm._path then
        mpm._path:destroy()
    end
    mpm._path = PathClass:new(mpm._world, mpm._nav_world, mpm._num_sides)
    mpm:generate_spawn_points()
    dtpace.state, dtpace.for_host, dtpace.fakes, dtpace.active = "occluding", host, nil, {}
    mod:info("DTPACE %s main path registered (%d nodes), generating occluded spawn points", host and "host" or "Bell",
        #(mpm._main_path_segments[1] and mpm._main_path_segments[1].nodes or {}))
end

function dtpace.occlude()
    local mpm, pm = Managers.state.main_path, Managers.state.pacing
    local MainPathSettings = require("scripts/settings/main_path/main_path_settings")
    local done = GwNavSpawnPoints.generate_occluded_points(mpm._nav_spawn_points, mpm._nav_world, mpm._world,
        MainPathSettings.occluded_points_collision_filter, 0.004)
    if not done then
        return
    end
    pcall(pm.reset, pm) -- a fresh roamer pacing for the new spawn points
    dtpace.generating = true
    local okg, errg = pcall(pm.on_spawn_points_generated, pm)
    dtpace.generating = nil
    if not okg then
        mod:error("DTPACE roamer generation: %s", tostring(errg))
    end
    mod:info("DTPACE roamers generated, density %s", tostring(pm:current_density_type()))
    local hp = pm._horde_pacing
    if hp then
        hp._triggered_hordes, hp._old_furthest_travel_distance = 0, 0
    end
    pm:pause_spawn_type("monsters", not dtpace.for_host, "qiangiq_bell")
    if dtpace.for_host then
        dtpace.state, dtpace.for_host = nil, nil
        local rb = dtpace.beacons_skipped
        dtpace.beacons_skipped = nil
        if rb then
            local okb, errb = pcall(rb._create_respawn_beacons, rb)
            if not okb then
                mod:error("host respawn beacons: %s", tostring(errb))
            end
        end
        mod:info("DTPACE host main path restored")
        return
    end
    dtpace.make_fakes()
    dtpace.state = "live"
    local gm = Managers.state.game_mode and Managers.state.game_mode:game_mode()
    if gm then
        gm._pacing_enabled = true
    end
    pm:set_enabled(true)
    mod:info("DTPACE live: Darktide pacing runs on the Bell's main path")
    if mod:get("verbose") then
        say("Darktide spawning is on in the Bell")
    end
end

function dtpace.stale()
    dtpace.state = "stale"
    pcall(function() Managers.state.pacing:set_enabled(false) end)
end

-- runs every frame on the server while the Bell is up
function dtpace.update(dt)
    if not (dtpace.wanted() and map_ready and bake_count > 0) or dtpace.failed then
        return
    end
    if navbake then
        if dtpace.state == "live" then
            dtpace.stale() -- a bake changes the navmesh under the spawn points: hold pacing and rebuild afterwards
        end
        return
    end
    local ok, err = true, nil
    if dtpace.state == nil or dtpace.state == "stale" then
        ok, err = pcall(dtpace.build, false)
    elseif dtpace.state == "occluding" then
        ok, err = pcall(dtpace.occlude)
    else
        dtpace.update_spawners(dt)
    end
    if not ok then
        dtpace.failed, dtpace.state = true, nil
        mod:error("Darktide pacing could not start in the Bell: %s", tostring(err))
        say("Darktide spawning could not start in the Bell (%s); the Bell's own spawn director is used", tostring(err))
    end
end

-- called when the Bell is torn down: give the host mission its main path back (finished over the next frames)
function dtpace.restore()
    local had = dtpace.state ~= nil
    dtpace.state, dtpace.fakes, dtpace.active, dtpace.cache, dtpace.failed = nil, nil, {}, nil, nil
    if had and is_server() then
        local ok, err = pcall(dtpace.build, true)
        if not ok then
            mod:error("host main path restore failed: %s", tostring(err))
            dtpace.state = nil
        end
    end
end

-- all = true on leaving the gameplay state (its main path manager is gone); otherwise a host restore in progress is kept
function dtpace.reset(all)
    if all or not dtpace.for_host then
        dtpace.state, dtpace.for_host = nil, nil
    end
    if all then
        dtpace.beacons_skipped, dtpace.update_err = nil, nil
    end
    dtpace.fakes, dtpace.active, dtpace.cache, dtpace.failed = nil, {}, nil, nil
    dtpace.exited, dtpace.exit_i, dtpace.exit_t = false, nil, 0
end

-- 0.2.14 (user 2026-10-27): no enemies until the players leave the start building. The exit is the first main path
-- node of three in a row with open sky above it; quiet() holds Darktide's spawning, the VT2 patrols and the fallback
-- director until a player's nearest main path node is at or past it.
dtpace.exited, dtpace.exit_t = false, 0
-- 0.2.15 (user 2026-10-27, /bell debug "you are at VT2 -111,-52,-11": "debug is where enemies begin to spawn"): the spawn
-- start is this hand-placed spot; the main path node nearest it is the exit
dtpace.EXIT = { -111, -52, -11 }
function dtpace.find_exit()
    if dtpace.EXIT and Data.main_path and #Data.main_path > 0 then
        local e, best, bd = dtpace.EXIT, 1, math.huge
        for i, n in ipairs(Data.main_path) do
            local d = (n[1] - e[1]) ^ 2 + (n[2] - e[2]) ^ 2 + (n[3] - e[3]) ^ 2
            if d < bd then
                best, bd = i, d
            end
        end
        mod:info("spawn start at main path node %d of %d (%.1f m from VT2 %d, %d, %d)", best, #Data.main_path,
            math.sqrt(bd), e[1], e[2], e[3])
        return best
    end
    local world = level_world()
    local pw = world and World.physics_world(world)
    if not pw or not base_box or not Data.main_path then
        return nil
    end
    local run = 0
    for i = 1, #Data.main_path do
        -- down from high above: roof undersides have no collision (build_bell drops downward faces), so a ray up from
        -- the path never hits a roof; a roof is anything the ray meets 2.5 m or more above the path
        local p = W(Data.main_path[i])
        local ok, hit, hit_pos = pcall(PhysicsWorld.raycast, pw, p + Vector3(0, 0, 80), Vector3(0, 0, -1), 80,
            "closest", "collision_filter", "filter_player_mover")
        if not ok then
            return nil
        end
        local roofed = hit and hit_pos and Vector3.z(hit_pos) > Vector3.z(p) + 2.5 * MAP_SCALE
        run = roofed and 0 or run + 1
        if run >= 3 then
            local n = Data.main_path[i - 2]
            mod:info("start building exit at main path node %d of %d (VT2 %.1f, %.1f, %.1f)", i - 2, #Data.main_path, n[1], n[2], n[3])
            return i - 2
        end
    end
    return 1
end

function dtpace.quiet()
    return in_map() and not dtpace.exited
end

function dtpace.quiet_update(dt)
    if dtpace.exited then
        return
    end
    dtpace.exit_t = dtpace.exit_t - dt
    if dtpace.exit_t > 0 then
        return
    end
    dtpace.exit_t = 1
    dtpace.exit_i = dtpace.exit_i or dtpace.find_exit()
    if not dtpace.exit_i then
        return
    end
    for _, player in pairs(Managers.player:players()) do
        local u = player.player_unit
        if unit_ok(u) then
            local pos = Unit.world_position(u, 1)
            local best, bd = 1, math.huge
            for i = 1, #Data.main_path do
                local d = Vector3.distance_squared(pos, W(Data.main_path[i]))
                if d < bd then
                    best, bd = i, d
                end
            end
            -- 0.2.16 hotfix 5: a player still far off the path (not teleported in yet when the map is built) does not count
            if best >= dtpace.exit_i and bd < 400 then
                dtpace.exited = true
                mod:info("players left the start building (node %d): enemies can spawn", best)
                return
            end
        end
    end
end

-- 0.2.15 (user 2026-10-27: enemies in big open areas stay idle while I fight across the road): once a second, idle or
-- alerted minions within the aggro_range setting of a player are alerted twice (MinionPerceptionExtension.alert: passive
-- -> alerted with that player as target -> aggroed). Monsters and bosses are left to their own perception.
dtpace.aggro_t = 0
function dtpace.aggro_update(dt)
    dtpace.aggro_t = dtpace.aggro_t - dt
    local range = mod:get("aggro_range") or 35
    if dtpace.aggro_t > 0 or range <= 0 or dtpace.quiet() then
        return
    end
    dtpace.aggro_t = 1
    local players = {}
    for _, player in pairs(Managers.player:players()) do
        local u = player.player_unit
        if unit_ok(u) and HEALTH_ALIVE[u] then
            players[#players + 1] = u
        end
    end
    if #players == 0 then
        return
    end
    local r2 = (range * MAP_SCALE) ^ 2
    for unit in pairs(HEALTH_ALIVE) do
        local ext = ScriptUnit.has_extension(unit, "perception_system")
        local pc = ext and ext._perception_component
        local breed = ext and ext._breed
        if pc and breed and pc.aggro_state ~= "aggroed" and not (breed.tags and breed.tags.monster)
            and not breed.trigger_boss_health_bar_on_aggro then
            local pos = Unit.world_position(unit, 1)
            local best, bd = nil, r2
            for _, pu in ipairs(players) do
                local d = Vector3.distance_squared(pos, Unit.world_position(pu, 1))
                if d < bd then
                    best, bd = pu, d
                end
            end
            if best then
                pcall(ext.alert, ext, best, true)
                pcall(ext.alert, ext, best, true)
            end
        end
    end
end

-- host restore runs its occluded-point pass from mod.update even when the Bell is gone
function dtpace.update_host()
    if dtpace.state == "occluding" and dtpace.for_host then
        local ok, err = pcall(dtpace.occlude)
        if not ok then
            mod:error("host main path restore failed: %s", tostring(err))
            dtpace.state, dtpace.for_host = nil, nil
        end
    end
end

-- ---------------------------------------------------------------------------------------------------- VT2 navmesh, 1:1
-- The level's own navmesh (levels/honduras/bell world.nav_data: a Gameware "BlobAggFile 2.17.3", the same Gameware release
-- Darktide's gwnav plugin is built from) is loaded into a temporary nav world with GwNavGeneration.add_navdata_to_world (as
-- shared_nav.lua does with a path on disk), its triangles are read back with GwNavWorld.database_tile_count /
-- database_tile_triangle_count / database_triangle (as spawn_point_queries.lua reads a navmesh) and cached in
-- nav/bell_navmesh.txt. They are baked into Darktide's nav world at the map origin with GwNavGeneration.push_indexed_mesh, the way
-- bake_navmesh.lua bakes an Expedition level's nav_base triangles, with a 5 cm entity radius so the walkable area stays VT2's.
-- The bake is checked against the level's walkable points; a bad result is retried with the triangle winding flipped, and if
-- that fails too the tile bake above takes over.
local NAV_FILE = "../mods/QIangIQsBell/nav/bell.nav_data"
local NAV_CACHE = "../mods/QIangIQsBell/nav/bell_navmesh.txt"
local vt2nav = { state = "idle" }  -- idle | loading | extracting | ready_to_bake | baking | ready | failed

mod.vt2nav_state = function()
    return vt2nav.state
end

local function lua_io()
    local m = rawget(_G, "Mods")
    return m and m.lua and m.lua.io
end

-- The temporary world is never destroyed. 0.2.1 destroyed it and the game's own nav world crashed in its very next
-- kick_async_update (access violation in _Mtx_lock under gwnav); 0.2.0 ran init_async_update on it and the main thread hung.
-- The plugin evidently keeps one async-update state for all nav worlds, so a second world is left alone after the read
-- (about 2 MB for the session; only made when nav/bell_navmesh.txt is missing).
local kept_nav_worlds = {}

local function vt2nav_release_world()
    local nw = vt2nav.nw
    if nw then
        kept_nav_worlds[#kept_nav_worlds + 1] = nw
    end
    vt2nav.nw = nil
end

local nav_guard = { owned = false }   -- read / write / release below; one local (main chunk local limit)

local function vt2nav_fail(why)
    vt2nav_release_world()
    nav_guard.release("failed")
    mod:info("VT2NAV failed: %s; the runtime tile bake is used instead", tostring(why))
    if mod:get("verbose") then
        say("VT2 navmesh not used (%s); baking tiles instead", tostring(why))
    end
    vt2nav = { state = "failed", why = tostring(why) }
end

local function read_nav_cache()
    local lio = lua_io()
    local f = lio and lio.open(NAV_CACHE, "r")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    local verts, idx, nv, nt = {}, {}, nil, nil
    for line in s:gmatch("[^\n]+") do
        if not nv then
            local a, b = line:match("^BELLNAV 1 (%d+) (%d+)")
            if not a then
                return nil
            end
            nv, nt = tonumber(a), tonumber(b)
        elseif #verts < nv then
            local x, y, z = line:match("^(%S+) (%S+) (%S+)")
            verts[#verts + 1] = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 }
        else
            local a, b, c = line:match("^(%d+) (%d+) (%d+)")
            if a then
                idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = tonumber(a), tonumber(b), tonumber(c)
            end
        end
    end
    if not nv or nt == 0 or #verts ~= nv or #idx ~= nt * 3 then
        return nil
    end
    return verts, idx
end

local function write_nav_cache(verts, idx)
    local lio = lua_io()
    local f = lio and lio.open(NAV_CACHE, "w")
    if not f then
        return false
    end
    local out = { string.format("BELLNAV 1 %d %d", #verts, #idx / 3) }
    for _, v in ipairs(verts) do
        out[#out + 1] = string.format("%.3f %.3f %.3f", v[1], v[2], v[3])
    end
    for i = 1, #idx, 3 do
        out[#out + 1] = idx[i] .. " " .. idx[i + 1] .. " " .. idx[i + 2]
    end
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    return true
end

-- the guard file holds "loading" while the navdata is being read; it is set back only when that ends in this session
local NAV_GUARD = "../mods/QIangIQsBell/nav/bell_navmesh.guard"

function nav_guard.read()
    local lio = lua_io()
    local f = lio and lio.open(NAV_GUARD, "r")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s and s:match("^(%a+)")
end

function nav_guard.write(s)
    local lio = lua_io()
    local f = lio and lio.open(NAV_GUARD, "w")
    if f then
        f:write(s, "\n")
        f:close()
        nav_guard.owned = s == "loading" or s == "baking"
    end
end

nav_guard.release = function(s)
    if nav_guard.owned then
        pcall(nav_guard.write, s)
        nav_guard.owned = false
    end
end

local function vt2nav_start()
    if vt2nav.state ~= "idle" then
        return
    end
    if mod:get("vt2_navmesh_test") ~= true then
        vt2nav = { state = "failed", why = "off in the mod options" }
        return
    end
    -- guard: a read or bake that never finished last time (game hung or crashed) is not tried again
    local g = nav_guard.read()
    if g == "loading" or g == "baking" then
        vt2nav_fail("the last VT2 navmesh " .. (g == "loading" and "read" or "bake") .. " did not finish; delete nav/bell_navmesh.guard to try again")
        return
    end
    local verts, idx = read_nav_cache()
    if verts then
        vt2nav = { state = "ready_to_bake", verts = verts, idx = idx, src = "cache" }
        mod:info("VT2NAV: %d triangles from the cache", #idx / 3)
        return
    end
    local ok, err = pcall(function()
        local NW, Gen = rawget(_G, "GwNavWorld"), rawget(_G, "GwNavGeneration")
        if not (NW and Gen and Gen.add_navdata_to_world and NW.database_tile_count and NW.database_tile_triangle_count and NW.database_triangle) then
            error("the Gameware navdata calls are not in this game build")
        end
        local lio = lua_io()
        local f = lio and lio.open(NAV_FILE, "rb")
        if not f then
            error(NAV_FILE .. " is missing")
        end
        f:close()
        nav_guard.write("loading")
        -- a plain nav world as the editor's shared_nav.lua makes one: no init_async_update and no kick/join. 0.2.0 ran async
        -- updates on this second world next to the game's own and the main thread hung in the gwnav plugin (deadlock crash).
        local nw = NW.create()
        vt2nav = { state = "loading", nw = nw, t = 0, verts = {}, idx = {}, vkey = {}, tile = 1, tri = 0 }
        vt2nav.data = Gen.add_navdata_to_world(nw, NAV_FILE)
    end)
    if not ok then
        vt2nav_fail(err)
    end
end

local function vt2nav_vertex(s, v)
    local x, y, z = Vector3.x(v), Vector3.y(v), Vector3.z(v)
    local k = string.format("%d:%d:%d", math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5), math.floor(z * 100 + 0.5))
    local i = s.vkey[k]
    if not i then
        i = #s.verts + 1
        s.verts[i] = { x, y, z }
        s.vkey[k] = i
    end
    return i
end

local function vt2nav_update(dt)
    local s = vt2nav
    if s.state == "loading" then
        s.t = s.t + dt
        local ok, err = pcall(function()
            local n = GwNavWorld.database_tile_count(s.nw) or 0
            if n > 0 then
                s.stable = n == s.last_n and (s.stable or 0) + 1 or 0
                s.last_n = n
                if s.stable >= 3 then
                    s.state, s.tiles = "extracting", n
                    mod:info("VT2NAV: navdata loaded, %d tiles", n)
                    return
                end
            end
        end)
        if not ok then
            vt2nav_fail(err)
        elseif s.state == "loading" and s.t > 15 then
            vt2nav_fail("the navdata did not load within 15 s")
        end
    elseif s.state == "extracting" then
        local ok, err = pcall(function()
            local budget = 2500
            local temp = Script.temp_byte_count()
            while budget > 0 and s.tile <= s.tiles do
                local cnt = s.tile_cnt or GwNavWorld.database_tile_triangle_count(s.nw, s.tile) or 0
                s.tile_cnt = cnt
                while s.tri < cnt and budget > 0 do
                    s.tri = s.tri + 1
                    budget = budget - 1
                    local a, b, c = GwNavWorld.database_triangle(s.nw, s.tile, s.tri)
                    local ia, ib, ic = 0, 0, 0
                    if a and b and c then
                        ia, ib, ic = vt2nav_vertex(s, a), vt2nav_vertex(s, b), vt2nav_vertex(s, c)
                    end
                    if ia ~= ib and ib ~= ic and ia ~= ic then
                        local n = #s.idx
                        s.idx[n + 1], s.idx[n + 2], s.idx[n + 3] = ia, ib, ic
                    end
                    Script.set_temp_byte_count(temp)
                end
                if s.tri >= cnt then
                    s.tile, s.tri, s.tile_cnt = s.tile + 1, 0, nil
                end
            end
            Script.set_temp_byte_count(temp)
        end)
        if not ok then
            vt2nav_fail(err)
            return
        end
        if s.tile > s.tiles then
            vt2nav_release_world()
            if #s.idx < 300 then
                vt2nav_fail(string.format("only %d triangles in the navdata", #s.idx / 3))
                return
            end
            s.vkey = nil
            nav_guard.release("ok")
            local cached = pcall(write_nav_cache, s.verts, s.idx)
            s.state, s.src = "ready_to_bake", "nav_data"
            mod:info("VT2NAV: %d triangles, %d vertices read from the navdata (cache written: %s)", #s.idx / 3, #s.verts, tostring(cached))
        end
    end
end

local function vt2nav_bake()
    local s = vt2nav
    local ok, err = pcall(function()
        local Gen = GwNavGeneration
        local world, nw = level_world(), nav_world()
        if not (world and nw and base_box) then
            error("no nav world or map yet")
        end
        local b = base_box:unbox()
        local verts, idx = s.verts, s.idx
        if s.flip then
            local f = {}
            for i = 1, #idx, 3 do
                f[i], f[i + 1], f[i + 2] = idx[i], idx[i + 2], idx[i + 1]
            end
            idx = f
        end
        local nav_gen = Gen.create(world)
        local temp = Script.temp_byte_count()
        -- explicit triangles, not push_indexed_mesh: 0.2.1 crashed in finish_async_generation after an indexed push, and the
        -- index base push_indexed_mesh expects is not documented
        do
            Gen.begin_push_triangle(nav_gen)
            for i = 1, #idx, 3 do
                local A, B, C = verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]
                Gen.push_triangle(nav_gen, b + Vector3(A[1], A[2], A[3]) * MAP_SCALE, b + Vector3(B[1], B[2], B[3]) * MAP_SCALE, b + Vector3(C[1], C[2], C[3]) * MAP_SCALE)
                Script.set_temp_byte_count(temp)
            end
        end
        -- seeds: one triangle centre per 6 m cell, so every piece of VT2's navmesh is kept
        local cells, nseeds = {}, 0
        for i = 1, #idx, 3 do
            local A, B, C = verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]
            local cx, cy, cz = (A[1] + B[1] + C[1]) / 3, (A[2] + B[2] + C[2]) / 3, (A[3] + B[3] + C[3]) / 3
            local key = math.floor(cx / 6) .. ":" .. math.floor(cy / 6) .. ":" .. math.floor(cz / 3)
            if not cells[key] then
                cells[key] = true
                Gen.push_seed_point(nav_gen, b + Vector3(cx, cy, cz) * MAP_SCALE + Vector3(0, 0, 0.05))
                nseeds = nseeds + 1
                Script.set_temp_byte_count(temp)
            end
        end
        local settings = {
            altitude_tolerance = 0.5, atomic_consume_units = true, cell_size = 3, consume_terrain = true,
            database_index = 0, entity_height = 1.6, entity_radius = 0.3, height_field_sampling = 1,
            min_navigable_surface = 0.5, output_type = 1, raster_precision = 0.1, sector_name = "world",
            slope_max = 60, step_max = 0.5, sector_id = math.uuid(),
        }
        nav_guard.write("baking")
        Managers.state.nav_mesh:set_async_paused(true)
        local job_id = Gen.generate_async(nav_gen, nw, settings, { [math.uuid()] = "BellVT2Nav" })
        Gen.destroy(nav_gen)
        navbake = { job_id = job_id, t = 0, chunks = 0, seeds = nseeds, vt2 = true }
        s.state = "baking"
        mod:info("VT2NAV: baking %d triangles (%s, winding %s), %d seeds", #idx / 3, tostring(s.src), s.flip and "flipped" or "as read", nseeds)
    end)
    if not ok then
        pcall(function() Managers.state.nav_mesh:set_async_paused(false) end)
        vt2nav_fail(err)
    end
end

local function vt2nav_coverage()
    local NavQueries = require("scripts/utilities/nav_queries")
    local nw = nav_world()
    local list = Data.walkable or {}
    local hits, n = 0, 0
    local step = math.max(1, math.floor(#list / 60))
    for i = 1, #list, step do
        n = n + 1
        if NavQueries.position_on_mesh(nw, W(list[i]), 1.5, 1.5) then
            hits = hits + 1
        end
    end
    return hits, n
end

-- nav tag volumes (VT2 NO_BOTS / NO_SPAWN, NavMeshManager.add_nav_tag_volume) and the sealed first wall; re-added after every bake
-- so the new navdata is tagged too. Layers "20" and "21" closed the boss doors in VT2; those doors are not in the map.
local NAVTAG = {
    no_spawn = { layer = "NO_SPAWN", type = "content/volume_types/nav_tag_volumes/no_spawn" },
    no_bots = { layer = "NO_BOTS", type = "content/volume_types/nav_tag_volumes/bot_impassable" },
}
local WALL_LAYER = "BELL_WALL"
local tag_vols = {}
local wall_vol = nil

local tag_world = nil   -- the nav world the volumes were added to (they are only removed from that same world)

local function clear_nav_tags()
    local nm = Managers.state and Managers.state.nav_mesh
    if nm and tag_world and nav_world() == tag_world then
        for _, v in ipairs(tag_vols) do
            pcall(nm.remove_nav_tag_volume, nm, v)
        end
    end
    tag_vols, wall_vol, tag_world = {}, nil, nil
end

local function add_nav_tags()
    clear_nav_tags()
    local nm = Managers.state and Managers.state.nav_mesh
    if not (nm and base_box and is_server()) then
        return
    end
    tag_world = nav_world()
    local b = base_box:unbox()
    local bz = Vector3.z(b)
    for _, v in ipairs(Extra.data.nav or {}) do
        local def = NAVTAG[v.kind]
        if def then
            local pts = {}
            for _, p in ipairs(v.pts) do
                pts[#pts + 1] = b + Vector3(p[1], p[2], p[3]) * MAP_SCALE
            end
            local ok, vol = pcall(nm.add_nav_tag_volume, nm, pts, bz + v.amin * MAP_SCALE, bz + v.amax * MAP_SCALE, def.layer, true, def.type)
            if ok and vol then
                tag_vols[#tag_vols + 1] = vol
            else
                mod:info("nav tag volume %s failed: %s", tostring(v.name), tostring(vol))
            end
        end
    end
    if Data.wall and named["bc_wall"] and not wall_broken then
        local w = Data.wall
        local pts = {
            W({ w[1] - 3.5, w[2] - 3.5, w[3] }), W({ w[1] + 3.5, w[2] - 3.5, w[3] }),
            W({ w[1] + 3.5, w[2] + 3.5, w[3] }), W({ w[1] - 3.5, w[2] + 3.5, w[3] }),
        }
        local ok, vol = pcall(nm.add_nav_tag_volume, nm, pts, bz + (w[3] - 3) * MAP_SCALE, bz + (w[3] + 6) * MAP_SCALE, WALL_LAYER, false)
        if ok and vol then
            wall_vol = vol
            tag_vols[#tag_vols + 1] = vol
        end
    end
end

local function remove_wall_tag()
    local nm = Managers.state and Managers.state.nav_mesh
    if wall_vol and nm and nav_world() == tag_world then
        pcall(nm.remove_nav_tag_volume, nm, wall_vol)
        for i = #tag_vols, 1, -1 do
            if tag_vols[i] == wall_vol then
                table.remove(tag_vols, i)
            end
        end
    end
    wall_vol = nil
end

-- bots keep out of NO_BOTS, minions out of the standing wall (per navigation extension, as NavMeshManager.set_allowed_nav_tag_layer
-- does; that function itself is not used because it sends an RPC clients without the layer would reject)
local layer_t = 0
local function update_layer_rules(dt)
    layer_t = layer_t - dt
    if layer_t > 0 or #tag_vols == 0 then
        return
    end
    layer_t = 2
    pcall(function()
        local nav_system = Managers.state.extension:system("navigation_system")
        for unit, ext in pairs(nav_system:unit_to_extension_map()) do
            if ext.allow_nav_tag_layer then
                if ext.__class_name == "BotNavigationExtension" then
                    pcall(ext.allow_nav_tag_layer, ext, "NO_BOTS", false)
                elseif wall_vol then
                    pcall(ext.allow_nav_tag_layer, ext, WALL_LAYER, false)
                end
            end
        end
    end)
end

-- inside a VT2 NO_SPAWN volume (level coordinates)
local function in_no_spawn(l)
    local x, y, z = Vector3.x(l), Vector3.y(l), Vector3.z(l)
    for _, v in ipairs(Extra.data.nav or {}) do
        if v.kind == "no_spawn" and z >= v.amin - 1 and z <= v.amax + 1 then
            local pts, inside, j = v.pts, false, #v.pts
            for i = 1, #pts do
                local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
                if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
                    inside = not inside
                end
                j = i
            end
            if inside then
                return true
            end
        end
    end
    return false
end

mod.on_bake_done = function(vt2)
    if vt2 and vt2nav.state == "baking" then
        local hits, n = vt2nav_coverage()
        mod:info("VT2NAV: %d of %d walkable points are on the new navmesh", hits, n)
        if n > 0 and hits * 2 < n then
            if not vt2nav.flip then
                vt2nav.flip, vt2nav.state = true, "ready_to_bake"
                return
            end
            vt2nav_fail(string.format("only %d of %d walkable points on the baked navmesh", hits, n))
        else
            vt2nav.state = "ready"
            nav_guard.release("ok")
            if mod:get("verbose") then
                say("VT2 navmesh ready (%d of %d test points)", hits, n)
            end
        end
    end
    add_nav_tags()
end

mod.on_bake_failed = function(err)
    if vt2nav.state == "baking" then
        vt2nav_fail(err)
    end
end

local function update_vt2nav(dt)
    if not is_server() then
        return
    end
    if vt2nav.state == "idle" then
        vt2nav_start()
    elseif vt2nav.state == "loading" or vt2nav.state == "extracting" then
        vt2nav_update(dt)
    elseif vt2nav.state == "ready_to_bake" and not navbake then
        vt2nav_bake()
    end
    update_layer_rules(dt)
end

local function reset_vt2nav()
    vt2nav_release_world()
    nav_guard.release("idle")
    -- the extracted triangles stay for the next map build in this session
    if vt2nav.verts and vt2nav.idx and vt2nav.state ~= "loading" and vt2nav.state ~= "extracting" then
        vt2nav = { state = "ready_to_bake", verts = vt2nav.verts, idx = vt2nav.idx, src = vt2nav.src, flip = vt2nav.flip }
    else
        vt2nav = { state = "idle" }
    end
    clear_nav_tags()
end

-- ---------------------------------------------------------------------------------------------------- minions
-- VT2 breed -> Darktide breed (each entry is a list; units alternate through it). The names are breeds from
-- scripts/settings/breed/breeds.lua.
local BREEDS = {
    skaven_slave = { "chaos_poxwalker" },
    skaven_clan_rat = { "cultist_melee", "renegade_melee" },
    skaven_clan_rat_with_shield = { "cultist_vanguard" },
    skaven_storm_vermin_commander = { "renegade_executor", "cultist_berzerker" },
    skaven_plague_monk = { "cultist_berzerker" },
    skaven_poison_wind_globadier = { "chaos_poxwalker_bomber" },
    skaven_pack_master = { "renegade_netgunner" },
    skaven_gutter_runner = { "chaos_hound" },
    skaven_ratling_gunner = { "renegade_gunner" },
    skaven_rat_ogre = { "chaos_plague_ogryn" },
    skaven_stormfiend = { "chaos_beast_of_nurgle" },
    chaos_spawn = { "chaos_spawn" },
}
local PATROL_BREEDS = { "skaven_clan_rat", "skaven_clan_rat", "skaven_storm_vermin_commander", "skaven_clan_rat" }
local PATROL_SIZE = 6
-- 0.2.7: the spawn director (specials, and Havoc-sized packs, hordes and patrols on Auric); filled in after pick_spawners
local director = { packs_done = {}, t = 0 }
local ROAM_ACTIVATE = 65
local BOSS_ACTIVATE = 90
local PICKUP_ACTIVATE = 90

local rng_state = 0
local function rnd(a, b)
    rng_state = (rng_state * 1103515245 + 12345) % 2147483648
    local r = rng_state / 2147483648
    if a == nil then
        return r
    elseif b == nil then
        return math.floor(r * a) + 1
    end
    return a + math.floor(r * (b - a + 1))
end

local jobs = {}            -- spawn jobs: { pos = Vector3Box (world), vt2 = VT2 breed name, n = counter, tries, wait, aggro, tag }
local tracked = {}         -- spawned minions: unit -> { vt2, tag, aggro }
local counts = { spawned = 0, dropped = 0, queued = 0 }
local jobs_t = 0

local function spawn_job(world_pos, vt2_breed, opts)
    counts.queued = counts.queued + 1
    jobs[#jobs + 1] = { pos = Vector3Box(world_pos), vt2 = vt2_breed, n = counts.queued, tries = 0, wait = 0,
        aggro = opts and opts.aggro, tag = opts and opts.tag, floor = opts and opts.floor, dt = opts and opts.dt }
    jobs[#jobs].wait = opts and opts.wait or 0
end

-- The Bell's Rat Ogre is a custom Plague Ogryn. At the top difficulty (6, Havoc 40) it has 140000 health and attacks at 2x speed;
-- lower difficulties scale down along Darktide's own tables: health follows the monster health steps of
-- minion_difficulty_settings (x1, 1.25, 1.5, 2, 3 per challenge) with Havoc's +70 percent monster health on top for step 6
-- (3 x 1.7 = 5.1), attack speed follows the havoc_melee_attack_speed_01..05 buffs (+0.2, 0.35, 0.5, 0.75, 1.0).
local OGRE_HP_AT_TOP = 140000
local OGRE_HP_STEPS = { 1, 1.25, 1.5, 2, 3, 5.1 }
local OGRE_ATTACK_BUFFS = { false, "havoc_melee_attack_speed_01", "havoc_melee_attack_speed_02", "havoc_melee_attack_speed_03",
    "havoc_melee_attack_speed_04", "havoc_melee_attack_speed_05" }

local function ogre_stats()
    local t = math.max(1, math.min(#OGRE_HP_STEPS, mod:get("difficulty") or 5))
    return OGRE_HP_AT_TOP * OGRE_HP_STEPS[t] / OGRE_HP_STEPS[#OGRE_HP_STEPS], OGRE_ATTACK_BUFFS[t], t
end

local function try_spawn(job)
    local NavQueries = require("scripts/utilities/nav_queries")
    local nw = nav_world()
    local pos = job.pos:unbox()
    if job.floor then
        local g = ground_below(pos, 2, 10)
        if g then
            pos = g
        end
    end
    local mesh_pos = nw and NavQueries.position_on_mesh(nw, pos, 3, 3) or nil
    if not mesh_pos then
        return false
    end
    local list = job.dt and { job.dt } or BREEDS[job.vt2] or BREEDS.skaven_clan_rat   -- dt: a Darktide breed (director)
    local breed = list[(job.n % #list) + 1]
    local side = Managers.state.extension:system("side_system"):get_side_from_name("villains")
    local rot = Quaternion.look(Vector3(rnd() - 0.5, rnd() - 0.5, 0), Vector3.up())
    local ogre_hp, ogre_buff, ogre_tier
    local param
    if job.vt2 == "skaven_rat_ogre" then
        ogre_hp, ogre_buff, ogre_tier = ogre_stats()
        local base = Managers.state.difficulty:get_minion_max_health(breed)
        param = Managers.state.minion_spawn:request_param_table()
        param.optional_health_modifier = ogre_hp / base
    end
    local unit = Managers.state.minion_spawn:spawn_minion(breed, mesh_pos, rot, side.side_id, param)
    if not unit then
        return false
    end
    if ogre_hp then
        if ogre_buff then
            local ok, err = pcall(function()
                local buffs = ScriptUnit.extension(unit, "buff_system")
                buffs:add_internally_controlled_buff(ogre_buff, Managers.time:time("gameplay"))
            end)
            if not ok then
                mod:error("ogre attack speed buff failed: %s", tostring(err))
            end
        end
        mod:info("OGRE tier %d: %.0f health, attack speed buff %s", ogre_tier, ogre_hp, tostring(ogre_buff))
    end
    tracked[unit] = { vt2 = job.vt2, tag = job.tag, aggro = job.aggro, breed = breed }
    counts.spawned = counts.spawned + 1
    if job.aggro then
        local pe = ScriptUnit.has_extension(unit, "perception_system")
        if pe and pe.aggro then
            pcall(pe.aggro, pe)
        end
    end
    return true
end

local function process_jobs(dt)
    if #jobs == 0 then
        return
    end
    local budget = 3
    for i = #jobs, 1, -1 do
        local job = jobs[i]
        job.wait = job.wait - dt
        if job.wait <= 0 then
            budget = budget - 1
            local ok, res = pcall(try_spawn, job)
            if ok and res then
                table.remove(jobs, i)
            else
                if not ok then
                    mod:error("spawn failed (%s): %s", tostring(job.vt2), tostring(res))
                    job.tries = job.tries + 5
                end
                job.tries = job.tries + 1
                job.wait = 3
                want_bake(job.pos:unbox())
                if job.tries > 25 then
                    counts.dropped = counts.dropped + 1
                    table.remove(jobs, i)
                    if counts.dropped == 1 then
                        say("some enemies found no navmesh and were dropped (see /bell debug)")
                    end
                end
            end
            if budget <= 0 then
                break
            end
        end
    end
end

local function alive_count(vt2, tag)
    local n = 0
    for unit, rec in pairs(tracked) do
        if (not vt2 or rec.vt2 == vt2) and (not tag or rec.tag == tag) then
            if unit_ok(unit) and HEALTH_ALIVE[unit] then
                n = n + 1
            else
                tracked[unit] = nil
            end
        end
    end
    for _, job in ipairs(jobs) do
        if (not vt2 or job.vt2 == vt2) and (not tag or job.tag == tag) then
            n = n + 1
        end
    end
    return n
end

local function player_positions()
    local out = {}
    local players = Managers.player and Managers.player:human_players() or {}
    for _, player in pairs(players) do
        local pu = player.player_unit
        if unit_ok(pu) and HEALTH_ALIVE[pu] then
            out[#out + 1] = Unit.world_position(pu, 1)
        end
    end
    return out
end

local function nearest_flat(pos, list)
    local best, bd = nil, math.huge
    for _, q in ipairs(list) do
        local d = flat_dist(q, pos)
        if d < bd then
            best, bd = q, d
        end
    end
    return best, bd
end

-- minions that stood still while a player is far away are moved toward the players (runtime navmesh is a patchwork)
local nudge_t = 0
local nudge_last = setmetatable({}, { __mode = "k" })
local function nudge_stuck(dt)
    nudge_t = nudge_t - dt
    if nudge_t > 0 or mod:get("nudge_stuck") == false then
        return
    end
    nudge_t = 2.5
    local NavQueries = require("scripts/utilities/nav_queries")
    local nw = nav_world()
    local ppos = player_positions()
    if not nw or #ppos == 0 then
        return
    end
    for unit, rec in pairs(tracked) do
        if rec.aggro and unit_ok(unit) and HEALTH_ALIVE[unit] then
            local p = Unit.world_position(unit, 1)
            local best, bd = nearest_flat(p, ppos)
            local r = nudge_last[unit]
            if not r then
                r = { pos = Vector3Box(p), still = 0 }
                nudge_last[unit] = r
            end
            local moved = Vector3.length(p - r.pos:unbox())
            r.pos:store(p)
            if moved < 1 and bd > 30 and bd < 400 then
                r.still = r.still + 2.5
            else
                r.still = 0
            end
            if r.still >= 5 then
                r.still = 0
                local dir = Vector3.normalize(Vector3.flat(best - p))
                local target = p + dir * math.min(24, bd - 30)
                local mp = NavQueries.position_on_mesh(nw, target, 12, 12)
                if mp and in_no_spawn(to_level(mp)) then
                    mp = nil -- never pop a minion into a VT2 NO_SPAWN volume
                end
                local loco = mp and ScriptUnit.has_extension(unit, "locomotion_system")
                if loco then
                    loco:teleport_to(mp, Quaternion.look(dir, Vector3.up()))
                end
            end
        elseif not (unit_ok(unit) and HEALTH_ALIVE[unit]) then
            tracked[unit] = nil
        end
    end
end

-- ---------------------------------------------------------------------------------------------------- pickups
-- VT2 LevelSettings.bell.pickup_settings.default (primary + secondary), VT2 pickup type -> Darktide pickup name.
-- Placed on the level's 148 pickup spawner units, spread along the main path (VT2 spreads by percentage_through_level) and
-- spawned when a player comes within PICKUP_ACTIVATE m (pickup_system:spawn_pickup, pickup_system.lua:944).
local PICKUP_PLAN = {
    { "small_clip", 6 }, { "large_clip", 6 },            -- ammo 6 + 6
    { "small_grenade", 11 },                             -- grenades 6 + 5
    { "medical_crate_pocketable", 10 },                  -- healing: first_aid_kit 5 + secondary healing 5
    { "medical_crate_deployable", 5 },                   -- healing_draught 5
    { "syringe_power_boost_pocketable", 3 }, { "syringe_speed_boost_pocketable", 3 },
    { "syringe_ability_boost_pocketable", 3 }, { "syringe_corruption_pocketable", 2 }, -- potions 6 + 5
    { "expedition_explosive_luggable_01", 4 },           -- level_events explosive_barrel 4
}

local pickups = nil -- { { pos = Vector3Box (level), name, done, cool } }

local function path_progress(p)
    local best, bd = 0, math.huge
    for _, n in ipairs(Data.main_path) do
        local d = (n[1] - p[1]) ^ 2 + (n[2] - p[2]) ^ 2 + (n[3] - p[3]) ^ 2
        if d < bd then
            best, bd = n[4], d
        end
    end
    return best
end

local function build_pickups()
    pickups = {}
    local spawners = {}
    for i, p in ipairs(Data.pickups) do
        spawners[i] = { p = p, d = path_progress(p) }
    end
    table.sort(spawners, function(a, b) return a.d < b.d end)
    local items = {}
    for _, row in ipairs(PICKUP_PLAN) do
        for _ = 1, row[2] do
            items[#items + 1] = row[1]
        end
    end
    for i = #items, 2, -1 do
        local j = rnd(i)
        items[i], items[j] = items[j], items[i]
    end
    local n = math.min(#items, #spawners)
    for i = 1, n do
        local idx = math.max(1, math.min(#spawners, math.floor((i - 0.5) * #spawners / n + 0.5)))
        local s = spawners[idx]
        pickups[#pickups + 1] = { pos = Vector3Box(v3(s.p)), name = items[i], done = false, cool = 0 }
        s.used = true
    end
    -- the start kit for the sealed wall: a mine to plant, the explosive luggable and grenades, on the path before the wall
    local a, b = Data.main_path[2], Data.main_path[3]
    if a and b and Data.wall then
        local kit = {
            { "motion_detection_mine_explosive_pocketable", a[1] + 1.2, a[2], a[3] },
            { "expedition_explosive_luggable_01", a[1] - 1.2, a[2], a[3] },
            { "small_grenade", b[1] + 1, b[2] + 1, b[3] },
            { "small_grenade", b[1] - 1, b[2] - 1, b[3] },
        }
        for _, k in ipairs(kit) do
            pickups[#pickups + 1] = { pos = Vector3Box(Vector3(k[2], k[3], k[4])), name = k[1], done = false, cool = 0 }
        end
    end
end

local function update_pickups(here, dt)
    if not pickups or mod:get("pickups") == false then
        return
    end
    local lh = to_level(here)
    for _, pk in ipairs(pickups) do
        if not pk.done then
            pk.cool = math.max(0, pk.cool - dt)
            local lp = pk.pos:unbox()
            if pk.cool <= 0 and Vector3.length(lh - lp) < PICKUP_ACTIVATE then
                pk.cool = 8
                local ok, err = pcall(function()
                    local sys = Managers.state.extension:system("pickup_system")
                    local wp = base_box:unbox() + lp * MAP_SCALE
                    local gp = ground_below(wp, 2.5, 8)
                    if not gp then
                        return -- ground not there yet; retried
                    end
                    local rot = Quaternion(Vector3.up(), math.rad(rnd(0, 359)))
                    local unit = sys:spawn_pickup(pk.name, gp + Vector3(0, 0, 0.25), rot)
                    if unit then
                        pk.done = true
                    end
                end)
                if not ok then
                    pk.done = true
                    mod:error("pickup %s failed: %s", pk.name, tostring(err))
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------- patrols and bosses
local roams = nil   -- { { id, pts (level), center (level Vector3Box), spawned } }
local bosses = nil  -- { { pos (level), vt2, spawned } }
local OGRE_SPAWNER = nil

local function nearest_in(list, p)
    local best, bd = nil, math.huge
    for i, q in ipairs(list) do
        local d = (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2
        if d < bd then
            best, bd = i, d
        end
    end
    return best
end

local function build_gameplay()
    rng_state = (mod:get("seed") or (os and os.time and os.time()) or 12345) % 2147483648
    build_pickups()
    roams = {}
    for _, r in ipairs(Data.patrols) do
        local sx, sy, sz = 0, 0, 0
        for _, p in ipairs(r.pts) do
            sx, sy, sz = sx + p[1], sy + p[2], sz + p[3]
        end
        local n = #r.pts
        roams[#roams + 1] = { id = r.id, pts = r.pts, center = Vector3Box(Vector3(sx / n, sy / n, sz / n)), spawned = false }
    end
    -- hand-placed bosses (LevelSettings.bell.boss_spawning_method = "hand_placed"): the spawner nearest the lever is the
    -- canyon_ogre_boss spawner; 3 of the other boss spawners get a boss from VT2's boss list
    local spawners = Data.boss_spawners
    local ogre_i = nearest_in(spawners, Data.lever)
    OGRE_SPAWNER = spawners[ogre_i]
    local others = {}
    for i, p in ipairs(spawners) do
        if i ~= ogre_i then
            others[#others + 1] = p
        end
    end
    for i = #others, 2, -1 do
        local j = rnd(i)
        others[i], others[j] = others[j], others[i]
    end
    local pool = { "skaven_rat_ogre", "skaven_stormfiend", "chaos_spawn" }
    bosses = {}
    for i = 1, math.min(3, #others) do
        bosses[#bosses + 1] = { pos = others[i], vt2 = pool[(i - 1) % #pool + 1], spawned = false }
    end
end

local function update_roams(here, dt)
    if not roams or mod:get("patrols") == false then
        return
    end
    local lh = to_level(here)
    for _, r in ipairs(roams) do
        if not r.spawned and Vector3.length(Vector3.flat(lh - r.center:unbox())) < ROAM_ACTIVATE then
            r.spawned = true
            local size = director.patrol_size and director.patrol_size() or PATROL_SIZE
            for i = 1, size do
                local p = r.pts[((i - 1) * 2) % #r.pts + 1]
                local wp = W(p) + Vector3(rnd() * 3 - 1.5, rnd() * 3 - 1.5, 0)
                if i > PATROL_SIZE then
                    -- the Havoc-sized part of the patrol: Darktide roamers with elites mixed in
                    spawn_job(wp, "skaven_clan_rat", { tag = "patrol", floor = true, dt = director.pick("roam") })
                else
                    spawn_job(wp, PATROL_BREEDS[(i - 1) % #PATROL_BREEDS + 1], { tag = "patrol", floor = true })
                end
            end
            mod:info("PATROL %s spawned %d", r.id, size)
        end
    end
end

local function update_bosses(here, dt)
    if not bosses or mod:get("bosses") == false then
        return
    end
    local lh = to_level(here)
    for _, b in ipairs(bosses) do
        if not b.spawned and Vector3.length(Vector3.flat(lh - v3(b.pos))) < BOSS_ACTIVATE then
            b.spawned = true
            spawn_job(W(b.pos), b.vt2, { tag = "boss", floor = true })
            mod:info("BOSS %s at %.0f,%.0f", b.vt2, b.pos[1], b.pos[2])
            say("a boss is nearby")
        end
    end
end

-- ---------------------------------------------------------------------------------------------------- events
-- terror_events_bell.lua, step by step. Steps VT2 uses for its own bookkeeping (set_master_event_running,
-- control_specials, control_pacing, disable_kick, set_freeze_condition, time challenges) have no counterpart here: pacing is
-- held off in the map anyway. difficulty_requirement values are terror_event_utils.lua (HARDER 4, HARDEST 5, CATACLYSM 6) and
-- are compared with the option "difficulty"; that option also picks the horde composition tier.
-- ---------------------------------------------------------------------------------------------------- comms (VT2 hero dialogue)
-- The Bell has no handler or narrator: its voice lines are the five heroes' level_talk lines (bell_vo.lua). VT2 plays them when a hero
-- looks at one of the 14 point_of_interest eyes, on level events (bell chime, horde, effect, destroyed, falling, exit) and as an intro
-- chain. Here each one shows in the mission-speaker popup on the right of the screen (name + voice bars) with the subtitle as a
-- notification. There is no audio: the VT2 voice files are not in Darktide.
local comm_cur, comm_queue, comm_gap, comm_last, eye_seen, eye_t = nil, {}, 0, {}, {}, 0
local COMM_NAME = "qiangiq_comm"

-- The speaking hero's VT2 unit-frame portrait in the popup (medium_unit_frame_portrait_* from VT2's gui_hud_atlas, compiled as
-- the asset bell_portraits by make_portraits.py; material i holds HEROES[hero] = i). One local (main chunk local limit).
local portraits = { ticket = nil, ready = false,
    HEROES = { dwarf_ranger = 0, wood_elf = 1, empire_soldier = 2, witch_hunter = 3, bright_wizard = 4 } }

function portraits.request()
    if portraits.ticket ~= nil or mod:get("portraits") == false then
        return
    end
    custom_assets = custom_assets or get_mod("CustomAssets")
    if not (custom_assets and custom_assets.acquire) then
        return
    end
    local id = "QIangIQsBell:bell_portraits"
    local ok, t = pcall(custom_assets.acquire, mod, id, function(_, _, load_error)
        portraits.ready = not load_error
        if load_error then
            mod:info("hero portraits failed to load: %s (run the custom assets patcher with the game closed)", tostring(load_error))
        end
    end, { reference_name = id })
    portraits.ticket = ok and t or false
end

function portraits.icon(hero)
    local i = portraits.ready and mod:get("portraits") ~= false and portraits.HEROES[hero]
    return i and ("content/mods/qiangiq_bell/bell_portraits_material_" .. i .. "_bc") or nil
end

local function reset_comms()
    comm_cur, comm_queue, comm_gap, comm_last, eye_seen, eye_t = nil, {}, 1, {}, {}, 0
    portraits.request()
end

local function pick_line(tag)
    local list = VO.lines[tag]
    if not list or #list == 0 then
        return nil
    end
    for _ = 1, 6 do
        local l = list[rnd(#list)]
        if not comm_last[l.id] then
            comm_last[l.id] = true
            return l
        end
    end
    comm_last = {}
    return list[rnd(#list)]
end

-- shared = an event line the Realms host also sends to clients (bell_extra.lua sync); intro and eye lines stay local
local function queue_comm(tag, delay, shared)
    comm_queue[#comm_queue + 1] = { tag = tag, wait = delay or 0, shared = shared }
end

local function show_comm(line)
    local name = VO.heroes[line.hero] or line.hero
    -- the VT2 voice clip plays with the popup (bell_extra.lua); the popup stays up for the clip, or for the text length without one
    local dur = Extra.play_vo(line.id)
    comm_cur = { name = name, left = dur and (dur + 0.4) or math.max(3, math.min(9, #line.text / 14)), shown = false,
        icon = portraits.icon(line.hero) }
    local ok = pcall(function()
        Managers.event:trigger("event_add_notification_message", "default", name .. ": " .. line.text)
    end)
    if not ok then
        say("%s: %s", name, line.text)
    end
end

-- a line the Realms host showed (SyncChannel): queued as the exact line, after whatever is playing now
local function show_comm_id(id)
    local line = LINE_BY_ID[id]
    if line then
        comm_queue[#comm_queue + 1] = { line = line, wait = 0 }
    end
end

local function update_comms(dt, here)
    if mod:get("voice_lines") == false then
        return
    end
    if comm_cur then
        comm_cur.left = comm_cur.left - dt
        if comm_cur.left <= 0 then
            comm_cur = nil
            comm_gap = 2
        end
    end
    comm_gap = comm_gap - dt
    for i = #comm_queue, 1, -1 do
        comm_queue[i].wait = comm_queue[i].wait - dt
    end
    if comm_cur or comm_gap > 0 then
        return
    end
    for i, q in ipairs(comm_queue) do
        if q.wait <= 0 then
            table.remove(comm_queue, i)
            local line = q.line or pick_line(q.tag)
            if line then
                show_comm(line)
                if q.shared then
                    Extra.publish("c:" .. line.id)
                end
            end
            return
        end
    end
    eye_t = eye_t - dt
    if eye_t > 0 or not here then
        return
    end
    eye_t = 0.25
    local player = local_player()
    local pu = player and player.player_unit
    if not unit_ok(pu) then
        return
    end
    local l = to_level(here)
    local fwd = Vector3.flat(Quaternion.forward(Unit.world_rotation(pu, 1)))
    if Vector3.length(fwd) < 0.01 then
        return
    end
    fwd = Vector3.normalize(fwd)
    for i, e in ipairs(VO.eyes) do
        if not eye_seen[i] then
            local d = Vector3(e[1], e[2], e[3]) - l
            local flat = Vector3.flat(d)
            local dist = Vector3.length(flat)
            if dist < 32 and math.abs(Vector3.z(d)) < 14 and dist > 0.5 and Vector3.dot(fwd, flat / dist) > 0.8 then
                eye_seen[i] = true
                local line = pick_line(e[4])
                if line then
                    show_comm(line)
                    return
                end
            end
        end
    end
end

-- 0.2.16 hotfix 5: hook_require can run this callback again for the same class table (DMF logged "Attempting to
-- rehook active hook"), so the hook is put on once per table.
mod:hook_require("scripts/ui/hud/elements/mission_speaker_popup/hud_element_mission_speaker_popup", function(Popup)
    if rawget(Popup, "__qiangiq_bell_speaker") then
        return
    end
    rawset(Popup, "__qiangiq_bell_speaker", true)
    mod:hook(Popup, "_sync_active_speaker", function(func, self, ...)
        local c = comm_cur
        if c then
            if not c.shown then
                c.shown = true
                self._speaker_name = COMM_NAME
                self:_mission_speaker_start(c.name, c.icon)
                self._is_speaking = true
            end
            return
        end
        if self._speaker_name == COMM_NAME then
            self._speaker_name = nil
            self:_mission_speaker_stop()
            self._is_speaking = false
        end
        return func(self, ...)
    end)
end)

local SPECIALS_A = { "skaven_poison_wind_globadier", "skaven_pack_master", "skaven_gutter_runner" }
local SPECIALS_B = { "skaven_poison_wind_globadier", "skaven_pack_master", "skaven_gutter_runner", "skaven_ratling_gunner" }

local function few_rats()
    return alive_count("skaven_slave", "event") < 5 and alive_count("skaven_clan_rat", "event") < 5
end

local EVENTS = {
    bell = { name = "canyon_bell_event", steps = {
        { t = "horde", comp = "event_small", where = "bell" },
        { t = "special", amount = 1, breeds = SPECIALS_A, req = 4 },
        { t = "horde", comp = "event_extra_spice_medium", where = "bell", limit = 3, req = 5 },
        { t = "delay", duration = 5 },
        { t = "horde", comp = "plague_monks_small", where = "bell", limit = 3, req = 6 },
        -- 0.2.16 (user playtest: the bell fell at once, no objective): VT2's objective is breaking the bell's chain holds
        -- (destructible_hold_01, three groups); each one drops the bell a step, hordes keep coming until all three are gone
        { t = "holds" },
        { t = "flow", name = "canyon_bell_event_done" },
    } },
    ogre = { name = "canyon_ogre_boss", steps = {
        { t = "boss", breed = "skaven_rat_ogre" },
        { t = "special", amount = 1, breeds = SPECIALS_B, req = 6 },
        { t = "horde", comp = "event_extra_spice_medium", where = "near", limit = 3, req = 6 },
    } },
    escape = { name = "canyon_escape_event", steps = {
        { t = "horde", comp = "event_small", where = "near" },
        { t = "delay", duration = 5 },
        { t = "continue_when", duration = 80, cond = few_rats },
        { t = "flow", name = "canyon_escape_event_done" },
    } },
}

local running = {}   -- { key, steps, i, wait }
local fired = {}     -- event key -> true
local flags = {}     -- flow events raised
local completed = false
local trig_t = 0

local function tier()
    return mod:get("difficulty") or 5
end

-- 0.2.8: spawn spots are VT2's own spawners (bell_spawners.lua, 63: hidden spots, house windows, ledges, a floor hole), at
-- the navmesh exit dtpace.spawn_pos gives each; the old 47-point list is only used before the navmesh exists
local function pick_spawners(where, limit)
    local ppos = player_positions()
    local cands, all = {}, {}
    for i = 1, #dtpace.rows do
        local wp = dtpace.spawn_pos(i)
        if wp then
            local _, dmin = nearest_flat(wp, ppos)
            all[#all + 1] = { wp = wp, d = dmin }
            if where == "bell" then
                if flat_dist(wp, W(Data.bell)) < 85 and dmin > 10 then
                    cands[#cands + 1] = wp
                end
            elseif dmin >= 22 and dmin <= 95 then
                cands[#cands + 1] = wp
            end
        end
    end
    if #cands == 0 then
        if #all == 0 then
            for _, s in ipairs(Data.enemy_spawners) do
                local wp = W(s)
                local _, dmin = nearest_flat(wp, ppos)
                all[#all + 1] = { wp = wp, d = dmin }
            end
        end
        table.sort(all, function(a, b) return a.d < b.d end)
        for i = 1, math.min(3, #all) do
            cands[#cands + 1] = all[i].wp
        end
    end
    for i = #cands, 2, -1 do
        local j = rnd(i)
        cands[i], cands[j] = cands[j], cands[i]
    end
    while limit and #cands > limit do
        table.remove(cands)
    end
    return cands
end

local function do_horde(step)
    local comp = Hordes[step.comp]
    if not comp then
        mod:error("horde composition %s missing", tostring(step.comp))
        return
    end
    local entries = comp[math.max(1, math.min(#comp, tier()))]
    local total = 0
    for _, e in ipairs(entries) do
        total = total + e[1]
    end
    local roll, pick = rnd() * total, entries[1]
    for _, e in ipairs(entries) do
        roll = roll - e[1]
        if roll <= 0 then
            pick = e
            break
        end
    end
    local spawners = pick_spawners(step.where, step.limit)
    if #spawners == 0 then
        return
    end
    -- like VT2's spawners: each one lets its share out one at a time (0.45 s apart) from the spawner itself, no scatter
    local i, n, per = 0, 0, {}
    for _, b in ipairs(pick[2]) do
        for _ = 1, rnd(b[2], b[3]) do
            i = i + 1
            local k = i % #spawners + 1
            per[k] = (per[k] or 0) + 1
            spawn_job(spawners[k], b[1], { aggro = true, tag = "event", wait = (per[k] - 1) * 0.45 })
            n = n + 1
        end
    end
    mod:info("EVENT horde %s (%s): %d minions on %d spawners", step.comp, step.where, n, #spawners)
end

local function do_special(step)
    local spawners = pick_spawners("near", nil)
    if #spawners == 0 then
        return
    end
    for k = 1, step.amount do
        local b = step.breeds[rnd(#step.breeds)]
        spawn_job(spawners[(k - 1) % #spawners + 1], b, { aggro = true, tag = "special" })
        mod:info("EVENT special %s", b)
    end
end

-- The spawn director. VT2's own spawns give a segment 3 or 4 clusters of about 3. 0.2.8: once Darktide's own pacing runs
-- in the Bell (dtpace, setting dt_pacing) it brings the roamers, hordes and specials, and the director only adds the Auric
-- packs below; it does all of this itself only when Darktide's pacing is off or could not start. The director adds:
--  * specials on every difficulty (Darktide's specials, one or two at a time, alive cap by challenge);
--  * on Auric (challenge 5) or Havoc, setting auric_density: Havoc-sized roamer packs of 10-16 at each of VT2's 47 enemy
--    spawners as you near them, patrols of 16, and a horde of 40-60 every 75-120 s from spawners out of sight.
-- Breed names are scripts/settings/breed/breeds.lua; any name this game build lacks is skipped.
director.LISTS = {
    horde = { "chaos_poxwalker", "chaos_poxwalker", "chaos_newly_infected", "cultist_melee", "renegade_melee", "cultist_melee" },
    roam = { "cultist_melee", "renegade_melee", "renegade_rifleman", "cultist_assault", "renegade_assault", "chaos_newly_infected" },
    elite = { "renegade_executor", "cultist_berzerker", "renegade_berzerker", "cultist_shocktrooper", "renegade_shocktrooper",
        "renegade_gunner", "cultist_gunner", "chaos_ogryn_executor", "chaos_ogryn_bulwark", "chaos_ogryn_gunner" },
    special = { "chaos_hound", "renegade_netgunner", "cultist_flamer", "renegade_flamer", "chaos_poxwalker_bomber",
        "cultist_grenadier", "renegade_grenadier", "cultist_mutant" },
}

function director.valid_lists()
    if director.checked then
        return
    end
    director.checked = true
    local ok, Breeds = pcall(require, "scripts/settings/breed/breeds")
    if not ok or type(Breeds) ~= "table" then
        return
    end
    for _, list in pairs(director.LISTS) do
        for i = #list, 1, -1 do
            if not Breeds[list[i]] then
                mod:info("director: breed %s is not in this game build, skipped", list[i])
                table.remove(list, i)
            end
        end
    end
end

function director.challenge()
    local ok, c = pcall(function() return Managers.state.difficulty:get_challenge() end)
    return ok and tonumber(c) or tier()
end

function director.havoc()
    if mod:get("auric_density") == false then
        return false
    end
    local ok, h = pcall(function()
        local d = Managers.state.difficulty
        return d.get_parsed_havoc_data and d:get_parsed_havoc_data() ~= nil
    end)
    return director.challenge() >= 5 or (ok and h == true)
end

function director.pick(kind)
    director.valid_lists()
    local elite_share = director.havoc() and 0.3 or 0.12
    local list = director.LISTS[kind] or director.LISTS.roam
    if kind ~= "special" and rnd() < elite_share and #director.LISTS.elite > 0 then
        list = director.LISTS.elite
    end
    return list[rnd(#list)] or "cultist_melee"
end

function director.patrol_size()
    return director.havoc() and 16 or PATROL_SIZE
end

function director.reset()
    director.packs_done, director.t, director.horde_t, director.special_t = {}, 0, nil, nil
    director.fill_done, director.fill_t, director.trickle_t, director.cum = {}, 0, nil, nil
    if director.holds_clear then
        director.holds_clear()
    end
end

function director.update(dt, here)
    director.t = director.t - dt
    if director.t > 0 then
        return
    end
    director.t = 1
    local havoc = director.havoc()
    local alive = alive_count(nil, nil)
    local cap = havoc and 170 or 70
    -- specials
    if mod:get("specials") ~= false and not dtpace.live() then
        local c = math.max(1, math.min(5, director.challenge()))
        local max_alive = havoc and 8 or ({ 2, 2, 3, 4, 6 })[c]
        director.special_t = (director.special_t or (havoc and 20 or 40)) - 1
        if director.special_t <= 0 and alive_count(nil, "special") < max_alive and alive < cap then
            director.special_t = havoc and rnd(15, 25) or rnd(math.max(20, 70 - c * 10), 90 - c * 10)
            local sp = pick_spawners("near", nil)
            for k = 1, (havoc and 2 or 1) do
                if sp[k] then
                    local b = director.pick("special")
                    spawn_job(sp[k], "skaven_gutter_runner", { aggro = true, tag = "special", dt = b })
                    mod:info("DIRECTOR special %s", b)
                end
            end
        end
    end
    if not havoc then
        return
    end
    -- Havoc-sized roamer packs streaming out of VT2's spawners (one every 0.45 s) as players near them
    local lh = to_level(here)
    for i, s in ipairs(dtpace.rows) do
        if not director.packs_done[i] and alive < cap then
            local dx, dy, dz = s[1] - Vector3.x(lh), s[2] - Vector3.y(lh), s[3] - Vector3.z(lh)
            local sp = dx * dx + dy * dy < 60 * 60 and dx * dx + dy * dy > 25 * 25 and math.abs(dz) < 25 and dtpace.spawn_pos(i)
            if sp then
                director.packs_done[i] = true
                local n = rnd(10, 16)
                for k = 1, n do
                    spawn_job(sp, "skaven_clan_rat", { tag = "pack", dt = director.pick("roam"), wait = (k - 1) * 0.45 })
                end
                alive = alive + n
                mod:info("DIRECTOR pack of %d at spawner %d", n, i)
            end
        end
    end
    -- hordes
    director.horde_t = (director.horde_t or 60) - 1
    if director.horde_t <= 0 and alive < cap - 40 and not dtpace.live() then
        director.horde_t = rnd(75, 120)
        local sp = pick_spawners("near", 4)
        if #sp > 0 then
            local n = rnd(40, 60)
            for k = 1, n do
                spawn_job(sp[(k - 1) % #sp + 1], "skaven_slave", { aggro = true, tag = "horde", dt = director.pick("horde"),
                    wait = math.floor((k - 1) / #sp) * 0.45 })
            end
            mod:info("DIRECTOR horde of %d on %d spawners", n, #sp)
            queue_comm("horde", 2, true)
        end
    end
end

-- 0.2.16 (user playtest 2026-10-27: "there should be enemies every few metres on standard pathing", hordes and specials came
-- in big waves): two steady sources on top of Darktide's pacing, both off inside the start building.
--  * path fill: every path_spacing VT2 metres along VT2's main path, 35-80 m ahead of the furthest player, a small idle group
--    of roamers stands a few metres off the path (aggro_update wakes them as players come near);
--  * pressure stream: every few seconds 2-4 aggroed enemies come out of a VT2 spawner 22-95 m from the players.
function director.path_cum()
    if director.cum then
        return director.cum
    end
    local cum, total = { 0 }, 0
    local mp = Data.main_path or {}
    for i = 2, #mp do
        local a, b = mp[i - 1], mp[i]
        total = total + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        cum[i] = total
    end
    director.cum = cum
    return cum
end

-- the VT2 point at distance d along the main path, and the path direction there
function director.path_at(d)
    local mp, cum = Data.main_path, director.path_cum()
    for i = 2, #mp do
        if cum[i] >= d then
            local a, b = mp[i - 1], mp[i]
            local seg = math.max(cum[i] - cum[i - 1], 0.001)
            local t = (d - cum[i - 1]) / seg
            local dx, dy = (b[1] - a[1]) / seg, (b[2] - a[2]) / seg
            return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }, dx, dy
        end
    end
    return nil
end

function director.flow(dt, here)
    director.fill_t = (director.fill_t or 0) - dt
    if director.fill_t > 0 or not (Data.main_path and #Data.main_path > 1) then
        return
    end
    director.fill_t = 0.5
    director.fill_done = director.fill_done or {}
    local havoc = director.havoc()
    local c = math.max(1, math.min(5, director.challenge()))
    local alive = alive_count(nil, nil)
    local cap = havoc and 170 or 70 + c * 10
    -- the furthest path progress of any player (nearest main path node)
    local cum = director.path_cum()
    local far = -1
    for _, wp in ipairs(player_positions()) do
        local l = to_level(wp)
        local best, bd = 1, math.huge
        for i, n in ipairs(Data.main_path) do
            local d = (n[1] - Vector3.x(l)) ^ 2 + (n[2] - Vector3.y(l)) ^ 2 + (n[3] - Vector3.z(l)) ^ 2
            if d < bd then
                best, bd = i, d
            end
        end
        far = math.max(far, cum[best] or 0)
    end
    if far < 0 then
        return
    end
    local spacing = mod:get("path_spacing") or 9
    if spacing > 0 then
        local start = dtpace.exit_i and cum[dtpace.exit_i] or 0
        local k0 = math.ceil(math.max(far + 35, start) / spacing)
        local k1 = math.floor((far + 80) / spacing)
        for k = k0, k1 do
            if alive >= cap then
                break
            end
            if not director.fill_done[k] then
                director.fill_done[k] = true
                local pt, dx, dy = director.path_at(k * spacing)
                if pt then
                    local side = rnd() < 0.5 and -1 or 1
                    local off = side * (1.5 + rnd() * 3.5)
                    local base = { pt[1] - dy * off, pt[2] + dx * off, pt[3] + 0.5 }
                    local n = rnd(2, 2 + math.ceil(c / 2) + (havoc and 2 or 0))
                    for j = 1, n do
                        local wp = W({ base[1] + rnd() * 2.4 - 1.2, base[2] + rnd() * 2.4 - 1.2, base[3] })
                        spawn_job(wp, "skaven_clan_rat", { tag = "fill", floor = true, dt = director.pick("roam"), wait = j * 0.1 })
                    end
                    alive = alive + n
                end
            end
        end
    end
    -- pressure stream
    local every = mod:get("stream_interval") or 9
    if every <= 0 then
        return
    end
    director.trickle_t = (director.trickle_t or every) - 0.5
    if director.trickle_t <= 0 and alive < cap - 10 then
        director.trickle_t = every * (0.7 + rnd() * 0.6) * (havoc and 0.6 or 1)
        local sp = pick_spawners("near", 1)[1]
        if sp then
            local n = rnd(2, 3 + math.floor(c / 3) + (havoc and 2 or 0))
            for j = 1, n do
                spawn_job(sp, "skaven_slave", { aggro = true, tag = "stream", dt = director.pick("horde"), wait = (j - 1) * 0.4 })
            end
        end
    end
end

-- 0.2.7: the Rat Ogre event spawns the user's Sprayer Ogryn boss when QIangIQsSprayerOgryn is installed (setting
-- sprayer_boss). It is optional: without that mod the Bell's own custom Plague Ogryn below is used, so the Bell still works
-- on its own. The Sprayer mod spawns its boss near the host (sog.Boss.spawn) after loading its packages.
local function do_boss(step)
    local p = OGRE_SPAWNER or Data.boss_spawners[1]
    if step.breed == "skaven_rat_ogre" and mod:get("sprayer_boss") ~= false then
        local sog = get_mod("QIangIQsSprayerOgryn")
        local Boss = sog and type(sog.sog) == "table" and sog.sog.Boss
        if Boss and Boss.spawn then
            local ok, res, why = pcall(Boss.spawn, 1, 14)
            if ok and res then
                say("the Sprayer Ogryn has been woken")
                mod:info("BOSS event: Sprayer Ogryn via QIangIQsSprayerOgryn")
                return
            end
            mod:info("Sprayer Ogryn spawn refused (%s %s); using the Rat Ogre", tostring(res), tostring(why))
        end
    end
    if p then
        spawn_job(W(p), step.breed, { aggro = true, tag = "boss", floor = true })
        say("a Rat Ogre has been woken")
    end
end

local function start_event(key)
    local def = EVENTS[key]
    if not def or fired[key] then
        return false
    end
    fired[key] = true
    running[#running + 1] = { key = key, steps = def.steps, i = 1 }
    mod:info("EVENT %s started", def.name)
    say("event: %s", def.name)
    if key == "bell" then
        queue_comm("chime", 0, true); queue_comm("horde", 7, true); queue_comm("effect", 28, true)
        -- VT2: the bell wobbles (story a1beecc7) and the bell music starts as the event begins
        Extra.emit("s:a1beecc7")
        Extra.emit("m:1")
    elseif key == "escape" then
        queue_comm("exit", 5, true)
    end
    return true
end

local function update_events(dt)
    for r = #running, 1, -1 do
        local ev = running[r]
        local step = ev.steps[ev.i]
        local advance = false
        if not step then
            table.remove(running, r)
        else
            local ok, err = pcall(function()
                if step.req and tier() < step.req then
                    advance = true
                elseif step.t == "holds" then
                    advance = director.holds_update(dt)
                elseif step.t == "delay" then
                    ev.wait = (ev.wait or step.duration) - dt
                    advance = ev.wait <= 0
                elseif step.t == "continue_when" then
                    ev.wait = (ev.wait or step.duration) - dt
                    advance = ev.wait <= 0 or step.cond()
                elseif step.t == "horde" then
                    do_horde(step)
                    advance = true
                elseif step.t == "special" then
                    do_special(step)
                    advance = true
                elseif step.t == "boss" then
                    do_boss(step)
                    advance = true
                elseif step.t == "flow" then
                    flags[step.name] = true
                    if step.name == "canyon_bell_event_done" then
                        queue_comm("destroyed", 0, true); queue_comm("falling", 9, true)
                        -- the bell breaks loose and falls 112 m (bell_drop_03); the event music ends
                        Extra.emit("s:bell_drop_03")
                        Extra.emit("m:0")
                    end
                    mod:info("EVENT flow %s", step.name)
                    say("%s", step.name)
                    advance = true
                else
                    advance = true
                end
            end)
            if not ok then
                mod:error("event %s step %d failed: %s", ev.key, ev.i, tostring(err))
                advance = true
            end
            if advance then
                ev.i = ev.i + 1
                ev.wait = nil
            end
        end
    end
end

-- Event triggers. The flow graph of the level is not decoded, so these are placed at the level units the events belong to:
-- the bell prop (bell event), the lever (ogre boss; it opens the gameplay_boss_door units), the end_zone unit (end).
local function any_player_near(pos_level, radius, dz)
    for _, wp in ipairs(player_positions()) do
        local l = to_level(wp)
        if Vector3.length(Vector3.flat(l - v3(pos_level))) < radius and math.abs(Vector3.z(l) - pos_level[3]) < dz then
            return true
        end
    end
    return false
end

local function update_triggers(dt)
    trig_t = trig_t - dt
    if trig_t > 0 then
        return
    end
    trig_t = 0.5
    if not fired.ogre and any_player_near(Data.lever, 24, 14) then
        start_event("ogre")
    end
    if not fired.bell and any_player_near(Data.bell, 18, 16) then
        start_event("bell")
    end
    if not flags.vo_reached and any_player_near(Data.bell, 40, 40) then
        flags.vo_reached = true
        queue_comm("reaching_bell", 1, true)
    end
    if flags.canyon_bell_event_done and not fired.escape and not any_player_near(Data.bell, 30, 400) then
        start_event("escape")
    end
    if fired.escape and not completed and any_player_near(Data.end_zone, 14, 10) then
        completed = true
        say("you escaped the Bell")
        pcall(function() Managers.state.game_mode:complete_game_mode("won") end)
    end
end

-- 0.2.16: the bell's chain holds (VT2 destructible_hold_01, three groups of three). A hold breaks once players have stood
-- at it for HOLD_TIME seconds in all; every break shakes the bell down a step (bell_drop_01, _02) and the third lets it
-- fall. Markers and messages show on every peer (sync event "h:<broken mask>").
director.HOLDS = { { -48.31, -433.46, 40.44 }, { -44.55, -393.76, 44.13 }, { -13.21, -413.49, 44.06 } }
director.HOLD_TIME = 5

function director.holds_note(text)
    pcall(function()
        Managers.event:trigger("event_add_notification_message", "default", text)
    end)
end

function director.holds_markers(mask)
    director.hold_marker_ids = director.hold_marker_ids or {}
    for i, h in ipairs(director.HOLDS) do
        local broken = mask and math.floor(mask / 2 ^ (i - 1)) % 2 == 1
        local id = director.hold_marker_ids[i]
        if (broken or not mask) and id then
            pcall(function() Managers.event:trigger("remove_world_marker", id) end)
            director.hold_marker_ids[i] = nil
        elseif mask and not broken and not id and base_box then
            local pos = W(h)
            local g = ground_below(pos, 4 * MAP_SCALE, 10 * MAP_SCALE)
            pcall(function()
                Managers.event:trigger("add_world_marker_position", "objective", (g or pos) + Vector3(0, 0, 1.5), function(mid)
                    director.hold_marker_ids[i] = mid
                end, {})
            end)
        end
    end
end

-- every peer: the host's hold state (number = broken mask; "x" = event over)
function director.holds_sync(arg)
    if arg == "x" then
        director.holds_markers(nil)
        return
    end
    local mask = tonumber(arg) or 0
    local before = director.hold_seen
    director.hold_seen = mask
    director.holds_markers(mask)
    local n = (mask % 2) + (math.floor(mask / 2) % 2) + (math.floor(mask / 4) % 2)
    if before == nil then
        director.holds_note("Break the bell's three chain holds: stay at a marked hold to hack it loose.")
    elseif mask ~= before then
        director.holds_note(n < 3 and string.format("Chain hold broken (%d of 3)", n) or "The last hold gives way. The bell falls!")
    end
end

function director.holds_clear()
    director.hold_state, director.hold_seen = nil, nil
    director.holds_markers(nil)
end

-- host, every frame while the event waits on the holds; true once all three are broken
function director.holds_update(dt)
    local st = director.hold_state
    if not st then
        st = { prog = { 0, 0, 0 }, mask = 0, n = 0, horde_t = 20, special_t = 12, remind_t = 25 }
        director.hold_state = st
        Extra.emit("h:0")
    end
    local ppos = player_positions()
    for i, h in ipairs(director.HOLDS) do
        if math.floor(st.mask / 2 ^ (i - 1)) % 2 == 0 then
            local near = 0
            for _, wp in ipairs(ppos) do
                local l = to_level(wp)
                if Vector3.length(Vector3.flat(l - v3(h))) < 5 and math.abs(Vector3.z(l) - h[3]) < 7 then
                    near = near + 1
                end
            end
            if near > 0 then
                st.prog[i] = st.prog[i] + dt * (1 + 0.5 * (near - 1))
                if st.prog[i] >= director.HOLD_TIME then
                    st.mask, st.n = st.mask + 2 ^ (i - 1), st.n + 1
                    mod:info("EVENT bell chain hold %d broken (%d of 3)", i, st.n)
                    if st.n <= 2 then
                        Extra.emit("s:bell_drop_0" .. st.n)
                    end
                    Extra.emit("h:" .. st.mask)
                end
            end
        end
    end
    if st.n >= 3 then
        Extra.emit("h:x")
        return true
    end
    -- the bell keeps calling: hordes and specials until the holds are gone
    st.horde_t, st.special_t, st.remind_t = st.horde_t - dt, st.special_t - dt, st.remind_t - dt
    if st.horde_t <= 0 then
        st.horde_t = rnd(22, 34)
        do_horde({ comp = "event_small", where = "bell" })
        queue_comm("horde", 1, true)
    end
    if st.special_t <= 0 and mod:get("specials") ~= false then
        st.special_t = rnd(20, 30)
        do_special({ amount = 1, breeds = SPECIALS_B })
    end
    if st.remind_t <= 0 then
        st.remind_t = 30
        Extra.emit("h:" .. st.mask)
        director.holds_note(string.format("Break the bell's chain holds (%d of 3 broken)", st.n))
    end
    return false
end

-- ---------------------------------------------------------------------------------------------------- sealed first wall
-- The way out of the start cave is walled off (chunk unit "bc_wall", three VT2 brick wall panels, build_bell.py). It falls when
-- any explosion goes off within WALL_BREAK_RADIUS of it: the mine (pocketable, planted), the explosive luggable, grenades.
-- A kit of those lies on the path before the wall (build_pickups). /bell blast opens it by hand.
local WALL_BREAK_RADIUS = 9

local function break_wall()
    local u = named["bc_wall"]
    if wall_broken or not u then
        return false
    end
    wall_broken = true
    named["bc_wall"] = nil
    unit_set[u] = nil
    for i = #units, 1, -1 do
        if units[i] == u then
            table.remove(units, i)
            break
        end
    end
    if unit_ok(u) then
        local world = Unit.world(u)
        if world then
            World.destroy_unit(world, u)
        end
    end
    say("the wall collapses")
    remove_wall_tag()
    -- the VT2 navmesh already runs through the wall's spot (the wall is not in VT2); the tile bake needs the gap re-baked
    if Data.wall and vt2nav.state ~= "ready" then
        pcall(bake_around, { Data.wall[1], Data.wall[2], Data.wall[3] }, 30, true)
    end
    return true
end

mod:hook_require("scripts/utilities/attack/explosion", function(Explosion)
    mod:hook_safe(Explosion, "create_explosion", function(world, physics_world, source_position)
        if wall_broken or not Data.wall or not base_box or not named["bc_wall"] or not in_map() or not source_position then
            return
        end
        local site = Data.breach_site -- where the main path meets the wall (breach.site)
        if Vector3.length(source_position - W(Data.wall)) < WALL_BREAK_RADIUS
            or (site and Vector3.length(source_position - W(site)) < WALL_BREAK_RADIUS) then
            break_wall() -- breach.update then clears the charge and its objective
        end
    end)
end)

-- Breach charge, the way Mercantile's walls work: hold Interact at the wall for PLANT_TIME (Darktide's setup_breach_charge
-- duration), then a FUSE_TIME fuse (BreachChargeAddon), then the wall goes with the VT2 bell explosion sound and Darktide's
-- breach_charge_explosion camera shake. Darktide's own charge prop has no package outside its missions, so this is done
-- here instead. The host's blast goes to Realms clients as a "w" event (bell_extra.lua); a client's own plant opens its
-- own copy of the wall.
-- one local for all of it: the main chunk is at Lua's 200-locals limit
local breach = { hold = 0, fuse = nil, hinted = false, planting = false, PLANT_RANGE = 6, HINT_RANGE = 12, PLANT_TIME = 4, FUSE_TIME = 3 }

function breach.notify(text)
    pcall(function()
        Managers.event:trigger("event_add_notification_message", "default", text)
    end)
end

function breach.blast()
    breach.fuse, breach.hold, breach.planting = nil, 0, false
    if wall_broken then
        return
    end
    local pos = Data.wall and base_box and W(Data.breach_site or Data.wall)
    if pos then
        pcall(Extra.sfx, "amb\\bell_explosion.ogg", to_level(pos), 250, 1)
        pcall(function()
            local CameraShake = require("scripts/utilities/camera/camera_shake")
            CameraShake.camera_shake_by_distance("breach_charge_explosion", pos, 8, 30, 1, 0.3)
        end)
    end
    breach.remove_charge()
    break_wall()
end

-- distance from the player to the wall in VT2 metres (flat, height): the nearest point of the wall chunk's box (it
-- includes the extension panels), falling back to the wall's anchor point
function breach.dist(here)
    local wall = W(Data.wall)
    local d = Vector3.length(Vector3.flat(here - wall)) / MAP_SCALE
    local dz = math.abs(Vector3.z(here) - Vector3.z(wall)) / MAP_SCALE
    local u = named["bc_wall"]
    local ok, pose, ext = pcall(Unit.box, u)
    if ok and pose and ext then
        local okl, lp = pcall(function()
            return Matrix4x4.transform(Matrix4x4.inverse(pose), here)
        end)
        if okl and lp then
            local dx = math.max(0, math.abs(Vector3.x(lp)) - Vector3.x(ext))
            local dy = math.max(0, math.abs(Vector3.y(lp)) - Vector3.y(ext))
            local bz = math.max(0, math.abs(Vector3.z(lp)) - Vector3.z(ext))
            local db = math.sqrt(dx * dx + dy * dy) / MAP_SCALE
            if db < d then
                d, dz = db, bz / MAP_SCALE
            end
        end
    end
    return d, dz
end

-- VT2's ladders (units/ladders/generic_ladder_4m / 6m) are plain meshes here: Darktide's ladder extension is not on them.
-- 0.2.7: they work like Darktide's: walk into the foot of one (moving forward, facing it) and you climb it, stepping onto the
-- ledge at its top (the side of the ladder that has ground there); walk into the top of one from its ledge and you climb
-- down. Jump lets go. Rows: VT2 base x, y, z, height, ladder facing (local Y) x, y. Kept on the breach table: the main
-- chunk is at Lua's 200-locals limit.
breach.LADDERS = {
    { -22.46, -223.87, -32.86, 4.0, 0.982, -0.132 }, { -115.63, 1.44, 1.58, 6.0, -0.014, -1.000 },
    { -121.48, -95.08, -19.87, 3.1, 0.296, -0.946 }, { -5.64, -194.05, -33.04, 4.0, 0.989, -0.070 },
    { -28.85, -220.94, -31.44, 4.0, -0.931, 0.339 }, { -60.90, -226.42, -31.73, 4.4, 0.233, -0.972 },
    { 10.37, -232.42, -26.18, 3.9, 1.000, -0.007 },
}
breach.CLIMB_SPEED = 3.2   -- world metres per second, about Darktide's ladder speed
breach.climb_cd = 0

-- the ledge next to the ladder at height z (VT2), or nil
function breach.ledge(L, z)
    for _, s in ipairs({ 1, -1 }) do
        local g = ground_below(W({ L[1] + L[5] * s * 0.9, L[2] + L[6] * s * 0.9, z }), 1.5 * MAP_SCALE, 3 * MAP_SCALE)
        if g then
            return g + Vector3(0, 0, 0.1)
        end
    end
    return nil
end

function breach.start_climb(L, up, side)
    local from_l = up and { L[1] + L[5] * side * 0.45, L[2] + L[6] * side * 0.45, L[3] + 0.1 }
        or { L[1] + L[5] * side * 0.45, L[2] + L[6] * side * 0.45, L[3] + L[4] - 0.2 }
    local to_l = { from_l[1], from_l[2], up and (L[3] + L[4] - 0.2) or (L[3] + 0.1) }
    local from, to = W(from_l), W(to_l)
    local exit = up and breach.ledge(L, L[3] + L[4]) or (ground_below(to, 1, 3 * MAP_SCALE) or to)
    breach.climb = { from = Vector3Box(from), to = Vector3Box(to), exit = Vector3Box(exit), t = 0,
        dur = math.max(0.4, Vector3.length(to - from) / breach.CLIMB_SPEED) }
end

function breach.ladder_update(dt, pu, here)
    local input = ScriptUnit.has_extension(pu, "input_system")
    local c = breach.climb
    if c then
        local okj, jump = false, false
        if input then
            okj, jump = pcall(input.get, input, "jump")
        end
        if okj and jump then
            breach.climb, breach.climb_cd = nil, 0.8
            return
        end
        c.t = c.t + dt
        local a = math.min(1, c.t / c.dur)
        if a < 1 then
            teleport_to(Vector3.lerp(c.from:unbox(), c.to:unbox(), a))
        else
            teleport_to(c.exit:unbox())
            breach.climb, breach.climb_cd = nil, 0.8
        end
        return
    end
    if breach.climb_cd > 0 then
        breach.climb_cd = breach.climb_cd - dt
        return
    end
    local okm, move = false, nil
    if input then
        okm, move = pcall(input.get, input, "move")
    end
    if not (okm and move and Vector3.y(move) > 0.3) then
        return
    end
    local fwd = Quaternion.forward(Unit.world_rotation(pu, 1))
    local l = to_level(here)
    for _, L in ipairs(breach.LADDERS) do
        local dx, dy, dz = Vector3.x(l) - L[1], Vector3.y(l) - L[2], Vector3.z(l) - L[3]
        local d2 = dx * dx + dy * dy
        if not breach.dtl[L] and d2 < 1.44 and dz > -1 and dz < L[4] + 1.5 then
            -- the side of the ladder the player stands on, and whether they face the ladder from there
            local along = dx * L[5] + dy * L[6]
            local side = along >= 0 and 1 or -1
            local facing = -(Vector3.x(fwd) * L[5] + Vector3.y(fwd) * L[6]) * side
            if facing > 0.5 then
                if dz < L[4] * 0.5 then
                    breach.start_climb(L, true, side)
                elseif dz > L[4] - 1 then
                    -- from the ledge: the ladder side is the one away from the ledge
                    breach.start_climb(L, false, -side)
                end
                return
            end
        end
    end
end

-- 0.2.16 (user playtest 2026-10-27: "ladder is slightly buggy, use darktide ladders as stand in"): Darktide's ladder state
-- needs a level unit (ladder_unit_id is the unit's level index, synced to every peer), so a spawned ladder cannot work.
-- The host mission's own ladders are level units: each VT2 ladder borrows one, moved onto it, turned to face the wall and
-- stretched to its height (collision actors rebuilt at the new pose). Every peer does the same in the same order (level
-- index), so the ids match. They go back when the Bell is torn down. VT2 ladders left without one keep the auto-climb above.
breach.dtl = {}           -- VT2 ladder row -> true when a Darktide ladder stands in
breach.dtl_moved = {}     -- { unit, pos, rot, scale }

function breach.dtl_actors(u)
    local okn, na = pcall(Unit.num_actors, u)
    for i = 1, okn and na or 0 do
        pcall(Unit.destroy_actor, u, i)
        pcall(Unit.create_actor, u, i)
    end
end

function breach.dtl_find(world)
    local found, lseen, useen = {}, {}, {}
    local function walk(level)
        if not level or lseen[level] then
            return
        end
        lseen[level] = true
        local okn, nested = pcall(Level.nested_levels, level)
        for _, sub in ipairs(okn and type(nested) == "table" and nested or {}) do
            walk(sub)
        end
        local oku, lunits = pcall(Level.units, level, true)
        if not (oku and type(lunits) == "table") then
            oku, lunits = pcall(Level.units, level)
        end
        for _, u in ipairs(oku and type(lunits) == "table" and lunits or {}) do
            if not useen[u] and unit_ok(u) and not unit_set[u] and Unit.has_node(u, "node_top") and Unit.has_node(u, "node_bottom")
                and Unit.has_node(u, "node_leave") then
                useen[u] = true
                local okl, idx = pcall(function() return Managers.state.unit_spawner:level_index(u) end)
                if okl and idx then
                    local len = Vector3.distance(Unit.world_position(u, Unit.node(u, "node_top")),
                        Unit.world_position(u, Unit.node(u, "node_bottom")))
                    if len > 1 then
                        found[#found + 1] = { unit = u, idx = idx, len = len }
                    end
                end
            end
        end
    end
    for _, level in ipairs(World.levels(world) or {}) do
        walk(level)
    end
    table.sort(found, function(a, b) return a.idx < b.idx end)
    return found
end

function breach.dtl_restore()
    for _, m in ipairs(breach.dtl_moved) do
        if unit_ok(m.unit) then
            pcall(function()
                Unit.set_local_position(m.unit, 1, m.pos:unbox())
                Unit.set_local_rotation(m.unit, 1, m.rot:unbox())
                Unit.set_local_scale(m.unit, 1, m.scale:unbox())
                World.update_unit(Unit.world(m.unit), m.unit)
            end)
            breach.dtl_actors(m.unit)
        end
    end
    breach.dtl_moved, breach.dtl = {}, {}
end

function breach.dtl_place()
    breach.dtl_restore()
    local world = level_world()
    if mod:get("dt_ladders") == false or not (world and base_box) then
        return
    end
    local pool = breach.dtl_find(world)
    local used, n = {}, 0
    for _, L in ipairs(breach.LADDERS) do
        local want = L[4] * MAP_SCALE
        local best, bd = nil, math.huge
        for k, c in ipairs(pool) do
            local d = math.abs(math.log(want / c.len))
            if not used[k] and d < bd then
                best, bd = k, d
            end
        end
        if not best then
            break
        end
        used[best] = true
        local c = pool[best]
        local u = c.unit
        -- the wall side: the side with a ledge at the top (the climber faces it and steps off onto it)
        local s = 1
        if not ground_below(W({ L[1] + L[5] * 0.9, L[2] + L[6] * 0.9, L[3] + L[4] }), 1.5 * MAP_SCALE, 3 * MAP_SCALE)
            and ground_below(W({ L[1] - L[5] * 0.9, L[2] - L[6] * 0.9, L[3] + L[4] }), 1.5 * MAP_SCALE, 3 * MAP_SCALE) then
            s = -1
        end
        local ok, err = pcall(function()
            breach.dtl_moved[#breach.dtl_moved + 1] = { unit = u, pos = Vector3Box(Unit.local_position(u, 1)),
                rot = QuaternionBox(Unit.local_rotation(u, 1)), scale = Vector3Box(Unit.local_scale(u, 1)) }
            local sc0 = Unit.local_scale(u, 1)
            local target = W({ L[1], L[2], L[3] })
            Unit.set_local_rotation(u, 1, Quaternion.look(Vector3(L[5] * s, L[6] * s, 0), Vector3.up()))
            Unit.set_local_scale(u, 1, Vector3(Vector3.x(sc0), Vector3.y(sc0), Vector3.z(sc0) * want / c.len))
            Unit.set_local_position(u, 1, target)
            World.update_unit(world, u)
            local bottom = Unit.world_position(u, Unit.node(u, "node_bottom"))
            Unit.set_local_position(u, 1, target + (target - bottom))
            World.update_unit(world, u)
            Unit.set_unit_visibility(u, true)
        end)
        if ok then
            breach.dtl_actors(u)
            for i = #host_level.hidden, 1, -1 do
                if host_level.hidden[i].unit == u then
                    table.remove(host_level.hidden, i)
                end
            end
            breach.dtl[L] = true
            n = n + 1
        else
            mod:error("Darktide ladder stand-in failed: %s", tostring(err))
        end
    end
    mod:info("LADDERS: %d of %d VT2 ladders use one of the host mission's %d ladders", n, #breach.LADDERS, #pool)
end
host_level.on_restore = breach.dtl_restore

-- 0.2.7: Mercantile's breach charge. The host spawns Darktide's own breach charge prop on the wall (level_props breach_charge,
-- the way BreachChargeAddon spawns it on its wall nodes): its hologram and its setup_breach_charge interaction, which equips the
-- pup_breach_charge device and plays the plant animation. The interaction's success flow event starts the fuse. The prop only
-- ships in an expedition level package (ResourceLoader catalog: unit_004 packages[166]), loaded first. If loading or spawning
-- fails, holding Interact at the wall still plants a charge (the 0.2.4 way).
breach.CHARGE_UNIT = "content/environment/gameplay/breach_charge/breach_charge"
breach.CHARGE_PACKAGES = { "content/levels/expeditions/opportunities/wastes/op_16m_drop_pod_001/world",
    "content/weapons/player/pickups/pup_breach_charge/pup_breach_charge" }
-- 0.2.15: the wall is the brick seal in the basement doorway (bell_data wall_normal); VT2's -116 wall is scenery now
breach.NORMAL = Data.wall_normal or { -0.205, 0.979 }

-- 0.2.16 hotfix 3 (Dioscurio 2026-10-27: CTD in spawn_husk_unit joining a Bell run): the host's breach charge is a networked
-- level_prop, and a client that had not loaded the expedition package yet could not spawn its copy. A client now loads the
-- packages when its map is built, and if a level_prop husk arrives in the Bell before they are in, it waits for them here
-- (a short hitch instead of a crash).
breach.CHARGE_DELAY = 20
function breach.wait_packages(list)
    local pm = Managers.package
    for _, p in ipairs(list) do
        if not pm:has_loaded(p) then
            if not pm:is_loading(p) then
                pm:load(p, "QIangIQsBell", nil, true)
            end
            local h = pm._async_packages and pm._async_packages[p]
            if not h and pm._prioritize_package then
                pm:_prioritize_package(p)
                h = pm._async_packages and pm._async_packages[p]
            end
            if h then
                local t0 = Application.time_since_launch()
                while not ResourcePackage.has_loaded(h) and Application.time_since_launch() - t0 < 20 do
                end
                if ResourcePackage.has_loaded(h) then
                    ResourcePackage.flush(h)
                end
            end
            mod:info("package %s waited for (husk spawn): %s", p, tostring(h and ResourcePackage.has_loaded(h)))
        end
    end
end

function breach.ensure_now()
    breach.wait_packages(breach.CHARGE_PACKAGES)
end

-- 0.2.16 hotfix 5 (host/client parity): QIangIQsSprayerOgryn loads its boss packages only on the host before spawning, so a
-- client could get the boss husk without them (the same spawn_husk_unit crash as the breach charge). Every peer now loads
-- them when the Bell map is built, and a minion husk arriving before they are in waits for them.
function breach.sog_boss()
    local sog = get_mod("QIangIQsSprayerOgryn")
    return sog and type(sog.sog) == "table" and sog.sog.Boss or nil
end

function breach.sog_list()
    if breach.sog_pk == nil then
        breach.sog_pk = false
        local Boss = breach.sog_boss()
        if Boss and Boss.package_list then
            local ok, pk = pcall(Boss.package_list)
            if ok and type(pk) == "table" then
                local list = {}
                for name in pairs(pk) do
                    list[#list + 1] = name
                end
                table.sort(list)
                breach.sog_pk = list
            end
        end
    end
    return breach.sog_pk or nil
end

function breach.sog_preload()
    if mod:get("sprayer_boss") == false then
        return
    end
    local list = breach.sog_list()
    if not list then
        return
    end
    local pm = Managers.package
    local n = 0
    for _, p in ipairs(list) do
        if not pm:has_loaded(p) and not pm:is_loading(p) then
            pm:load(p, "QIangIQsBell", nil, true)
            n = n + 1
        end
    end
    mod:info("Sprayer Ogryn boss packages: %d of %d started loading on this peer", n, #list)
end

function breach.sog_wait()
    if breach.sog_ready or mod:get("sprayer_boss") == false then
        return
    end
    local list = breach.sog_list()
    if not list then
        breach.sog_ready = true
        return
    end
    local pm = Managers.package
    for _, p in ipairs(list) do
        if not pm:has_loaded(p) then
            breach.wait_packages(list)
            break
        end
    end
    -- one wait per run at most, so a package that never loads cannot stall every later spawn
    breach.sog_ready = true
end

-- 0.2.16 hotfix 4 (user CTD 2026-10-27 06:12, Havoc Bell run): a melee sweep hit a resting projectile unit (the Bell's
-- pickups / luggables lie in "sleep" with no true flight template) and ProjectileUnitLocomotionExtension.register_sweep_hit
-- indexed the nil template (projectile_unit_locomotion_extension.lua:648). Only true-flight projectiles take sweep hits.
mod:hook_require("scripts/extension_systems/locomotion/projectile_unit_locomotion_extension", function(Ext)
    if rawget(Ext, "__qiangiq_bell_sweep") then
        return
    end
    rawset(Ext, "__qiangiq_bell_sweep", true)
    mod:hook(Ext, "register_sweep_hit", function(func, self, ...)
        local data = self._integration_data
        if not (data and data.true_flight_template) then
            return
        end
        return func(self, ...)
    end)
end)

mod:hook_require("scripts/foundation/managers/unit_spawner/unit_spawner_manager", function(UnitSpawnerManager)
    if rawget(UnitSpawnerManager, "__qiangiq_bell_husk") then
        return
    end
    rawset(UnitSpawnerManager, "__qiangiq_bell_husk", true)
    mod:hook(UnitSpawnerManager, "spawn_husk_unit", function(func, self, game_object_id, ...)
        if current_mission() == MISSION_KEY or map_ready then
            pcall(function()
                local name = self._unit_template_network_lookup[GameSession.game_object_field(self._game_session,
                    game_object_id, "unit_template")]
                if name == "level_prop" then
                    breach.ensure_now()
                elseif name == "minion" then
                    breach.sog_wait()
                end
            end)
        end
        return func(self, game_object_id, ...)
    end)
end)

function breach.load_charge()
    if breach.pkg_state then
        return
    end
    breach.pkg_state = "loading"
    local left = #breach.CHARGE_PACKAGES
    local ok, err = pcall(function()
        for _, p in ipairs(breach.CHARGE_PACKAGES) do
            Managers.package:load(p, "QIangIQsBell", function()
                left = left - 1
                if left == 0 then
                    breach.pkg_state = "ready"
                    mod:info("breach charge packages loaded")
                end
            end)
        end
    end)
    if not ok then
        breach.pkg_state = "failed"
        mod:error("breach charge packages failed: %s", tostring(err))
    end
end

-- 0.2.11: the made-up extension panels that blocked the cave passage are gone (user 2026-10-27: remove that wall
-- entirely), so the charge goes back on VT2's own brick wall at its centre. Data.breach_site is read by the explosion hook.
function breach.site()
    Data.breach_site = Data.breach_site or { Data.wall[1], Data.wall[2], Data.wall[3] }
    return Data.breach_site
end

-- 0.2.12: the face players walk up to (the side of the main path node nearest the wall); NORMAL alone put the charge
-- and its hologram on the far side of the wall (user 2026-10-27: no hologram)
function breach.face()
    if breach.face_n then
        return breach.face_n
    end
    -- 0.2.15: the side the players arrive from (the start); the nearest path node can be past the doorway
    local w, n = Data.wall, breach.NORMAL
    local best = Data.start and Data.start[1]
    local s = 1
    if best and (best[1] - w[1]) * n[1] + (best[2] - w[2]) * n[2] < 0 then
        s = -1
    end
    breach.face_n = { n[1] * s, n[2] * s }
    mod:info("breach charge faces %.2f, %.2f", breach.face_n[1], breach.face_n[2])
    return breach.face_n
end

function breach.spawn_charge()
    local ok, res = pcall(function()
        local LevelProps = require("scripts/settings/level_prop/level_props")
        local w, n = breach.site(), breach.face()
        local pos = W({ w[1] + n[1] * 0.45, w[2] + n[2] * 0.45, w[3] + 1.1 })
        local rot = Quaternion.look(Vector3(n[1], n[2], 0), Vector3.up())
        local unit = Managers.state.unit_spawner:spawn_network_unit(breach.CHARGE_UNIT, "level_prop", pos, rot, nil,
            LevelProps.breach_charge)
        local ie = unit and ScriptUnit.has_extension(unit, "interactee_system")
        if not ie then
            error("the breach charge prop has no interactee extension")
        end
        ie._trigger_flow_event = function(ext, event_name)
            Unit.flow_event(ext._unit, event_name)
            if event_name == "lua_interaction_success_network_synced" and not breach.fuse and not wall_broken then
                breach.fuse = breach.FUSE_TIME
                breach.notify("Charge planted. Stand back!")
                say("breach charge planted, %d s fuse", breach.FUSE_TIME)
            end
        end
        return unit
    end)
    if ok and res then
        breach.charge_unit = res
        mod:info("breach charge prop spawned on the wall")
        breach.objective_start(res)
    else
        breach.charge_failed = true
        mod:error("breach charge prop failed (%s); holding Interact at the wall plants the charge instead", tostring(res))
    end
end

-- 0.2.14 (user 2026-10-27: mark it like Mercantile): the plant is a mission objective (HUD entry + objective marker on
-- the charge). The host mission's objectives don't have one, so No Man's Land's breaching charge objective is added to
-- the definitions on every peer (its name is in NetworkLookup, so the start / marker rpcs reach clients).
breach.OBJ = "objective_op_no_mans_dead_zone_breaching_charge"
function breach.objective_system()
    local mos = Managers.state.extension and Managers.state.extension:system("mission_objective_system")
    if not mos or not mos._objective_definitions then
        return nil
    end
    if not mos._objective_definitions[breach.OBJ] then
        local ok, T = pcall(require, "scripts/settings/mission_objective/mission_objective_templates")
        local def = ok and T and T.op_no_mans_land and T.op_no_mans_land.objectives[breach.OBJ]
        if not def then
            return nil
        end
        mos._objective_definitions[breach.OBJ] = def
    end
    return mos
end

function breach.objective_start(unit)
    local ok, err = pcall(function()
        local mos = breach.objective_system()
        if mos then
            mos:start_mission_objective(breach.OBJ)
            mos:add_marker(breach.OBJ, nil, unit)
            breach.objective_on = true
        end
    end)
    if not ok then
        mod:error("breach objective: %s", tostring(err))
    end
end

function breach.objective_end()
    if not breach.objective_on then
        return
    end
    breach.objective_on = nil
    pcall(function()
        local mos = breach.objective_system()
        if mos and is_server() then
            mos:end_mission_objective(breach.OBJ)
        end
    end)
end

function breach.remove_charge()
    breach.objective_end()
    local u = breach.charge_unit
    breach.charge_unit = nil
    if u and unit_ok(u) then
        pcall(Unit.flow_event, u, "interactable_disable")
        pcall(Unit.flow_event, u, "remove")
        pcall(function()
            Managers.state.unit_spawner:mark_for_deletion(u)
        end)
    end
end

function breach.update(dt, pu, here)
    if not is_server() and not wall_broken then
        breach.objective_system() -- the definition has to be there before the host's start rpc arrives
    end
    if wall_broken or not (Data.wall and named["bc_wall"]) then
        breach.hold, breach.fuse, breach.planting = 0, nil, false
        if wall_broken and (breach.charge_unit or breach.objective_on) then
            breach.remove_charge() -- the wall went some other way (a grenade, another explosive)
        end
        return
    end
    -- 0.2.16 hotfix 3: every peer loads the charge packages, whatever its own breach_charge setting (the host's prop
    -- reaches all clients); the host waits CHARGE_DELAY s after its map is up so clients can finish loading them
    breach.load_charge()
    breach.since = (breach.since or 0) + dt
    if mod:get("breach_charge") ~= false and not breach.charge_failed then
        if breach.pkg_state == "ready" and is_server() and not breach.charge_unit and breach.since >= breach.CHARGE_DELAY then
            breach.spawn_charge()
        end
    end
    -- the plant itself goes through the prop's interaction when it is up (a client trusts its host to have spawned it)
    local legacy = mod:get("breach_charge") == false or breach.charge_failed or breach.pkg_state == "failed"
    if breach.fuse then
        local before = math.ceil(breach.fuse)
        breach.fuse = breach.fuse - dt
        if breach.fuse <= 0 then
            breach.fuse = nil
            if is_server() then
                Extra.emit("w:1")
            else
                breach.blast()
            end
        elseif math.ceil(breach.fuse) < before then
            breach.notify(string.format("Breach charge: %d", math.ceil(breach.fuse)))
        end
        return
    end
    local d, dz = breach.dist(here)
    if d > breach.HINT_RANGE or dz > 5 then
        breach.hold, breach.planting = 0, false
        return
    end
    if not breach.hinted then
        breach.hinted = true
        breach.notify(legacy and "The way is walled off. Hold Interact at the wall to plant a breach charge."
            or "The way is walled off. Plant the breach charge on the wall.")
    end
    if not legacy then
        return
    end
    local input = ScriptUnit.has_extension(pu, "input_system")
    local ok, held = false, false
    if input and d <= breach.PLANT_RANGE then
        ok, held = pcall(input.get, input, "interact_hold")
    end
    if ok and held then
        if not breach.planting then
            breach.planting = true
            breach.notify("Planting the breach charge...")
        end
        breach.hold = breach.hold + dt
        if breach.hold >= breach.PLANT_TIME then
            breach.hold, breach.planting = 0, false
            breach.fuse = breach.FUSE_TIME
            breach.notify("Charge planted. Stand back!")
            say("breach charge planted, %d s fuse", breach.FUSE_TIME)
        end
    elseif breach.planting then
        breach.hold, breach.planting = 0, false
        breach.notify("Planting cancelled")
    end
end

-- ---------------------------------------------------------------------------------------------------- map lifecycle
local function reset_gameplay()
    wall_broken = false
    breach.hold, breach.fuse, breach.hinted, breach.planting = 0, nil, false, false
    breach.remove_charge()
    breach.charge_failed, breach.since, breach.sog_ready = nil, 0, nil
    director.reset()
    dtpace.reset(false)
    jobs, tracked, pickups, roams, bosses = {}, {}, nil, nil, nil
    reset_comms()
    running, fired, flags, completed = {}, {}, {}, false
    bake_tiles, bake_wanted, bake_count = {}, {}, 0
    mod._bell_full_bake = nil
    counts = { spawned = 0, dropped = 0, queued = 0 }
    finish_navbake(nil)
    reset_vt2nav()
    Extra.reset()
end

-- VT2's death-zone volume(s) (Data.kill_zones, from the level's own volume data): standing in one counts like falling out of the map
local function in_kill_zone(l)
    local x, y, z = Vector3.x(l), Vector3.y(l), Vector3.z(l)
    for _, kz in ipairs(Data.kill_zones or {}) do
        if z >= kz.alt_min - 1 and z <= kz.alt_max + 1 then
            local inside, pts, j = false, kz.pts, #kz.pts
            for i = 1, #pts do
                local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
                if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
                    inside = not inside
                end
                j = i
            end
            if inside then
                return true
            end
        end
    end
    return false
end

local progress_pos = nil
local rescue_t = 0
local function update_rescue(dt)
    rescue_t = rescue_t + dt
    if rescue_t < 0.25 then
        return
    end
    rescue_t = 0
    local player = local_player()
    local pu = player and player.player_unit
    if not (unit_ok(pu) and base_box) then
        return
    end
    local wp = Unit.world_position(pu, 1)
    local l = to_level(wp)
    local floor_z = -RESCUE_BELOW
    if Vector3.z(l) > floor_z and not in_kill_zone(l) then
        progress_pos = { Vector3.x(l), Vector3.y(l), Vector3.z(l) }
    else
        local from = progress_pos or Data.start[1]
        local i = nearest_in(Data.respawns or {}, from)
        local target = i and Data.respawns[i] or Data.start[1]
        local pos = W({ target[1], target[2], target[3] + 0.5 })
        local g = ground_below(pos, 2, 8)
        teleport_to(g and (g + Vector3(0, 0, 0.2)) or pos)
        say("caught you falling; back on the path")
    end
end

Extra.setup({
    data = Data,
    base = function() return base_box and base_box:unbox() or nil end,
    scale = function() return MAP_SCALE end,
    named = function() return named end,
    local_player = local_player,
    in_map = in_map,
    is_server = is_server,
    map_ready = function() return map_ready end,
    show_comm_id = show_comm_id,
    queue_comm = queue_comm,
    wall_blast = breach.blast,
    holds = director.holds_sync,
    local_near = function(pos_level, radius, dz)
        local player = local_player()
        local pu = player and player.player_unit
        if not (base_box and unit_ok(pu)) then
            return false
        end
        local l = to_level(Unit.world_position(pu, 1))
        return Vector3.length(Vector3.flat(l - v3(pos_level))) < radius and math.abs(Vector3.z(l) - pos_level[3]) < dz
    end,
})

local function map_built()
    map_ready = true
    reset_gameplay()
    local okh, errh = pcall(host_level.hide)
    if not okh then
        mod:error("hiding the host level failed: %s", tostring(errh))
    end
    local okl, errl = pcall(breach.dtl_place)
    if not okl then
        mod:error("Darktide ladders: %s", tostring(errl))
    end
    local oks, errs = pcall(breach.sog_preload)
    if not oks then
        mod:error("Sprayer Ogryn packages: %s", tostring(errs))
    end
    teleport_in()
    if is_server() then
        local ok, err = pcall(build_gameplay)
        if not ok then
            mod:error("gameplay setup failed: %s", tostring(err))
        end
    end
    say("The Bell is ready (%d units). %s", #units, mod:get("vt2_navmesh_test") == true and "Loading the VT2 navmesh; enemies wait for it." or "The navmesh is baked around you as you go.")
    queue_comm("intro_a", 4); queue_comm("intro_b", 14); queue_comm("intro_c", 24)
    -- audio, the intro cutscene, story pieces at rest, one-way planes (bell_extra.lua)
    local ok, err = pcall(Extra.on_map_built)
    if not ok then
        mod:error("Bell world setup failed: %s", tostring(err))
    end
end

mod.update = function(dt)
    if want_auto and current_mission() ~= nil then
        want_auto = false
        if current_mission() == MISSION_KEY then
            auto_enter = 3
        end
    end
    if spawn_queue then
        local world = level_world()
        if world and base_box then
            local base = base_box:unbox()
            for _ = 1, SPAWNS_PER_FRAME do
                local row = table.remove(spawn_queue)
                if not row then
                    break
                end
                -- spawned with the map scale in the pose so the collision is created scaled too
                local pose = Matrix4x4.from_quaternion_position(Quaternion.identity(), base + Vector3(row[2], row[3], row[4] or 0) * MAP_SCALE)
                Matrix4x4.set_scale(pose, Vector3(MAP_SCALE, MAP_SCALE, MAP_SCALE))
                local unit = World.spawn_unit_ex(world, UNIT_PREFIX .. row[1], nil, pose)
                if unit then
                    units[#units + 1] = unit
                    unit_set[unit] = true
                    named[row[1]] = unit
                end
            end
            if #spawn_queue == 0 then
                spawn_queue = nil
                map_built()
            end
        end
        return
    end
    if base_wait then
        base_wait = base_wait - dt
        mod._base_poll = (mod._base_poll or 0) - dt
        local got = false
        if mod._base_poll <= 0 then
            mod._base_poll = 0.5
            got = Extra.host_base() ~= nil
        end
        if got or base_wait <= 0 then
            if not got then
                say("no map origin from the host; using the shared grid origin")
            end
            base_wait = false
            start_spawning()
        end
    end
    if auto_enter then
        local player = local_player()
        if player and unit_ok(player.player_unit) then
            auto_enter = auto_enter - dt
            if auto_enter <= 0 then
                auto_enter = nil
                request_enter()
            end
        end
    end
    dtpace.update_host()
    if not (map_ready and base_box and #units > 0) then
        return
    end
    update_rescue(dt)
    Extra.update(dt)
    update_navbake(dt)
    update_vt2nav(dt)
    local player = local_player()
    local pu = player and player.player_unit
    if not unit_ok(pu) then
        return
    end
    local here = Unit.world_position(pu, 1)
    auto_navbake(here, dt)
    update_comms(dt, here)
    breach.update(dt, pu, here)
    breach.ladder_update(dt, pu, here)
    if is_server() then
        dtpace.quiet_update(dt)
        dtpace.update(dt)
        process_jobs(dt)
        update_pickups(here, dt)
        if not dtpace.quiet() then
            update_roams(here, dt)
            director.update(dt, here)
            director.flow(dt, here)
        end
        update_bosses(here, dt)
        update_triggers(dt)
        update_events(dt)
        nudge_stuck(dt)
        dtpace.aggro_update(dt)
    end
end

local function go_back()
    local player = local_player()
    local player_unit = player and player.player_unit
    if return_pos and unit_ok(player_unit) then
        PlayerMovement.teleport(player, return_pos:unbox(), Unit.world_rotation(player_unit, 1))
        clear_fall_speed(player_unit)
        say("back")
    end
    return_pos = nil
    map_ready = false
    dtpace.restore()
    if not mod:get("keep_map") then
        despawn_all()
        reset_gameplay()
    end
end

local function debug()
    local ok, why = gate()
    local session = Managers.multiplayer_session
    say("gate: %s%s | host type: %s | mission: %s | server: %s", tostring(ok), why and (" (" .. why .. ")") or "",
        session and tostring(session:host_type()) or "none", tostring(current_mission()), tostring(is_server()))
    local n_loaded = 0
    for _ in pairs(loaded_chunks) do
        n_loaded = n_loaded + 1
    end
    say("assets: %s, chunks loaded %d / %d, spawned %d, queued %d", load_state, n_loaded, #Layout.chunks, #units,
        spawn_queue and #spawn_queue or 0)
    local nb = 0
    for _ in pairs(bake_tiles) do
        nb = nb + 1
    end
    say("navmesh: nav world %s, %d bakes done, %d tiles, running %s, wanted %d",
        tostring(nav_world() ~= nil), bake_count, nb, navbake and string.format("%.0f s (%d chunks, %d seeds)", navbake.t, navbake.chunks, navbake.seeds) or "no", #bake_wanted)
    say("VT2 navmesh: %s%s%s | nav tag volumes %d", tostring(vt2nav.state), vt2nav.src and (" from " .. vt2nav.src) or "",
        vt2nav.why and (" (" .. vt2nav.why .. ")") or "", #tag_vols)
    say("Darktide pacing: %s | VT2 spawners with a navmesh exit: %d of %d", dtpace.failed and "failed" or tostring(dtpace.state or "off"),
        dtpace.fakes and #dtpace.fakes or 0, #dtpace.rows)
    say("%s", Extra.debug())
    local alive = { patrol = 0, event = 0, boss = 0, special = 0 }
    for unit, rec in pairs(tracked) do
        if unit_ok(unit) and HEALTH_ALIVE[unit] then
            alive[rec.tag or "event"] = (alive[rec.tag or "event"] or 0) + 1
        end
    end
    say("minions: %d spawned, %d dropped (no navmesh), %d waiting | alive patrol %d, event %d, boss %d, special %d",
        counts.spawned, counts.dropped, #jobs, alive.patrol, alive.event, alive.boss, alive.special)
    local pdone = 0
    for _, p in ipairs(pickups or {}) do
        if p.done then
            pdone = pdone + 1
        end
    end
    local rdone = 0
    for _, r in ipairs(roams or {}) do
        if r.spawned then
            rdone = rdone + 1
        end
    end
    say("pickups %d / %d placed | patrols %d / %d spawned | events fired: bell %s ogre %s escape %s | completed %s",
        pdone, pickups and #pickups or 0, rdone, roams and #roams or 0, tostring(fired.bell), tostring(fired.ogre),
        tostring(fired.escape), tostring(completed))
    local player = local_player()
    local pu = player and player.player_unit
    if base_box and unit_ok(pu) then
        local l = to_level(Unit.world_position(pu, 1))
        local NavQueries = require("scripts/utilities/nav_queries")
        local nw = nav_world()
        local mp = nw and NavQueries.position_on_mesh(nw, Unit.world_position(pu, 1), 2, 2)
        say("you are at VT2 %.0f, %.0f, %.0f | navmesh under you: %s", Vector3.x(l), Vector3.y(l), Vector3.z(l), tostring(mp ~= nil))
    end
end

local TP = { start = Data.start[1], lever = Data.lever, bell = Data.bell, ["end"] = Data.end_zone }

mod:command("bell", mod:localize("cmd_desc"), function(arg, arg2)
    if arg == "back" then
        go_back()
    elseif arg == "debug" then
        debug()
        say("first wall: %s", named["bc_wall"] and "standing" or (wall_broken and "blown" or "not built"))
        local p = local_player()
        if named["bc_wall"] and p and unit_ok(p.player_unit) then
            local d, dz = breach.dist(Unit.world_position(p.player_unit, 1))
            say("first wall is %.1f m away (height %.1f m), map size %.2f", d, dz, MAP_SCALE)
            local cu = breach.charge_unit
            if cu and unit_ok(cu) then
                local cp = Unit.world_position(cu, 1)
                local cl = to_level(cp)
                say("breach charge %.1f m away at VT2 %.1f, %.1f, %.1f", Vector3.length(cp - Unit.world_position(p.player_unit, 1)),
                    Vector3.x(cl), Vector3.y(cl), Vector3.z(cl))
            else
                say("breach charge: %s", breach.charge_failed and "failed (hold Interact at the wall)" or "not spawned")
            end
        end
    elseif arg == "blast" then
        if wall_broken or not named["bc_wall"] then
            say("no wall to open")
        elseif is_server() then
            Extra.emit("w:1")
        else
            breach.blast()
        end
    elseif arg == "bake" then
        local player = local_player()
        local pu = player and player.player_unit
        if base_box and unit_ok(pu) then
            local l = to_level(Unit.world_position(pu, 1))
            if not bake_around({ Vector3.x(l), Vector3.y(l), Vector3.z(l) }, AUTO_RADIUS, true) then
                say("a bake is already running")
            end
        else
            say("build the map first (/bell)")
        end
    elseif arg == "tp" then
        local t = TP[arg2 or "start"]
        if t and base_box then
            local pos = W({ t[1], t[2], t[3] + 1 })
            local g = ground_below(pos, 3, 12)
            teleport_to(g and (g + Vector3(0, 0, 0.2)) or pos)
        else
            say("/bell tp start | lever | bell | end (after the map is built)")
        end
    elseif arg == "event" then
        if arg2 and EVENTS[arg2] and map_ready then
            fired[arg2] = nil
            start_event(arg2)
        else
            say("/bell event bell | ogre | escape")
        end
    else
        request_enter()
    end
end)

mod.on_game_state_changed = function(status, state_name)
    if state_name == "StateGameplay" and status == "exit" then
        dtpace.reset(true)
        reset_gameplay()
        despawn_all()
        return_pos, auto_enter, progress_pos, base_wait = nil, nil, nil, nil
        if lib_ticket or next(chunk_tickets) then
            release_pending = true
        end
    elseif state_name == "StateGameplay" and status == "enter" then
        if release_pending then
            release_pending = false
            release_all()
        end
        -- the mission manager does not exist yet at this point: check in update
        want_auto = true
    end
end

mod.on_disabled = function()
    Extra.unload()
    despawn_all()
end

mod.on_unload = function()
    Extra.unload()
    despawn_all()
end
