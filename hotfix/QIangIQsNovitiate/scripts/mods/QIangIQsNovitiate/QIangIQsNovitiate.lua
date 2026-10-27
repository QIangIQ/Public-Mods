local mod = get_mod("QIangIQsNovitiate")

-- Novitiate: a Zealot-based class variant. The backend owns characters and
-- archetypes (and NetworkLookup is built at boot), so a brand new archetype
-- cannot be added from a mod. Novitiate is the Zealot with its own look
-- (nov_visual.lua), its own talent tree (nov_tree.lua) and three combat
-- abilities: Chain Hook (nov_hook.lua), Deflect (nov_deflect.lua) and
-- Penitent Pyre (nov_pyre.lua). The tree and the abilities exist where the
-- game runs talents locally (host, Psykhanium, solo play); on Fatshark's
-- mission servers the official Zealot tree is used and nothing here runs.
--
-- The mod is standalone. Chain Hook, Deflect and the tree code are vendored
-- into this mod. Custom Assets (the Sister Lacrima model, the Roadhog hook
-- head) and QIangIQsScumHook (hook head model) are optional.

local MOD_DIR = "QIangIQsNovitiate/scripts/mods/QIangIQsNovitiate/"

local N = {
	abilities = {},
	loc_keys = {},
	loc_text = {},
	on_loaded = {},
	on_setting = {},
	on_update = {},
}

mod.nov = N

-- New names go at the end of the NetworkLookup tables so every existing id
-- keeps its index (same as QIangIQsLegacyTalents class_swap.lua).
N.append_lookup = function (lookup_name, name)
	local NetworkLookup = rawget(_G, "NetworkLookup") or require("scripts/network_lookup/network_lookup")
	local lookup = NetworkLookup[lookup_name]

	if not lookup then
		mod:error("NetworkLookup.%s is missing", lookup_name)

		return
	end

	if rawget(lookup, name) == nil then
		local index = #lookup + 1

		rawset(lookup, index, name)
		rawset(lookup, name, index)
	end
end

-- game loc key -> this mod's localization key
N.add_loc = function (map)
	for key, mod_key in pairs(map) do
		N.loc_keys[key] = mod_key
	end
end

-- game loc key -> final text
N.add_loc_text = function (map)
	for key, text in pairs(map) do
		N.loc_text[key] = text
	end
end

mod:hook(CLASS.LocalizationManager, "_lookup", function (func, self, key)
	local text = N.loc_text[key]

	if text then
		return text
	end

	local mod_key = N.loc_keys[key]

	if mod_key then
		return mod:localize(mod_key)
	end

	return func(self, key)
end)

local function _load(file)
	local ok, err = pcall(mod.io_dofile, mod, MOD_DIR .. file)

	if not ok then
		mod:error("Novitiate: %s failed to load: %s", file, tostring(err))
	end

	return ok
end

-- Order matters: the tree reads what the ability modules register.
_load("nov_lookup_guard")
_load("nov_roster")
_load("nov_loadout")
_load("nov_passives")
_load("nov_deflect")
_load("nov_hook")
_load("nov_pyre")
_load("nov_tree")
_load("nov_visual")
_load("nov_icons")
_load("nov_glyphs")
_load("nov_inventory")

local function _run(list, ...)
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)

		if not ok then
			mod:error("Novitiate: %s", tostring(err))
		end
	end
end

mod.on_setting_changed = function (setting_id)
	_run(N.on_setting, setting_id)
end

mod.on_all_mods_loaded = function ()
	_run(N.on_loaded)

	local martyrdom = get_mod("QIangIQsMartyrdom")

	if martyrdom and martyrdom.is_enabled and martyrdom:is_enabled() then
		mod:warning("QIangIQsMartyrdom is on and also edits the Zealot tree. Turn one of the two off: Novitiate replaces the whole Zealot tree.")
	end
end

mod.on_game_state_changed = function (status, state_name)
	if N.guard_network_lookup then
		local ok, err = pcall(N.guard_network_lookup)

		if not ok then
			mod:error("Novitiate: NetworkLookup guard failed: %s", tostring(err))
		end
	end
end

mod.update = function (dt, t)
	if #N.on_update > 0 then
		_run(N.on_update, dt, t)
	end
end

mod:command("novitiate", mod:localize("command_description"), function ()
	if N.roster_status then
		mod:echo(N.roster_status())
	end

	if N.tree_status then
		mod:echo(N.tree_status())
	end

	if N.visual_status then
		mod:echo(N.visual_status())
	end

	if N.icons_status then
		mod:echo(N.icons_status())
	end

	if N.hook_status then
		mod:echo("Chain Hook head model: %s", N.hook_status())
	end
end)
