local mod = get_mod("QIangIQsNovitiate")
local N = mod.nov

-- Which characters are Novitiates. The backend owns characters and their
-- archetypes, so a Novitiate is one of your Zealot characters marked as one
-- (option "roster_scope": marked characters only, or every Zealot). A marked
-- Zealot shows as "Novitiate" on the character list and in its details, and
-- only it gets the Novitiate tree and look; other Zealots keep the official
-- tree and their builds. Mark or unmark the selected Zealot on the character
-- select screen with the "Mark as Novitiate" keybind. Marks are saved in
-- this mod's settings by character id.

local ProfileUtils = require("scripts/utilities/profile_utils")
local UISettings = require("scripts/settings/ui/ui_settings")

local state = {
	-- Character picked on the character select screen (before the game
	-- has a local player profile for it).
	selected_id = nil,
	-- Character of the local player's profile, polled.
	player_id = nil,
	poll_t = 0,
}

N.on_roster_changed = {}

local function _marked()
	local marked = mod:get("novitiate_characters")

	return type(marked) == "table" and marked or {}
end

local function _changed()
	for i = 1, #N.on_roster_changed do
		local ok, err = pcall(N.on_roster_changed[i])

		if not ok then
			mod:error("Novitiate: %s", tostring(err))
		end
	end
end

N.is_novitiate_id = function (character_id)
	if mod:get("roster_scope") == "all_zealots" then
		return true
	end

	return character_id ~= nil and _marked()[character_id] == true
end

N.is_novitiate_profile = function (profile)
	local archetype = profile and profile.archetype

	return archetype ~= nil and archetype.name == "zealot" and N.is_novitiate_id(profile.character_id)
end

local function _player_profile()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player_safe(1)
	local ok, profile = pcall(function ()
		return player and player:profile()
	end)

	return ok and profile or nil
end

-- The character in use: the local player's once it has a profile, else the
-- one picked on the character select screen.
N.current_character_id = function ()
	return state.player_id or state.selected_id
end

-- Is the character in use a Novitiate? Unknown character (no profile yet,
-- nothing picked): only with the "every Zealot" option.
N.current_is_novitiate = function ()
	if mod:get("roster_scope") == "all_zealots" then
		return true
	end

	local id = N.current_character_id()

	return id ~= nil and _marked()[id] == true
end

local function _set_player_id(id)
	if id ~= state.player_id then
		state.player_id = id

		_changed()
	end
end

N.on_update[#N.on_update + 1] = function (dt, t)
	state.poll_t = state.poll_t - (dt or 0)

	if state.poll_t > 0 then
		return
	end

	state.poll_t = 0.5

	local profile = _player_profile()

	_set_player_id(profile and profile.character_id or nil)
end

-- ####################################################################
-- Character select screen
-- ####################################################################

local function _novitiate_title(profile, exclude_symbol)
	local name = mod:localize("archetype_novitiate")
	local icon = UISettings.archetype_font_icon and UISettings.archetype_font_icon.zealot

	-- With the Novitiate class icons on, the Zealot glyph is left out; the
	-- emblem is drawn where the title is shown (nov_icons.lua).
	local own_icon = N.class_icon_texture and N.class_icon_texture("emblem")

	if icon and not exclude_symbol and not own_icon then
		return string.format("%s %s", icon, name)
	end

	return name
end

mod:hook(ProfileUtils, "character_archetype_title", function (func, profile, exclude_symbol, ...)
	if profile and not table.is_empty(profile) and N.is_novitiate_profile(profile) then
		return _novitiate_title(profile, exclude_symbol)
	end

	return func(profile, exclude_symbol, ...)
end)

local function _refresh_main_menu(view, profile)
	local widgets = view._widgets_by_name or {}

	for name, widget in pairs(widgets) do
		local content = widget.content

		if string.find(name, "^character_slot_") and content and content.profile then
			pcall(view._set_player_profile_information, view, content.profile, widget)
		end
	end

	if profile and view._character_details_active then
		pcall(view._show_character_details, view, true, profile)
	end
end

mod:hook_require("scripts/ui/views/main_menu_view/main_menu_view", function (MainMenuView)
	mod:hook_safe(MainMenuView, "_event_selected_profile_changed", function (self, profile)
		local id = profile and profile.character_id

		if id ~= state.selected_id then
			state.selected_id = id

			_changed()
		end
	end)
end)

-- Keybind: mark or unmark the Zealot selected on the character select screen.
mod.toggle_novitiate_character = function ()
	local ui_manager = Managers.ui
	local view = ui_manager and ui_manager:view_active("main_menu_view") and ui_manager:view_instance("main_menu_view")
	local profile = view and view._selected_profile

	if not profile then
		mod:notify(mod:localize("roster_no_selection"))

		return
	end

	if not (profile.archetype and profile.archetype.name == "zealot") then
		mod:notify(mod:localize("roster_not_zealot"))

		return
	end

	local marked = table.clone(_marked())
	local id = profile.character_id
	local name = ProfileUtils.character_name(profile)

	if marked[id] then
		marked[id] = nil

		mod:notify(mod:localize("roster_unmarked", name))
	else
		marked[id] = true

		mod:notify(mod:localize("roster_marked", name))
	end

	mod:set("novitiate_characters", marked, false)

	if mod:get("roster_scope") == "all_zealots" then
		mod:notify(mod:localize("roster_scope_all_hint"))
	end

	_refresh_main_menu(view, profile)
	_changed()
end

N.on_setting[#N.on_setting + 1] = function (setting_id)
	if setting_id == "roster_scope" then
		_changed()
	end
end

N.roster_status = function ()
	local count = 0

	for _ in pairs(_marked()) do
		count = count + 1
	end

	return string.format("Novitiates: %s (%d marked), current character %s is %sa Novitiate", mod:get("roster_scope") == "all_zealots" and "every Zealot" or "marked Zealots", count, tostring(N.current_character_id()), N.current_is_novitiate() and "" or "not ")
end
