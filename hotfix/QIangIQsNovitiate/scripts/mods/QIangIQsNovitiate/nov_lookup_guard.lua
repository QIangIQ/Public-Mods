local mod = get_mod("QIangIQsNovitiate")
local N = mod.nov

-- NetworkLookup guard (2026-10-27, a friend's crash on joining the official
-- Mourningstar as a new Novitiate: "AnimationStateMachine ... does not
-- exist" for grenade_tox_equipable, from a server correction).
-- The server sends weapon templates and abilities as indices into
-- NetworkLookup, which the game builds from the sorted names of
-- WeaponTemplates and PlayerAbilities. On that client the lookups had been
-- built after mods had added their own names to those tables, so the modded
-- names were sorted in among the game's names and every later index moved:
-- the server's unarmed_hub_human (hub hands) read as tox_grenade (5 names
-- earlier) and the server's zealot_targeted_dash / zealot_shock_grenade read
-- as zealot_invisibility_improved / zealot_invisibility (3 earlier, the
-- three Novitiate abilities). The client then tried to play a tox grenade
-- animation it never loaded.
-- This puts the game's own names back at the indices the server uses: the
-- game's names in the game's order first, every other name after them in
-- the order it had. The game's names are read from the game's own files
-- (package.loaded), so nothing here needs to know which mod added what.
-- Runs when this mod loads and on every game state change (before a
-- network session starts); a repair is logged once per lookup with the
-- names that were in the way.

local WEAPON_TEMPLATE_PREFIX = "scripts/settings/equipment/weapon_templates/"
local ABILITY_FILE_PATTERN = "^scripts/settings/ability/player_abilities/abilities/[%w_]+_abilities$"

local reported = {}

local function _vanilla_weapon_templates()
	local WeaponTemplates = package.loaded["scripts/settings/equipment/weapon_templates/weapon_templates"]

	if type(WeaponTemplates) ~= "table" then
		return nil
	end

	local names = {}
	local seen = {}

	for path in pairs(package.loaded) do
		if type(path) == "string" and string.sub(path, 1, #WEAPON_TEMPLATE_PREFIX) == WEAPON_TEMPLATE_PREFIX then
			local name = string.match(path, "([^/]+)$")

			if name and not seen[name] and rawget(WeaponTemplates, name) ~= nil then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end

	table.sort(names)

	return names
end

local function _vanilla_player_abilities()
	local seen = {}
	local names = {}
	local files = 0

	for path, definition in pairs(package.loaded) do
		if type(path) == "string" and type(definition) == "table" and string.find(path, ABILITY_FILE_PATTERN) then
			files = files + 1

			for name in pairs(definition) do
				if type(name) == "string" and not seen[name] then
					seen[name] = true
					names[#names + 1] = name
				end
			end
		end
	end

	if files == 0 then
		return nil
	end

	table.sort(names)
	table.insert(names, 1, "not_equipped")

	return names
end

local function _repair(lookup_name, lookup, vanilla)
	if type(lookup) ~= "table" or not vanilla or #vanilla == 0 then
		return
	end

	local in_order = true

	for i = 1, #vanilla do
		if rawget(lookup, i) ~= vanilla[i] then
			in_order = false

			break
		end
	end

	if in_order then
		return
	end

	local is_vanilla = {}

	for i = 1, #vanilla do
		is_vanilla[vanilla[i]] = true
	end

	local count = #lookup
	local others = {}
	local in_the_way = {}

	for i = 1, count do
		local name = rawget(lookup, i)

		if name ~= nil and not is_vanilla[name] then
			others[#others + 1] = name

			if i <= #vanilla then
				in_the_way[#in_the_way + 1] = tostring(name)
			end
		end
	end

	-- Only a pure "sorted in" mix-up is repaired: the game's names, read in
	-- the lookup's order, must be exactly the game's list. Anything else
	-- (a name missing, another order) is left alone and logged.
	local filtered = 0

	for i = 1, count do
		local name = rawget(lookup, i)

		if name ~= nil and is_vanilla[name] then
			filtered = filtered + 1

			if vanilla[filtered] ~= name then
				filtered = -1

				break
			end
		end
	end

	if filtered ~= #vanilla then
		if not reported[lookup_name] then
			reported[lookup_name] = true
			mod:warning("NetworkLookup.%s does not match the game's own list and was left alone.", lookup_name)
		end

		return
	end

	for i = 1, count do
		local name = rawget(lookup, i)

		if name ~= nil then
			rawset(lookup, name, nil)
		end

		rawset(lookup, i, nil)
	end

	local index = 0

	for i = 1, #vanilla do
		index = index + 1
		rawset(lookup, index, vanilla[i])
		rawset(lookup, vanilla[i], index)
	end

	for i = 1, #others do
		index = index + 1
		rawset(lookup, index, others[i])
		rawset(lookup, others[i], index)
	end

	if not reported[lookup_name] then
		reported[lookup_name] = true
		mod:warning("NetworkLookup.%s had modded names among the game's names (%s); moved them after the game's %d names so the server's ids read right.", lookup_name, table.concat(in_the_way, ", "), #vanilla)
	end
end

local function _lookups()
	local result = {}
	local global = rawget(_G, "NetworkLookup")
	local loaded = package.loaded["scripts/network_lookup/network_lookup"]

	if type(global) == "table" then
		result[#result + 1] = global
	end

	if type(loaded) == "table" and loaded ~= global then
		result[#result + 1] = loaded
	end

	return result
end

N.guard_network_lookup = function ()
	local lookups = _lookups()

	if #lookups == 0 then
		return
	end

	local weapons = _vanilla_weapon_templates()
	local abilities = _vanilla_player_abilities()

	for i = 1, #lookups do
		local NetworkLookup = lookups[i]

		_repair("weapon_templates", rawget(NetworkLookup, "weapon_templates"), weapons)
		_repair("player_abilities", rawget(NetworkLookup, "player_abilities"), abilities)
	end
end

local ok, err = pcall(N.guard_network_lookup)

if not ok then
	mod:error("Novitiate: NetworkLookup guard failed: %s", tostring(err))
end
