local mod = get_mod("QIangIQsNovitiate")
local N = mod.nov

-- The Novitiate's own class icons, in place of the Zealot's:
--   coin (Custom/nov_coin): the talent tree start node.
--   emblem (Custom/nov_emblem, white fleur-de-lis): the class symbol in front
--     of the player name on the HUD, before "Novitiate" on the character
--     list, the list watermark and the talent tree banner badge.
-- The PNGs (_icons/coin.png, emblem.png, drawn from _icons/icons.html) are
-- wrapped in one-quad units by _icons/build_nov_icons.py and compiled into
-- this mod's Custom Assets build, the QIangIQsCrossbow HUD icon way: the
-- quads are never spawned, loading them makes the textures
-- content/mods/qiangiq_novitiate/<name>_material_0_bca resident, and
-- ui_default_base shows them as texture_map. Without Custom Assets (or
-- before its patcher ran) the Zealot icons stay.
-- The class symbol is a font glyph in the game's text (UISettings.
-- archetype_font_icon), so the glyph is swapped for spaces and the emblem
-- is drawn over them by an added texture pass.

local UISettings = require("scripts/settings/ui/ui_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local UI_BASE = "content/ui/materials/base/ui_default_base"
local TEXTURES = {
	coin = "content/mods/qiangiq_novitiate/nov_coin_material_0_bca",
	emblem = "content/mods/qiangiq_novitiate/nov_emblem_material_0_bca",
}
local ASSETS = {
	coin = "QIangIQsNovitiate:nov_coin",
	emblem = "QIangIQsNovitiate:nov_emblem",
}
-- Proxima Nova spaces are narrow (about a fifth of an em): seven cover a one
-- em icon and the gap after it (five overlapped the "N", 2026-10-26).
local GAP = "       "

local ready = {}

local function _on()
	return mod:get("class_icons") ~= false
end

local function _texture(key)
	return _on() and ready[key] and TEXTURES[key] or nil
end

N.class_icon_texture = _texture

local function _set_texture(widget, style_id, content_id, texture)
	local style = widget.style[style_id]

	if not style then
		return
	end

	style.material_values = style.material_values or {}

	if widget.content[content_id] ~= UI_BASE or style.material_values.texture_map ~= texture then
		widget.content[content_id] = UI_BASE
		style.material_values.texture_map = texture
		widget.dirty = true
	end
end

-- Talent tree ------------------------------------------------------------------

local function _tree_view_update(view)
	if not (N.tree_active and N.tree_active()) then
		return
	end

	local coin = _texture("coin")
	local widgets = coin and view._node_widgets

	if widgets then
		for i = 1, #widgets do
			local widget = widgets[i]
			local node = widget.content.node_data

			if node and node.type == "start" then
				_set_texture(widget, "icon", "icon", coin)
			end
		end
	end

	local emblem = _texture("emblem")
	local banner = emblem and view._widgets_by_name and view._widgets_by_name.info_banner
	local badge = banner and banner.style.badge

	if badge then
		badge.material_values = badge.material_values or {}

		if badge.material_values.badge ~= emblem then
			badge.material_values.badge = emblem
			banner.dirty = true
		end
	end
end

mod:hook_require("scripts/ui/views/talent_builder_view/talent_builder_view", function (TalentBuilderView)
	mod:hook_safe(TalentBuilderView, "update", function (self)
		_tree_view_update(self)
	end)
end)

-- realms_loadout's talent screen is a subclass made before these hooks, so it
-- needs its own (running twice is harmless, the update only sets textures).
mod:hook_safe("RealmsLoadoutTalentView", "update", function (self)
	_tree_view_update(self)
end)

-- Character list ---------------------------------------------------------------

local TITLE_ICON = 18

mod:hook_require("scripts/ui/pass_templates/character_select_pass_templates", function (CharacterSelectPassTemplates)
	local passes = CharacterSelectPassTemplates.character_select

	if type(passes) ~= "table" or passes.__nov_icons then
		return
	end

	passes.__nov_icons = true

	-- Sits on the spaces in front of "Novitiate", in the archetype title's box
	-- (character_select_pass_templates.lua: left, vertically centred, 54 high,
	-- text at the bottom, y offset 12 or -1 with or without a player title).
	passes[#passes + 1] = {
		pass_type = "texture",
		style_id = "nov_title_emblem",
		value = UI_BASE,
		value_id = "nov_title_emblem",
		style = {
			horizontal_alignment = "left",
			vertical_alignment = "center",
			offset = { 0, 0, 2 },
			size = { TITLE_ICON, TITLE_ICON },
			color = { 255, 255, 255, 255 },
			material_values = {},
		},
		visibility_function = function (content)
			return content.nov_title_emblem_texture ~= nil
		end,
		change_function = function (content, style)
			local title_style = content.nov_title_style

			style.material_values.texture_map = content.nov_title_emblem_texture

			-- true_level rewrites the title ("Novitiate - 70") after us and
			-- drops the spaces the emblem sits on; put them back.
			local title = content.character_archetype_title

			if content.nov_title_emblem_texture and type(title) == "string" and string.sub(title, 1, #GAP) ~= GAP then
				content.character_archetype_title = GAP .. string.gsub(title, "^%s+", "")
			end

			if title_style then
				style.offset[1] = title_style.offset[1]
				style.offset[2] = title_style.offset[2] + title_style.size[2] * 0.5 - TITLE_ICON * 0.5 - 1
				style.color[1] = title_style.text_color[1]
				style.color[2] = title_style.text_color[2]
				style.color[3] = title_style.text_color[3]
				style.color[4] = title_style.text_color[4]
			end
		end,
	}
end)

local function _list_widget(widget, profile)
	local content = widget.content
	local emblem = N.is_novitiate_profile(profile) and _texture("emblem")

	content.nov_title_emblem_texture = nil

	if not emblem then
		return
	end

	-- The title is "<glyph> Novitiate <level> " (ProfileUtils.character_archetype_title).
	local name = mod:localize("archetype_novitiate")

	content.character_archetype_title = string.format("%s%s %s ", GAP, name, tostring(profile.current_level))
	content.nov_title_emblem_texture = emblem
	content.nov_title_style = widget.style.character_archetype_title

	if widget.style.archetype_icon then
		_set_texture(widget, "archetype_icon", "archetype_icon", emblem)
	end
end

-- Character details (main menu, under the 3D character): the big class badge
-- above the name becomes the coin, and the title drops the Zealot glyph.
local BADGE_SIZE = 150
local BADGE_BOX = 240

local function _details_widget(widget, profile)
	local style = widget.style.style_id_1
	local coin = N.is_novitiate_profile(profile) and _texture("coin")

	if not (style and style.size) then
		return
	end

	if not style.__nov_size then
		style.__nov_size = { style.size[1], style.size[2] }
	end

	if not coin then
		style.size[1] = style.__nov_size[1]
		style.size[2] = style.__nov_size[2]

		if style.offset and style.__nov_offset then
			style.offset[2] = style.__nov_offset[2]
		end

		return
	end

	if not style.__nov_offset and style.offset then
		style.__nov_offset = { style.offset[1], style.offset[2] }
	end

	style.size[1] = BADGE_SIZE
	style.size[2] = BADGE_SIZE

	-- Centred in the badge's 240 px box so it clears the name below.
	if style.offset and style.__nov_offset then
		style.offset[2] = style.__nov_offset[2] + (BADGE_BOX - BADGE_SIZE) * 0.5
	end
	style.material_values = style.material_values or {}
	style.material_values.texture_map = coin
	widget.content.archetype_icon = UI_BASE
	widget.content.character_archetype_title = string.format("%s - %s ", mod:localize("archetype_novitiate"), tostring(profile.current_level))
	widget.dirty = true
end

-- hook_require can run its callback more than once for the same class
-- (DMF then logs "Attempting to rehook active hook"), so hook each class once.
local main_menu_hooked = {}

mod:hook_require("scripts/ui/views/main_menu_view/main_menu_view", function (MainMenuView)
	if main_menu_hooked[MainMenuView] then
		return
	end

	main_menu_hooked[MainMenuView] = true

	mod:hook(MainMenuView, "_set_player_profile_information", function (func, self, profile, widget, ...)
		if N.apply_solo_level then
			N.apply_solo_level(profile)
		end

		func(self, profile, widget, ...)

		if widget and profile then
			_list_widget(widget, profile)
		end
	end)

	mod:hook(MainMenuView, "_show_character_details", function (func, self, show, profile, ...)
		if N.apply_solo_level then
			N.apply_solo_level(profile)
		end

		func(self, show, profile, ...)

		local widget = self._widgets_by_name and self._widgets_by_name.character_info

		if show and widget and profile then
			_details_widget(widget, profile)
		end
	end)
end)

-- HUD player name ----------------------------------------------------------------

local PANEL_DEFINITIONS = {
	"scripts/ui/hud/elements/personal_player_panel/hud_element_personal_player_panel_definitions",
	"scripts/ui/hud/elements/personal_player_panel_hub/hud_element_personal_player_panel_hub_definitions",
	"scripts/ui/hud/elements/team_player_panel/hud_element_team_player_panel_definitions",
	"scripts/ui/hud/elements/team_player_panel_hub/hud_element_team_player_panel_hub_definitions",
}

local function _add_name_pass(definitions)
	local widget_definitions = definitions and definitions.widget_definitions
	local definition = widget_definitions and widget_definitions.player_name

	if not definition or definition.__nov_icons then
		return
	end

	definition.__nov_icons = true

	UIWidget.add_definition_pass(definition, {
		pass_type = "texture",
		style_id = "nov_emblem",
		value = UI_BASE,
		value_id = "nov_emblem",
		style = {
			horizontal_alignment = "left",
			vertical_alignment = "top",
			offset = { 0, 0, 5 },
			size = { 16, 16 },
			color = { 255, 255, 255, 255 },
			material_values = {},
		},
		visibility_function = function (content)
			return content.nov_emblem_texture ~= nil
		end,
	})
end

for i = 1, #PANEL_DEFINITIONS do
	mod:hook_require(PANEL_DEFINITIONS[i], _add_name_pass)
end

local function _local_novitiate(player)
	if not player or player.__deleted then
		return false
	end

	local players = Managers.player
	local me = players and players:local_player_safe(1)

	if player ~= me then
		return false
	end

	local ok, character_id = pcall(player.character_id, player)

	return ok and N.is_novitiate_id(character_id) and player:archetype_name() == "zealot"
end

local function _name_prefix(func, self, player, ...)
	local emblem = _local_novitiate(player) and _texture("emblem")

	-- The game builds the prefix once per slot; rebuild it when the
	-- emblem comes or goes.
	if (emblem ~= nil) ~= (self.__nov_emblem ~= nil) then
		self._player_name_prefix = nil
		-- who_are_you and true_level rebuild the name from the prefix once;
		-- let them pick up the new one.
		self.wru_modified = false
		self.tl_modified = false
	end

	func(self, player, ...)

	local prefix = self._player_name_prefix

	self.__nov_emblem = nil

	if not (emblem and prefix) then
		return
	end

	-- "{#color(r,g,b)}<glyph>{#reset()} ": the glyph becomes spaces, the
	-- space after the reset tag stays.
	local symbol = UISettings.archetype_font_icon and UISettings.archetype_font_icon.zealot
	-- ("symbol and string.find(...)" would keep only the first result.)
	local s, e

	if symbol then
		s, e = string.find(prefix, symbol, 1, true)
	end

	if s then
		self._player_name_prefix = string.sub(prefix, 1, s - 1) .. string.sub(GAP, 2) .. string.sub(prefix, e + 1)
	end

	local slot = player.slot and player:slot()
	local color = slot and UISettings.player_slot_colors[slot]

	self.__nov_emblem = emblem
	self.__nov_emblem_color = color
end

local function _panel_update(self)
	local widget = self._widgets_by_name and self._widgets_by_name.player_name
	local style = widget and widget.style.nov_emblem

	if not style then
		return
	end

	local emblem = self.__nov_emblem

	if widget.content.nov_emblem_texture ~= emblem then
		widget.content.nov_emblem_texture = emblem
		widget.dirty = true
	end

	if not emblem then
		return
	end

	-- Other mods may set the name text themselves with their own glyph.
	local symbol = UISettings.archetype_font_icon and UISettings.archetype_font_icon.zealot
	local text_value = widget.content.text

	if symbol and type(text_value) == "string" then
		local s, e = string.find(text_value, symbol, 1, true)

		if s then
			widget.content.text = string.sub(text_value, 1, s - 1) .. string.sub(GAP, 2) .. string.sub(text_value, e + 1)
			widget.dirty = true
		end
	end

	local text = widget.style.text
	local font_size = text.font_size or 16
	local icon = math.floor(font_size + 0.5)

	style.material_values.texture_map = emblem
	style.size[1] = icon
	style.size[2] = icon
	-- Line the emblem up with the first glyph of the text. A text style
	-- without a size is aligned in the whole scenegraph area (the hub and
	-- personal panels: bottom of panel_background), one with a size inside
	-- its own box (2026-10-26: the emblem sat at the top of the panel).
	local valign = text.text_vertical_alignment or "top"
	local descent = math.floor(font_size * 0.12)

	style.offset[1] = text.offset[1]
	style.offset[3] = text.offset[3] + 1

	if text.size and text.size[2] then
		style.vertical_alignment = "top"

		if valign == "bottom" then
			style.offset[2] = text.offset[2] + text.size[2] - icon - descent
		elseif valign == "center" then
			style.offset[2] = text.offset[2] + math.floor((text.size[2] - icon) / 2)
		else
			style.offset[2] = text.offset[2] + descent
		end
	else
		style.vertical_alignment = valign

		if valign == "bottom" then
			style.offset[2] = text.offset[2] - descent
		elseif valign == "center" then
			style.offset[2] = text.offset[2]
		else
			style.offset[2] = text.offset[2] + descent
		end
	end

	local color = self.__nov_emblem_color

	if color then
		style.color[2] = color[2]
		style.color[3] = color[3]
		style.color[4] = color[4]
	end

	style.color[1] = text.text_color and text.text_color[1] or 255
end

mod:hook_require("scripts/ui/hud/elements/player_panel_base/hud_element_player_panel_base", function (HudElementPlayerPanelBase)
	mod:hook(HudElementPlayerPanelBase, "_update_player_name_prefix", _name_prefix)
	mod:hook_safe(HudElementPlayerPanelBase, "update", _panel_update)
end)

-- The panels are subclasses, and class() copies the base's methods when the
-- subclass is made. Other mods load the panels before this mod, so the
-- copies miss the base hooks above: hook the panels too, and pass straight
-- through when a copy is the base's hooked method (2026-10-26, the HUD kept
-- the Zealot glyph).
local PANEL_CLASSES = {
	"HudElementPersonalPlayerPanel",
	"HudElementPersonalPlayerPanelHub",
	"HudElementTeamPlayerPanel",
	"HudElementTeamPlayerPanelHub",
}

local function _base_method(name, func)
	local base = CLASSES and CLASSES.HudElementPlayerPanelBase

	return base ~= nil and func == rawget(base, name)
end

for i = 1, #PANEL_CLASSES do
	mod:hook(PANEL_CLASSES[i], "_update_player_name_prefix", function (func, self, ...)
		if _base_method("_update_player_name_prefix", func) then
			return func(self, ...)
		end

		return _name_prefix(func, self, ...)
	end)

	-- Idempotent, so running after the base hook too is harmless.
	mod:hook_safe(PANEL_CLASSES[i], "update", _panel_update)
end

-- Nameplates (Mourningstar) ------------------------------------------------------

-- The hub nameplates put the archetype glyph in front of the name in a
-- centred text. The glyph becomes spaces and the emblem is drawn where it
-- was, measured with UIRenderer.text_size.
local UIRenderer = require("scripts/managers/ui/ui_renderer")

local NAMEPLATE_TEMPLATES = {
	"scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate",
	"scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate_party_hud",
}

local function _text_width(ui_renderer, text, style, font_size)
	if text == "" then
		return 0
	end

	local ok, width = pcall(UIRenderer.text_size, ui_renderer, text, style.font_type, font_size)

	return ok and tonumber(width) or 0
end

local function _nameplate_update(ui_renderer, widget, marker)
	local content = widget.content
	local style = widget.style
	local emblem_style = style.nov_emblem
	local player = marker.data

	if not emblem_style then
		return
	end

	local emblem = type(player) == "table" and _local_novitiate(player) and _texture("emblem") or nil

	content.nov_emblem_texture = emblem

	if not emblem then
		return
	end

	local symbol = UISettings.archetype_font_icon and UISettings.archetype_font_icon.zealot
	local text = content.header_text

	if symbol and type(text) == "string" then
		local s, e = string.find(text, symbol, 1, true)

		if s then
			text = string.sub(text, 1, s - 1) .. string.sub(GAP, 2) .. string.sub(text, e + 1)
			content.header_text = text
		end
	end

	if type(text) ~= "string" or not ui_renderer then
		return
	end

	local header = style.header_text
	local font_size = header.font_size or 20
	local icon = math.floor(font_size + 0.5)
	local first_line = string.match(text, "^([^\n]*)") or text
	local _, lines = string.gsub(text, "\n", "\n")
	local gap_at = string.find(first_line, string.sub(GAP, 2), 1, true) or 1
	local before = string.sub(first_line, 1, gap_at - 1)
	local line_width = _text_width(ui_renderer, first_line, header, font_size)
	local before_width = _text_width(ui_renderer, before, header, font_size)
	local line_height = font_size * 1.2

	emblem_style.size[1] = icon
	emblem_style.size[2] = icon
	emblem_style.offset[1] = (header.offset[1] or 0) - line_width / 2 + before_width + icon / 2
	emblem_style.offset[2] = (header.offset[2] or 0) - lines * line_height / 2
	emblem_style.offset[3] = (header.offset[3] or 0) + 1
	emblem_style.color[1] = header.text_color and header.text_color[1] or 255
end

for i = 1, #NAMEPLATE_TEMPLATES do
	mod:hook_require(NAMEPLATE_TEMPLATES[i], function (template)
		if template.__nov_icons then
			return
		end

		template.__nov_icons = true

		local create = template.create_widget_defintion
		local update = template.update_function

		template.create_widget_defintion = function (...)
			local definition = create(...)

			if definition then
				UIWidget.add_definition_pass(definition, {
					pass_type = "texture",
					style_id = "nov_emblem",
					value = UI_BASE,
					value_id = "nov_emblem",
					style = {
						horizontal_alignment = "center",
						vertical_alignment = "center",
						offset = { 0, 0, 3 },
						size = { 20, 20 },
						color = { 255, 255, 255, 255 },
						material_values = {},
					},
					visibility_function = function (content)
						return content.nov_emblem_texture ~= nil
					end,
				})
			end

			return definition
		end

		template.update_function = function (parent, ui_renderer, widget, marker, ...)
			if update then
				update(parent, ui_renderer, widget, marker, ...)
			end

			local ok, err = pcall(_nameplate_update, ui_renderer, widget, marker)

			if ok then
				local emblem = widget.content.nov_emblem_texture

				if emblem then
					widget.style.nov_emblem.material_values.texture_map = emblem
				end
			elseif not template.__nov_error then
				template.__nov_error = true
				mod:error("Novitiate nameplate emblem: %s", tostring(err))
			end
		end
	end)
end

-- Loading ------------------------------------------------------------------------

local requested = false

local function _request()
	if requested then
		return
	end

	local custom_assets = get_mod("CustomAssets")

	if not custom_assets or not custom_assets.is_api_compatible or not custom_assets.is_api_compatible(1) then
		mod:info("Novitiate: Custom Assets (API 1) is not available, the Zealot class icons stay")

		return
	end

	requested = true

	for key, id in pairs(ASSETS) do
		local ticket, err = custom_assets.acquire(mod, id, function (_, _, load_error)
			if load_error then
				mod:error("%s failed to load: %s (run CUSTOM_ASSETS_PATCH.bat with the game closed)", id, tostring(load_error))

				return
			end

			ready[key] = true
		end, { resident = true, reference_name = id })

		if not ticket then
			mod:error("%s could not be requested: %s (run CUSTOM_ASSETS_PATCH.bat with the game closed)", id, tostring(err))
		end
	end
end

N.on_loaded[#N.on_loaded + 1] = _request

N.icons_status = function ()
	return string.format("Novitiate icons: %s (coin %s, emblem %s)", _on() and "on" or "off", ready.coin and "loaded" or "not loaded", ready.emblem and "loaded" or "not loaded")
end
