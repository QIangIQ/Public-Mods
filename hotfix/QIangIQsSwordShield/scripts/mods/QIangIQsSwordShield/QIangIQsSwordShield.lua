-- QIangIQ's Sword and Shield 0.6.10: the datamined sword-and-shield as a Zealot weapon.
--
-- What is datamined (A:\Dowloads\Darktide_NonMod\dauntless_datamine, INDEX.md "Sword + shield", Oct 11 2026 build):
--   * Retail units with their names in the dictionary: content/weapons/player/melee/combat_sword/attachments/blade_08/blade_08
--     and .../grip_08/grip_08. Node names (id32 match, A:\Dowloads\staging\swordshield\probe3.py): grip_08 has
--     ap_blade_01 at z 0.101 and ap_trinket_hook; blade_08 has fx_sweep (root) and fx_block (z 0.26).
--   * An UNNAMED heater shield unit 26b996dc3fdb55ff (no name, no textures). A retail unit can only be loaded by name,
--     so its datamined geometry is compiled as our own unit (Custom/heater_shield, build_shield_glb.py + DarktideGLBCompiler)
--     with a plain steel material (extrapolated: the unit ships no textures).
--   * NOT datamined: weapon template, item, animations. The colleagues' label combatsword_shield_p1_m1 (INDEX.md) is used
--     for the template and item name.
--
-- Built from released weapons (the QIangIQsDauntlessArmory pattern: template clone + NetworkLookup append + alias copy,
-- item clone into MasterItems.get_cached(), equip by override_slot):
--   * Rig, animations, block and weapon special = powermaul_shield_p1_m1 (power_maul_shields/powermaul_shield_p1_m1.lua):
--     the only human one-hander with a shield on the left arm (state machines assault_shield_maul, lines 1459-1460).
--   * 0.1.1: slots taken by path from the live item trees (the shield is a whole item in "left"; 0.1.0 looked for an
--     /attachments/ unit there and never built the item).
--   * Sword = the shaft slot of the shield maul becomes grip_08 (attach node of the maul shaft, LINK_MODE_NONE so it does not
--     follow same-named rig nodes, DauntlessArmory 0.2.0), with blade_08 on its ap_blade_01. Maul head and connector go.
--   * Shield = the retail assault shield stays in the item (it carries fx_display and fx_shield_special_active, and the hand
--     holds it); our heater is linked to its root and the retail shield is hidden. The heater was authored in the same frame:
--     both handles sit on -x (retail centroid -0.078, 0.200, 0.003; heater -0.090, 0.186, 0.001; probe4.py), the 1.5 cm
--     difference is baked into the compiled unit.
--
-- Custom moveset (0.4.0; actions grafted onto the sword-and-shield clips, see GRAFTS; damage profiles from
-- combatsword_damage_profile_templates.lua and power_maul_shield_damage_profile_templates.lua):
--   light chain   1 left diagonal cut        light_combatsword_linesman   faster (1.2)
--                 2 right diagonal cut       light_combatsword_linesman   faster (1.3)
--                 3 rising cut               light_combatsword_smiter     faster (1.2)
--                 4 shield poke              powermaul_shield_light_smiter_shield (blunt)
--   heavies       1 left diagonal cleave     heavy_combatsword
--                 2 right diagonal cleave    heavy_combatsword_smiter
--                 3 shield slam (4th swing)  powermaul_shield_heavy_tank_shield (blunt)
--   push follow   rising cut                 light_combatsword_linesman
--   0.4.0 shield arm: raised in first person by script (QIangIQsSwordShield_arm.lua, own driver unit Custom/ss_fp_driver).
--   block / special: the shield maul's own (block charges, shield push on release).
--   No power field (0.2.0): no shock buff or keyword, blunt wounds instead of shock wounds, power-field slot scripts
--   removed from the items, sword sounds/particles first in the alias copy.
-- Author: QIangIQ
local mod = get_mod("QIangIQsSwordShield")

local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")
local MasterItems = require("scripts/backend/master_items")
local NetworkLookup = require("scripts/network_lookup/network_lookup")

local TEMPLATE = "combatsword_shield_p1_m1"
local SOURCE_TEMPLATE = "powermaul_shield_p1_m1"
local SWORD_TEMPLATE = "combatsword_p1_m1"
local ITEM_ROOT = "content/items/weapons/player/melee/"
local ITEM = ITEM_ROOT .. "combatsword_shield_p1_m1"
local SOURCE_ITEM = ITEM_ROOT .. "powermaul_shield_p1_m1"
local SWORD_ITEM = ITEM_ROOT .. "combatsword_p1_m1"
local PART_ROOT = ITEM_ROOT .. "qiangiq_swordshield/"
local GRIP_ITEM = PART_ROOT .. "grip_08"
local BLADE_ITEM = PART_ROOT .. "blade_08"
local SHIELD_ITEM = PART_ROOT .. "shield"
-- the right-hand root of the source item tree (item log: right=content/items/weapons/player/melee/powermaul_p1_empty)
local RIGHT_ITEM = ITEM_ROOT .. "powermaul_p1_empty"
local SWORD_UNITS = "content/weapons/player/melee/combat_sword/attachments/"
local GRIP_UNIT = SWORD_UNITS .. "grip_08/grip_08"
local BLADE_UNIT = SWORD_UNITS .. "blade_08/blade_08"
local BLADE_NODE = "ap_blade_01"
local SHIELD_ASSET, SHIELD_UNIT = "QIangIQsSwordShield:heater_shield", "content/mods/qiangiq_swordshield/heater_shield"
local HUD_ICON_ASSET = "QIangIQsSwordShield:hud_icon"
local RETAIL_HUD_ICON = "content/ui/materials/icons/weapons/hud/combatsword_shield_p1_m1"
local DISPLAY = "loc_qiangiq_swordshield"

mod:add_global_localize_strings({
    loc_qiangiq_swordshield = { en = "Sword and Shield (datamined)" },
})

local function say(fmt, ...)
    local text = string.format(fmt, ...)

    mod:echo(text)
    mod:info(text)
end

-- Network lookups (QIangIQsShardStaff append_lookup): new names go at the end so no existing id moves -------------
local function append_lookup(lookup_name, key)
    local lookup = NetworkLookup[lookup_name]

    if not lookup then
        return false, "no lookup"
    end

    local existing = rawget(lookup, key)

    if existing then
        return true, existing
    end

    local index = #lookup + 1

    rawset(lookup, index, key)
    rawset(lookup, key, index)

    return true, index
end

-- Particle / sound aliases keyed by wielded_weapon_template (QIangIQsShardStaff alias_template_keys) --------------
local ALIAS_MODULES = {
    "scripts/settings/particles/player_character_particle_aliases",
    "scripts/settings/sound/player_character_sound_event_aliases",
}

-- 0.4.3 (user 2026-10-25: "electric cracking" audio): power field sounds and particles of the shield maul are not
-- copied where the alias has a default (player_character_sound_event_aliases.lua: weapon silence, e.g. :4975, :5150),
-- so the powermaul idle loop (:5162), electric sparks (:3749), shock swings (:3139, :3215) and the lightning charge-up
-- particles (player_character_particle_aliases.lua:455, :627, :645) fall back to that default.
local SHOCK_ALIAS_PATTERNS = { "shockmaul", "powermaul", "shock_maul", "electric", "lightning", "arbites_shield" }

local function is_shock_alias(value)
    if type(value) ~= "string" then
        return false
    end

    for _, pattern in ipairs(SHOCK_ALIAS_PATTERNS) do
        if string.find(value, pattern, 1, true) then
            return true
        end
    end

    return false
end

local function alias_keys(root, source, target, seen, counter, skip_shock)
    if type(root) ~= "table" or seen[root] then
        return
    end

    seen[root] = true

    local value = rawget(root, source)

    if value ~= nil and rawget(root, target) == nil then
        if skip_shock and is_shock_alias(value) and rawget(root, "default") ~= nil then
            counter.skipped = counter.skipped + 1
        else
            root[target] = value
            counter.n = counter.n + 1
        end
    end

    for _, child in pairs(root) do
        if type(child) == "table" then
            alias_keys(child, source, target, seen, counter, skip_shock)
        end
    end
end

local function copy_aliases(source, target, skip_shock)
    local counter = { n = 0, skipped = 0 }

    for _, path in ipairs(ALIAS_MODULES) do
        local ok, module = pcall(require, path)

        if ok then
            alias_keys(module, source, target, {}, counter, skip_shock)
        else
            mod:error("alias module %s: %s", path, tostring(module))
        end
    end

    if counter.skipped > 0 then
        mod:info("aliases %s -> %s: %d power field entries left on the default", source, target, counter.skipped)
    end

    return counter.n
end

-- Moveset (see the header) ----------------------------------------------------------------------------------------
-- 0.2.0: the attacks themselves are taken from the two shield maul marks, which share one state machine
-- (assault_shield_maul, powermaul_shield_p1_m1.lua:1334-1335 and powermaul_shield_p1_m2.lua:1543-1544), so every
-- animation event below exists for this rig. 0.1.x only changed damage, so it played exactly like the maul.
--   graft = { donor template, donor action }; chain = allowed_chain_actions rewired for this order
-- 0.4.0: the combat_sword_shield state machine (below) has the maul's states with only some clips replaced by its own
-- (A:\Dowloads\staging\swordshield\sm\align.py: its clip references aligned in file order against assault_shield_maul's).
-- Own sword-and-shield clips sit on the events attack_left_diagonal_down, attack_right_diagonal_down, attack_down,
-- attack_right_down (clip attack_down_right), attack_left_up (clip attack_up_left), attack_shield_poke,
-- heavy_charge/heavy_attack_left_diagonal_down, heavy_charge/heavy_attack_right_diagonal_down, heavy_charge/heavy_attack_down,
-- idle, parry, sprint, dodge, slide, inspect. attack_left, heavy_attack_right_down, heavy_charge_right_down_pose and the
-- shield slam stay Shield Maul clips, and 0.3.0 still used those, so it looked like the Arbites maul. Each slot now plays an
-- own clip; actions from templates outside the shield maul keep this template's chains and 3P events (keep = true).
-- The event -> clip pairing is read from the slot order, not from a decoded state graph.
local M1, M2 = "powermaul_shield_p1_m1", "powermaul_shield_p1_m2"
local GRAFTS = {
    -- light 1: left diagonal sword cut (combatsword_p1_m1 action_left_light, attack_left_diagonal_down, :147-239)
    -- from the m2 left windup (heavy_charge_left_diagonal_down, :213)
    action_melee_start_left = { M2, "action_melee_start_left" },
    action_light_1 = { "combatsword_p1_m1", "action_left_light", keep = true },
    -- heavy 1: diagonal cleave (m2 heavy_attack_left_diagonal_down, :395-470)
    action_heavy_1 = { M2, "action_heavy_1" },
    -- right windup + heavy 2: the one-handed power maul's right diagonal (powermaul_p1_m1 action_melee_start_right
    -- heavy_charge_right_diagonal_down :376-437, action_right_heavy heavy_attack_right_diagonal_down :528-604); in the
    -- shield maul state machine these slots held power_maul clips, so the power maul's timings were made for them
    action_melee_start_right = { "powermaul_p1_m1", "action_melee_start_right", keep = true },
    action_heavy_2 = { "powermaul_p1_m1", "action_right_heavy", keep = true },
    -- light 2 stays m1: right diagonal cut (m1 attack_right_diagonal_down :525-612)
    -- push follow-up: rising cut (m2 action_pushfollow attack_left_up, :1303-1386)
    action_pushfollow = { M2, "action_pushfollow", keep = true },
    -- light 3: rising cut (m2 attack_left_up, :757-845) from the m2 second left windup (:696)
    action_melee_start_left_2 = { M2, "action_melee_start_left_2" },
    action_light_3 = { M2, "action_light_3" },
    -- light 4 / heavy 3: shield poke and shield slam from the m1 shield windup (m1 :690-838 and :389-465)
    action_melee_start_right_2 = { M1, "action_melee_start_left_2", chain = { light_attack = "action_light_4", heavy_attack = "action_heavy_3" } },
    action_light_4 = { M1, "action_light_3", chain = { start_attack = "action_melee_start_left" } },
    action_heavy_3 = { M1, "action_heavy_1" },
}

-- Damage per action. Sword hits use the combat sword's profiles with its wound shapes (combatsword_p1_m1.lua:238-832):
-- WoundsTemplates.slash only has the fine shapes and the maul's *_coarse shapes gave wound_settings = nil and the
-- 0.1.1 crash (wound_materials.lua:185). Shield hits keep the shield maul profiles with plain blunt wounds.
local MOVESET = {
    action_light_1 = { profile = "light_combatsword_linesman", damage_type = "metal_slashing_light", wounds = "left_45_slash", speed = "time_scale_1_2" },
    action_heavy_1 = { profile = "heavy_combatsword", damage_type = "metal_slashing_medium", wounds = "left_45_slash" },
    action_light_2 = { profile = "light_combatsword_linesman", damage_type = "metal_slashing_light", wounds = "right_45_slash", speed = "time_scale_1_3" },
    action_heavy_2 = { profile = "heavy_combatsword_smiter", damage_type = "metal_slashing_medium", wounds = "right_45_slash" },
    action_light_3 = { profile = "light_combatsword_smiter", damage_type = "metal_slashing_light", wounds = "vertical_slash", speed = "time_scale_1_2" },
    action_light_4 = { profile = "powermaul_shield_light_smiter_shield", damage_type = "blunt", blunt = true },
    action_heavy_3 = { profile = "powermaul_shield_heavy_tank_shield", damage_type = "blunt_heavy", blunt = true },
    action_pushfollow = { profile = "light_combatsword_linesman", damage_type = "metal_slashing_light", wounds = "vertical_slash" },
}

-- powermaul_shield_p1_m1.lua:1383-1391: the power field sources sit on the maul head; the combat sword has only
-- _block/_sweep (combatsword_p1_m1.lua:1197-1200). The sources stay defined (slot scripts look them up) but point at
-- the blade's fx_block; the scripts that drew the power field on them are removed from the items (STRIP_SCRIPTS).
local FX_SOURCES = { _special_active = "fx_block", _wielded_idling = "fx_block" }

local blunt_profiles = {}

-- Same profile with WoundsTemplates.blunt instead of shock_blunt (power_maul_shield_damage_profile_templates.lua:632).
-- The name stays the game's, so the network still sends a known profile name.
local function blunt_profile(profile)
    local WoundsTemplates = require("scripts/settings/damage/wounds_templates")

    -- only shock wounds are swapped: 0.2.0 swapped every profile here, so the sword's slash profiles got blunt wounds,
    -- which list only *_coarse shapes, and the sword shapes crashed again (wound_materials.lua:185, user test 2026-10-25)
    if profile.wounds_template ~= WoundsTemplates.shock_blunt then
        return profile
    end

    local clone = blunt_profiles[profile]

    if not clone then
        clone = table.clone(profile)
        clone.wounds_template = WoundsTemplates.blunt
        blunt_profiles[profile] = clone
    end

    return clone
end

-- Copies a donor action into the clone. weapon_tweak_templates.lua _preparse_templates (:213-287) renamed each
-- <type>_template of an action to "<action>_<base>" and stored { new_identifier, base_identifier } under the action
-- name, and damage/explosion get {} per action (:289-309); a missing entry is the weapon_tweak_templates.lua:579 crash.
-- So the donor's entries are copied under our action name and the action's fields renamed to match.
local function graft(clone, action_name, donor, donor_action_name, notes)
    local WeaponTweakTemplateSettings = require("scripts/settings/equipment/weapon_templates/weapon_tweak_template_settings")
    local donor_action = donor.actions and donor.actions[donor_action_name]
    local donor_lookup = rawget(donor, "__base_template_lookup")
    local lookup = rawget(clone, "__base_template_lookup")

    if not (donor_action and donor_lookup and lookup) then
        notes[#notes + 1] = string.format("graft %s <- %s.%s missing", action_name, tostring(donor.name), donor_action_name)

        return false
    end

    local action = table.clone(donor_action)

    action.name = action_name

    for _, template_type in pairs(WeaponTweakTemplateSettings.template_types) do
        local from, to = donor_lookup[template_type], lookup[template_type]

        if from and to then
            for suffix, field in pairs({ [""] = template_type .. "_template", ["_special"] = "special_" .. template_type .. "_template" }) do
                local entry = from[donor_action_name .. suffix]

                if entry and entry.base_identifier then
                    local new_identifier = string.format("%s%s_%s", action_name, suffix, entry.base_identifier)

                    to[action_name .. suffix] = { new_identifier = new_identifier, base_identifier = entry.base_identifier }
                    action[field] = new_identifier
                elseif entry then
                    to[action_name .. suffix] = {}
                else
                    to[action_name .. suffix] = nil
                end
            end
        end
    end

    clone.actions[action_name] = action

    return true
end

local function apply_moveset(clone, notes)
    local DamageProfileTemplates = require("scripts/settings/damage/damage_profile_templates")
    local DamageSettings = require("scripts/settings/damage/damage_settings")
    local WoundsSettings = require("scripts/settings/wounds/wounds_settings")
    local WeaponHandlingTemplates = require("scripts/settings/equipment/weapon_handling_templates/weapon_handling_templates")
    local WeaponTweakTemplateSettings = require("scripts/settings/equipment/weapon_templates/weapon_tweak_template_settings")
    local damage_types = DamageSettings.damage_types
    local wounds_shapes = WoundsSettings.shapes

    for action_name, def in pairs(GRAFTS) do
        local donor = WeaponTemplates[def[1]]
        local old = clone.actions[action_name]
        local grafted = donor ~= nil and graft(clone, action_name, donor, def[2], notes)

        if grafted and def.keep and old then
            -- chains, inputs and 3P events stay this template's (the 3P state machine is still assault_shield_maul)
            local action = clone.actions[action_name]

            for _, field in ipairs({ "allowed_chain_actions", "start_input", "anim_event_3p", "chain_anim_event_3p" }) do
                action[field] = old[field]
            end

            if old.anim_event_3p == nil then
                action.anim_event_3p = old.anim_event
            end
        end

        if grafted and def.chain then
            local chains = clone.actions[action_name].allowed_chain_actions

            for input, target in pairs(def.chain) do
                if chains and chains[input] then
                    chains[input].action_name = target
                end
            end
        end
    end

    -- stat bars and trait lerps per action (powermaul_shield_p1_m1.lua base_stats): heavy 3 reads like heavy 1
    for _, stat in pairs(clone.base_stats or {}) do
        local damage = type(stat) == "table" and stat.damage

        if damage and damage.action_heavy_1 and not damage.action_heavy_3 then
            damage.action_heavy_3 = table.clone(damage.action_heavy_1)
            damage.action_heavy_3.display_data = nil
        end
    end

    local handling = rawget(clone, "__base_template_lookup")
    handling = handling and handling[WeaponTweakTemplateSettings.template_types.weapon_handling]

    for action_name, def in pairs(MOVESET) do
        local action = clone.actions[action_name]
        local profile = rawget(DamageProfileTemplates, def.profile)

        if action and profile then
            action.damage_profile = def.blunt and blunt_profile(profile) or profile
            action.damage_type = rawget(damage_types, def.damage_type) or action.damage_type

            if def.wounds and wounds_shapes[def.wounds] then
                action.wounds_shape = wounds_shapes[def.wounds]
            elseif def.blunt then
                action.wounds_shape = nil
            end

            -- _build_templates resolves base_identifier, so the speed is changed in the lookup
            local entry = def.speed and handling and handling[action_name]

            if entry and entry.base_identifier and rawget(WeaponHandlingTemplates, def.speed) then
                entry.base_identifier = def.speed
            end
        else
            notes[#notes + 1] = string.format("moveset: %s/%s missing", action_name, def.profile)
        end
    end

    -- no power field: any shock damage left (special, push) becomes plain blunt with blunt wounds
    for _, action in pairs(clone.actions) do
        if action.damage_type == damage_types.blunt_shock then
            action.damage_type = damage_types.blunt
        end

        if type(action.damage_profile) == "table" then
            action.damage_profile = blunt_profile(action.damage_profile)
        end
    end

    clone.fx_sources = table.clone(clone.fx_sources or {})

    for source, node in pairs(FX_SOURCES) do
        clone.fx_sources[source] = node
    end

    -- powermaul_shield_p1_m1.lua:1613-1626: the shock-on-hit buff and the "Shock Weapon" keyword
    clone.buffs = {}

    local keywords = {}

    for _, keyword in ipairs(clone.displayed_keywords or {}) do
        if keyword.display_name ~= "loc_weapon_keyword_shock_weapon" then
            keywords[#keywords + 1] = keyword
        end
    end

    clone.displayed_keywords = keywords
end

-- 0.6.0 (user 2026-10-25: "2x cleave"): every damage profile of the template gets its cleave_distribution (attack and
-- impact {min, max} hit mass budget, damage_profile_settings.lua:308-405) multiplied. Profiles are cloned under the
-- game's own name (as blunt_profile above), so the network still sends a known name; the host's copy decides the hits.
local tuned_profiles = {}

local function scaled(value, factor)
    if type(value) == "number" then
        return value * factor
    elseif type(value) == "table" then
        local out = {}

        for k, v in pairs(value) do
            out[k] = scaled(v, factor)
        end

        return out
    end

    return value
end

-- 0.6.6 (user: "reduce dps of weapon by 25% but increase the inborn rending enough for the heavy atk to count as not
-- [in]effective against carapace"): damage = every power_distribution.attack {min, max} of the profile and its targets
-- times damage_multiplier (default 0.75). Carapace: the hit is graded by the armour modifier BEFORE rending
-- (attack_settings.lua:27-35: "negated" at <= 0.1 with no rending, "full" above 0.6, else "reduced"; damage_calculation.lua
-- :112), and a profile has no rending of its own (rending only comes from stat buffs, damage_calculation.lua:629-661). For
-- melee_attack_strength heavy profiles the super_armor attack lerp of the profile and of every target is lifted to at
-- least carapace_heavy (default {0.62, 0.75}), so a heavy is graded "full" on Carapace at any penetration roll.
-- Before: heavy_combatsword target 1 lerp_0_25 {0.143, 0.358}, the rest cutting_am lerp_0_075 {0.04, 0.11} (negated);
-- heavy_combatsword_smiter target 1 lerp_0_4 {0.24, 0.56} (combat_sword_damage_profile_templates.lua:1244-1492,
-- damage_profile_settings.lua:84-115).
local function lift_carapace(modifier, floor)
    local attack = type(modifier) == "table" and modifier.attack
    local lerp = attack and attack.super_armor

    if type(lerp) == "table" and type(lerp[1]) == "number" then
        local out = table.clone(modifier)

        out.attack = table.clone(attack)
        out.attack.super_armor = { math.max(lerp[1], floor[1]), math.max(lerp[2] or lerp[1], floor[2]) }

        return out
    end

    return modifier
end

local function tuned_profile(profile, opts)
    if type(profile) ~= "table" then
        return profile
    end

    local key = opts.key
    tuned_profiles[key] = tuned_profiles[key] or {}

    local clone = tuned_profiles[key][profile]

    if clone then
        return clone
    end

    clone = table.clone(profile)

    if clone.cleave_distribution ~= nil and opts.cleave ~= 1 then
        clone.cleave_distribution = scaled(profile.cleave_distribution, opts.cleave)
    end

    -- 0.6.7 (user: "apply armor pen to lights, and reduce armor pen on heavies slightly"): lights get their own floor
    local floor = opts.carapace and opts.carapace[profile.melee_attack_strength]
    local heavy = floor ~= nil

    if heavy then
        clone.armor_damage_modifier = lift_carapace(clone.armor_damage_modifier, floor)
    end

    local function tune_target(target)
        if type(target) ~= "table" then
            return
        end

        if type(target.power_distribution) == "table" and target.power_distribution.attack and opts.damage ~= 1 then
            target.power_distribution.attack = scaled(target.power_distribution.attack, opts.damage)
        end

        if heavy and target.armor_damage_modifier then
            target.armor_damage_modifier = lift_carapace(target.armor_damage_modifier, floor)
        end
    end

    tune_target(clone)

    if type(clone.targets) == "table" then
        for _, target in pairs(clone.targets) do
            tune_target(target)
        end
    end

    tuned_profiles[key][profile] = clone

    return clone
end

-- every damage profile of the template is cloned under the game's own name (as blunt_profile above), so the network
-- still sends a known name; the host's copy decides the hits (your game, solo, the Psykhanium)
local function tune_profiles(clone, notes)
    local cleave = mod:get("cleave_multiplier") or 2
    -- 0.6.8: a new setting id, because DMF had saved the 0.6.6 default 0.75 under damage_multiplier
    local damage = (mod:get("damage_percent") or 100) / 100
    -- 0.6.8 (user: "revert 25%, and boost melee light adm slightly more"): damage x1 again, lights {0.63, 0.68} (0.6.7
    -- {0.61, 0.64}); both minimums stay above 0.6, so both still grade "full" (attack_settings.lua:30); 0.6.6 heavies were {0.62, 0.75}
    local floor = {
        heavy = mod:get("carapace_heavy") ~= false and { 0.61, 0.69 } or nil,
        light = mod:get("carapace_light") ~= false and { 0.63, 0.68 } or nil,
    }

    if not floor.heavy and not floor.light then
        floor = nil
    end

    local opts = { cleave = cleave, damage = damage, carapace = floor,
        key = string.format("%s/%s/%s/%s", tostring(cleave), tostring(damage), tostring(floor and floor.heavy ~= nil),
            tostring(floor and floor.light ~= nil)) }

    if cleave == 1 and damage == 1 and not floor then
        return
    end

    local count = 0

    for _, action in pairs(clone.actions) do
        for field, value in pairs(action) do
            if type(field) == "string" and field:find("^damage_profile") and type(value) == "table" then
                action[field] = tuned_profile(value, opts)
                count = count + 1
            end
        end
    end

    notes[#notes + 1] = string.format("%d damage profiles: cleave x%s, damage x%s, carapace: heavy %s, light %s", count,
        tostring(cleave), tostring(damage), floor and floor.heavy and "full" or "as the game",
        floor and floor.light and "full" or "as the game")
end

-- State -------------------------------------------------------------------------------------------------------------
local state ={ template_ok = false, item_ok = false, notes = {} }
local next_poll = 0
local assets_ready = false

-- Fatshark's unreleased sword-and-shield first-person animations (0.3.0) ---------------------------------------------
-- content/characters/player/human/first_person/animations/combat_sword_shield ships as a package + state machine
-- (unreleased-asset sweep 2026-10-25, index.tsv f732d4dc7e89349b) with no Lua using it. Its events, id32-matched against
-- every quoted string of the game source (technique-state-machine-event-scan; A:\Dowloads\staging\swordshield\sm\scan.py),
-- are exactly the assault_shield_maul 1P events plus an alternative inspect; which events carry its own clips is in the
-- GRAFTS note (0.4.0). No 3P set exists; 3P stays assault_shield_maul. player_unit_animation_state.lua:112 indexes
-- PlayerUnitAnimationStateMachineSettings by path, so the new path gets a copy of the maul's entry (QIangIQsChainLaspistol
-- 0.3.0, rawset because the table comes from settings()).
local SWORD_SHIELD_SM_1P = "content/characters/player/human/first_person/animations/combat_sword_shield"
-- 0.6.0 pose rigs: Arbites shield (powermaul_shield_p1_m1.lua:1335) and duelling sword (combatsword_p3_m1.lua:1365)
local POSE_SM_SHIELD = "content/characters/player/human/first_person/animations/assault_shield_maul"
local POSE_SM_SABRE = "content/characters/player/human/first_person/animations/sabre"

-- 0.6.4 (user: "3rd person pov doesnt line up with first person, shield clipping into thighs, facing the floor ... block
-- anim and heavy atk anim still arent synced in 3rd person"): the sword set cloned the combat sword's 3P state machine
-- (combatsword_p1_m1.lua:1181 power_sword), whose free left hand carries the shield at the thigh. Third person now plays
-- the Arbites shield maul set (powermaul_shield_p1_m1.lua:1334), like the first-person left arm, and every 3P event of the
-- combat sword is moved onto a shield maul event of the same kind. Events kept as they are exist in that set already:
-- attack_swing_left_diagonal / attack_swing_right / attack_swing_right_diagonal (shield maul m1/m2 swings), parry_pose
-- (its block, powermaul_shield_p1_m1.lua:979), attack_push, equip. Targets from powermaul_shield_p1_m1/m2.lua anim_event_3p.
local SHIELD_SM_3P = "content/characters/player/human/third_person/animations/assault_shield_maul"
local EVENTS_3P = {
    attack_swing_charge_left = "attack_swing_charge_down_left",      -- m2 :217
    attack_swing_charge_right = "attack_swing_charge_down_right",    -- m1 :470
    attack_swing_heavy_left = "attack_swing_left_diagonal",          -- m2 heavy 1 :399
    attack_swing_heavy_right = "attack_swing_heavy_down_right",      -- m1 heavy 2 :617
    attack_swing_heavy_down = "attack_swing_heavy_down_right",
    attack_swing_down_left = "attack_swing_left",                    -- m1 light 1 :297
    -- the riposte (combatsword_p1_m1.lua:997 anim_event attack_special, no 3P event) would play the maul's shield special
    attack_special = "attack_stab_01",                               -- m1 light 4 :904
}

local function use_shield_3p(clone, notes)
    if mod:get("third_person_set") == "sword" then
        return
    end

    local source = WeaponTemplates[SOURCE_TEMPLATE]
    local sm = source and source.anim_state_machine_3p or SHIELD_SM_3P

    clone.anim_state_machine_3p = sm
    clone.breed_anim_state_machine_3p = nil

    local moved = 0

    for _, action in pairs(clone.actions) do
        local event_3p = action.anim_event_3p or action.anim_event
        local mapped = event_3p and EVENTS_3P[event_3p]

        if mapped then
            action.anim_event_3p = mapped
            moved = moved + 1
        end

        if action.chain_anim_event_3p and EVENTS_3P[action.chain_anim_event_3p] then
            action.chain_anim_event_3p = EVENTS_3P[action.chain_anim_event_3p]
        end
    end

    state.shield_3p = true
    notes[#notes + 1] = string.format("3P %s, %d events moved", sm, moved)
end

-- 0.6.9 (user: "give arbitrator shield levels of block cost reduction and gunner and flamer and sniper resist when
-- blocking due to its shield characteristics"): the sword set's blocks take the Arbites shield's defence.
--   * stamina_template "powermaul_shield_p1_m1" (powermaul_shield_p1_m1.lua:1403; weapon_stamina_templates.lua:310):
--     block inner 0.6..0.2 / outer 2..1 (Combat Sword linesman_plus :60 has 1..0.5 / 3..1), ranged block inner 0.3..0.1,
--     push 1.5..0.5. A new stamina template name cannot be added: the weapon_tweak_templates component's names are fixed
--     when player_unit_data_component_config.lua:254-258 loads, so the shield's own template is used, sprint cost included.
--   * block_attack_types melee + ranged on the block and the parry special (block.lua:77-84 lets a ranged hit be blocked
--     only then), as powermaul_shield_p1_m1.lua:1032. Gunner, sniper and flamer-beam hits are ranged attacks
--     (bt_shoot_liquid_beam_action.lua:668-673 HitScan); the flamer's burn buff and the burning ground are not blocked,
--     the same as with the Arbites shield.
--   * block_unblockable on the block, as powermaul_shield_p1_m1.lua:980 (the parry special already has parry_block).
local function use_shield_defence(clone, notes)
    if mod:get("shield_defence") == false then
        return
    end

    local source = WeaponTemplates[SOURCE_TEMPLATE]

    -- 0.6.10 (crash 2026-10-27, weapon_stats.lua:422 stamina_template nil on realms_loadout's item hover): templates are
    -- preparsed at load (weapon_tweak_templates.lua:35-58, :213-225): stamina_template becomes "base_<name>" and
    -- __base_template_lookup.stamina.base maps it to the stamina template. The clone kept the Combat Sword's lookup, so
    -- the name set here resolved to nothing. Both the preparsed name and the lookup entry now come from the shield maul.
    local stamina_lookup = source and source.__base_template_lookup and source.__base_template_lookup.stamina

    if not (source and source.stamina_template and stamina_lookup and clone.__base_template_lookup) then
        notes[#notes + 1] = "shield defence: shield maul stamina template not found, Combat Sword stamina kept"
    else
        clone.stamina_template = source.stamina_template
        clone.__base_template_lookup.stamina = table.clone(stamina_lookup)
    end

    if source and source.block_angles then
        clone.block_angles = table.clone(source.block_angles)
    end

    for _, name in ipairs({ "action_block", "action_parry_special" }) do
        local action = clone.actions[name]

        if action then
            action.block_attack_types = { melee = true, ranged = true }
        end
    end

    if clone.actions.action_block then
        clone.actions.action_block.block_unblockable = true
    end

    notes[#notes + 1] = "shield defence: stamina " .. tostring(clone.stamina_template) .. ", ranged block"
end

local function use_retail_animations(clone)
    state.retail_anims = false

    if mod:get("retail_animations") == false then
        return
    end

    local ok, found = pcall(Application.can_get_resource, "package", SWORD_SHIELD_SM_1P)

    if not (ok and found) then
        mod:info("%s not found: the Shield Maul's first-person animations stay", SWORD_SHIELD_SM_1P)

        return
    end

    local SMSettings = require("scripts/settings/animation/player_unit_animation_state_machine_settings")

    if not rawget(SMSettings, SWORD_SHIELD_SM_1P) then
        rawset(SMSettings, SWORD_SHIELD_SM_1P, table.clone(rawget(SMSettings, clone.anim_state_machine_1p) or { blend_time = 0 }))
    end

    clone.anim_state_machine_1p = SWORD_SHIELD_SM_1P
    state.retail_anims = true
end

local function ensure_template()
    if rawget(WeaponTemplates, TEMPLATE) then
        state.template_ok = true
        state.official_template = not state.template_ours

        return true
    end

    -- 0.5.0 (user decision 2026-10-25: "Combat Sword swings + held shield"): by default the template is a clone of the
    -- Combat Sword itself (its actions, damage, block/parry special, combat_sword state machines); the shield is held up
    -- in first person by the arm driver (QIangIQsSwordShield_arm.lua hold). animation_set "shield_maul" keeps 0.4.x.
    state.sword_set = mod:get("animation_set") ~= "shield_maul"

    local source = WeaponTemplates[state.sword_set and SWORD_TEMPLATE or SOURCE_TEMPLATE]

    if not source then
        return false
    end

    local clone = table.clone(source)

    clone.name = TEMPLATE

    -- weapon_templates.lua _require_template: action_settings.name = action_name
    for action_name, action_settings in pairs(clone.actions) do
        action_settings.name = action_name
    end

    if not state.sword_set then
        apply_moveset(clone, state.notes)
        use_retail_animations(clone)
    end

    if state.sword_set then
        use_shield_3p(clone, state.notes)
        use_shield_defence(clone, state.notes)
    end

    tune_profiles(clone, state.notes)

    WeaponTemplates[TEMPLATE] = clone
    state.template_ours = true

    local ok, index = append_lookup("weapon_templates", TEMPLATE)

    state.template_id = ok and index or nil
    -- sword first (hits, swings), the shield maul fills what the sword lacks (block, shield special)
    state.aliases = copy_aliases(SWORD_TEMPLATE, TEMPLATE)

    if not state.sword_set then
        state.aliases = state.aliases + copy_aliases(SOURCE_TEMPLATE, TEMPLATE, true)
    end
    state.template_ok = ok

    return ok
end

-- Items -------------------------------------------------------------------------------------------------------------
local function find_item(cache, preferred, template)
    local direct = rawget(cache, preferred)

    if direct and direct.weapon_template == template then
        return preferred, direct
    end

    for name, item in pairs(cache) do
        if type(item) == "table" and item.weapon_template == template then
            return name, item
        end
    end
end

-- Only base_unit is kept: Items.base_unit can also read per-breed / first-person variants of the source part
local function only_base_unit(item, unit)
    for key in pairs(item) do
        if type(key) == "string" and key ~= "base_unit" and key:find("^base_unit") then
            item[key] = nil
        end
    end

    item.base_unit = unit
end

local function make_part(cache, name, template_item, unit, attach_node)
    local item = table.clone(template_item)

    only_base_unit(item, unit)
    item.name = name
    item.resource_dependencies = { [unit] = true }
    item.attachments = nil
    item.material_overrides = nil
    item.material_override_items = nil
    item.attach_node = attach_node
    cache[name] = item

    return name
end

-- Source tree as "slot_path=item" for the log, to check the placement against the game's data
local function dump_tree(tree, prefix, out)
    for slot_name, node in pairs(tree) do
        if type(node) == "table" then
            local path = prefix .. slot_name

            out[#out + 1] = string.format("%s=%s%s", path, tostring(node.item),
                node.link_map_mode_override and (" map:" .. tostring(node.link_map_mode_override)) or "")

            if type(node.children) == "table" then
                dump_tree(node.children, path .. "/", out)
            end
        end
    end

    return out
end

-- Every item in the tree becomes "" (spawns nothing) except the nodes listed in keep
local function clear_tree(tree, keep)
    for _, node in pairs(tree) do
        if type(node) == "table" then
            if not keep[node] and type(node.item) == "string" then
                node.item = ""
            end

            if type(node.children) == "table" then
                clear_tree(node.children, keep)
            end
        end
    end
end

-- Slot scripts are read from the root item and every attachment item (wieldable_slot_scripts.lua:99-150, CLASSES by
-- name). These draw the power field / shock: shock_maul_hit_effects.lua, power_weapon_effects.lua,
-- power_weapon_charges_effects.lua, riot_shield_effects.lua (electrified shield loop on _shield_special_active).
local STRIP_SCRIPTS = {
    ShockMaulHitEffects = true,
    PowerWeaponEffects = true,
    PowerWeaponChargesEffects = true,
    PowerWeaponOverheatEffects = true,
    RiotShieldEffects = true,
    -- 0.4.3: plays the equipped_item_passive_loop alias (wielded_idling_effects.lua:5-6, 41-43), the powermaul idle hum
    WieldedIdlingEffects = true,
}

local function strip_scripts(item, removed)
    if type(item.wieldable_slot_scripts) ~= "table" then
        return
    end

    local kept = {}

    for _, script_name in ipairs(item.wieldable_slot_scripts) do
        if STRIP_SCRIPTS[script_name] then
            removed[#removed + 1] = script_name
        else
            kept[#kept + 1] = script_name
        end
    end

    item.wieldable_slot_scripts = kept
end

local function build_item(cache)
    local source_name, source_item = find_item(cache, SOURCE_ITEM, SOURCE_TEMPLATE)
    local sword_name, sword_item = find_item(cache, SWORD_ITEM, SWORD_TEMPLATE)

    if not source_item or not sword_item then
        return false
    end

    if type(source_item.attachments) ~= "table" or type(sword_item.attachments) ~= "table" then
        return false, "source items have no attachments"
    end

    local item = table.clone(source_item)
    local notes = state.notes

    item.name = ITEM
    item.weapon_template = TEMPLATE
    item.display_name = DISPLAY

    for _, field in ipairs({ "weapon_family_display_name", "weapon_pattern_display_name", "weapon_mark_display_name" }) do
        if type(item[field]) == "table" then
            item[field].loc_id = DISPLAY
        end
    end

    local archetypes = {}

    for _, archetype in ipairs(source_item.archetypes or {}) do
        archetypes[#archetypes + 1] = archetype
    end

    if not table.find(archetypes, "zealot") then
        archetypes[#archetypes + 1] = "zealot"
    end

    item.archetypes = archetypes

    if not state.trees_logged then
        state.trees_logged = true
        mod:info("source tree of %s: %s", tostring(source_name), table.concat(dump_tree(item.attachments, "", {}), "; "))
        mod:info("sword tree of %s: %s", tostring(sword_name), table.concat(dump_tree(sword_item.attachments, "", {}), "; "))
    end

    -- Live trees (console log 2026-10-25 03:35):
    --   powermaul_shield_p1_m1: left = assault_shield_p1_m1 (the shield is a whole item on its own rig), right =
    --     powermaul_p1_empty, right/shaft (/connector/head, trinkets), right/trail = power_maul_trail_01
    --   combatsword_p1_m1: grip = combat_sword_grip_01, grip/body = combat_sword_blade_01, grip/trinket_hook, trail
    local left = item.attachments.left
    local right = item.attachments.right
    local shaft = right and type(right.children) == "table" and right.children.shaft
    local shaft_item = shaft and type(shaft.item) == "string" and rawget(cache, shaft.item)
    local grip = sword_item.attachments.grip
    local blade = grip and type(grip.children) == "table" and grip.children.body
    local grip_source = grip and rawget(cache, grip.item)
    local blade_source = blade and rawget(cache, blade.item)
    local sword_trail = sword_item.attachments.trail

    if not (left and type(left.item) == "string" and rawget(cache, left.item) and shaft_item) then
        return false, "no left (shield) or right/shaft slot in " .. tostring(source_name)
    end

    if not (grip_source and blade_source) then
        return false, "no grip or grip/body slot in " .. tostring(sword_name)
    end

    -- the shield item is copied whole under our name, so its spawned unit can be found by item name
    local shield_item = table.clone(rawget(cache, left.item))

    shield_item.name = SHIELD_ITEM
    cache[SHIELD_ITEM] = shield_item
    left.item = SHIELD_ITEM

    local removed = {}

    -- 0.5.0 sword set: the root's slot scripts are the Combat Sword's (the shield maul's RiotShieldChargeDisplay reads
    -- shield special charges the sword template does not have)
    if state.sword_set and type(sword_item.wieldable_slot_scripts) == "table" then
        item.wieldable_slot_scripts = table.clone(sword_item.wieldable_slot_scripts)
    end

    strip_scripts(item, removed)
    strip_scripts(shield_item, removed)

    if not state.scripts_logged then
        state.scripts_logged = true
        mod:info("slot scripts: root %s, shield %s, removed %s", table.concat(item.wieldable_slot_scripts or {}, ","),
            table.concat(shield_item.wieldable_slot_scripts or {}, ","), table.concat(removed, ","))
    end

    -- the sword takes the shaft's place under the right-hand rig and stays static relative to that node
    make_part(cache, GRIP_ITEM, grip_source, GRIP_UNIT, shaft_item.attach_node)
    make_part(cache, BLADE_ITEM, blade_source, BLADE_UNIT, BLADE_NODE)
    clear_tree(shaft.children or {}, {})
    shaft.item = GRIP_ITEM
    shaft.link_map_mode_override = "LINK_MODE_NONE"
    shaft.children = shaft.children or {}
    -- 0.3.0: the blade is held rigidly on the grip's ap_blade_01 too (user: blade not attached to the hilt; with the
    -- default LINK_MODE_NODE_NAME its nodes could follow same-named nodes instead, the DauntlessArmory 0.2.0 gotcha)
    shaft.children.qiangiq_blade = { item = BLADE_ITEM, children = {}, link_map_mode_override = "LINK_MODE_NONE" }

    -- sword trail instead of the power maul's
    if right.children.trail and sword_trail and type(sword_trail.item) == "string" and rawget(cache, sword_trail.item) then
        right.children.trail.item = sword_trail.item
    end

    notes[#notes + 1] = string.format("sword on right/shaft (attach node %s), shield %s", tostring(shaft_item.attach_node),
        tostring(shield_item.base_unit))


    -- HUD icon (hud_element_player_weapon.lua:77 reads item.hud_icon): the game's own unreleased sword-and-shield icon
    -- (material+package content/ui/materials/icons/weapons/hud/combatsword_shield_p1_m1, unreleased-asset sweep
    -- 2026-10-25, build 139617), else the combat sword's. The drawn icon can go over it (setting, needs Custom Assets).
    local deps0 = item.resource_dependencies or {}

    for _, icon in ipairs({ RETAIL_HUD_ICON, sword_item.hud_icon }) do
        local ok_pkg, pkg_found = pcall(Application.can_get_resource, "package", tostring(icon))
        local ok_mat, mat_found = pcall(Application.can_get_resource, "material", tostring(icon))
        local ok_icon = ok_pkg and ok_mat
        local icon_found = (pkg_found and mat_found) and true or false

        if type(icon) == "string" and ok_icon and icon_found then
            if type(item.hud_icon) == "string" then
                deps0[item.hud_icon] = nil
            end

            item.hud_icon = icon
            deps0[icon] = true
            notes[#notes + 1] = "hud icon " .. icon

            break
        end
    end

    item.resource_dependencies = deps0

    -- What the offline item compile adds for the weapon template (item_package.lua:239-249): state machines, sounds,
    -- effects (DauntlessArmory 0.3.0)
    local deps = item.resource_dependencies or {}
    local WeaponTemplateResourceDependencies = require("scripts/utilities/weapon_template_resource_dependencies")

    for _, resource in ipairs(WeaponTemplateResourceDependencies.generate(TEMPLATE)) do
        deps[resource] = true
    end

    -- 0.6.0: the hidden pose rigs of QIangIQsSwordShield_arm.lua play the Arbites shield and the duelling sword state
    -- machines, so both load with the weapon (the item compile lists state machines the same way, item_package.lua)
    deps[POSE_SM_SHIELD] = true
    deps[POSE_SM_SABRE] = true
    deps[SHIELD_SM_3P] = true

    item.resource_dependencies = deps

    local ok, index = append_lookup("player_item_names", ITEM)

    if not ok then
        return false
    end

    cache[ITEM] = item
    state.item_id = index
    state.source_item_name = source_name
    state.slot = item.slots and item.slots[1]
    state.archetypes = archetypes

    return true
end

local function ensure_item()
    local ok, has_data = pcall(MasterItems.has_data)

    if not ok or not has_data then
        return false
    end

    local cache = MasterItems.get_cached()

    if rawget(cache, ITEM) then
        state.item_ok = true

        return true
    end

    local built, err = build_item(cache)

    if err and err ~= state.last_error then
        state.last_error = err
        mod:error("%s", err)
    end

    state.item_ok = built and rawget(cache, ITEM) ~= nil

    return state.item_ok
end

-- Unlock lists (weapon_unlock_settings.lua WeaponUnlockSettings[archetype][level] = { item names }); realms_loadout
-- weapon_catalog.lua builds its human weapon list from it
local function add_to_unlock_list()
    if not mod:get("add_to_unlock_list") then
        return
    end

    local ok, unlocks = pcall(require, "scripts/settings/weapon_unlock/weapon_unlock_settings")
    local zealot = ok and unlocks and unlocks.zealot

    if not zealot then
        mod:error("WeaponUnlockSettings.zealot not found")

        return
    end

    local level = math.floor(mod:get("unlock_level") or 1)

    zealot[level] = zealot[level] or {}

    if not table.find(zealot[level], ITEM) then
        table.insert(zealot[level], ITEM)
    end
end

local function poll()
    if next_poll > os.clock() then
        return
    end

    next_poll = os.clock() + 1

    local before_t, before_i = state.template_ok, state.item_ok
    local ok_t, err_t = pcall(ensure_template)
    local ok_i, err_i = true, nil

    if state.template_ok then
        ok_i, err_i = pcall(ensure_item)
    end

    if not ok_t then
        mod:error("template: %s", tostring(err_t))
    end

    if not ok_i then
        mod:error("item: %s", tostring(err_i))
    end

    if state.template_ok and not before_t then
        if state.official_template then
            mod:info("the game now has its own %s template; using it", TEMPLATE)
        else
            mod:info("template %s registered (clone of %s), %s alias entries, 1P animations %s", TEMPLATE,
                state.sword_set and SWORD_TEMPLATE or SOURCE_TEMPLATE, tostring(state.aliases),
                state.sword_set and "combat_sword" or state.retail_anims and SWORD_SHIELD_SM_1P or "assault_shield_maul")
        end
    end

    if state.item_ok and not before_i then
        mod:info("item %s injected (clone of %s, slot %s): %s", ITEM, tostring(state.source_item_name), tostring(state.slot),
            table.concat(state.notes, "; "))
    end
end

-- Visuals: heater over the retail shield, sword grip offset ------------------------------------------------------------
-- Spawning, linking, 1p flags and cleanup follow QIangIQsDauntlessArmory's clip display (QIangIQsShardStaff pattern):
-- PlayerUnitVisualLoadoutExtension init/_update_item_visibility/update/_unequip_item_from_slot/destroy hooks,
-- ext._equipment[slot] item_name_by_unit_1p/3p (equipment_component.lua:299/345).
local tracked = {}

local function unit_ok(unit)
    return unit ~= nil and Unit.alive(unit)
end

local function delete_unit(unit)
    local unit_spawner = Managers.state and Managers.state.unit_spawner

    if unit_ok(unit) and unit_spawner then
        unit_spawner:mark_for_deletion(unit)
    end
end

local function unit_named(names, want)
    if names then
        for unit, item_name in pairs(names) do
            if item_name == want and unit_ok(unit) then
                return unit
            end
        end
    end
end

local function spawn_linked(ext, unit_name, parent, first_person)
    local world = ext.__qiangiq_swordshield_world
    local unit_spawner = Managers.state and Managers.state.unit_spawner
    local unit = world and unit_spawner and unit_spawner:spawn_unit(unit_name, Unit.world_pose(parent, 1))

    if not unit then
        return nil
    end

    if first_person then
        Unit.set_unit_culling(unit, false)
        Unit.set_shader_pass_flag_for_meshes_in_unit_and_childs(unit, "custom_fov", true)
    end

    World.link_unit(world, unit, 1, parent, 1, World.LINK_MODE_NONE)

    return unit
end

local function drop_record(records, key)
    local rec = records[key]

    if rec then
        delete_unit(rec.unit)
        records[key] = nil
    end
end

local function sync_shield(ext, records, key, names, visible, first_person)
    local rec = records[key]
    local retail = unit_named(names, SHIELD_ITEM)
    local want = retail and assets_ready and mod:get("shield_model") ~= "retail"

    if rec and (rec.parent ~= retail or not want or not unit_ok(rec.unit)) then
        drop_record(records, key)
        rec = nil
    end

    if not want then
        return
    end

    if not rec then
        rec = { parent = retail, unit = spawn_linked(ext, SHIELD_UNIT, retail, first_person) }
        records[key] = rec

        if not rec.unit then
            return
        end
    end

    -- recursive visibility also reaches the linked heater, so the heater is set after the retail shield
    Unit.set_unit_visibility(retail, false, true)
    Unit.set_unit_visibility(rec.unit, visible, true)

    -- +x is the shield's outer face (probe4.py); the compiled mesh is already 6 cm further out than 0.1.x
    -- 0.6.0 model check (user: "top of shield occupies similar area on screen as arbites shield"; probe8.py bounds in the
    -- shield frame): retail assault shield y -0.196..0.428, z -0.599..0.405 (1.00 m tall, top 0.405); heater as built
    -- y -0.159..0.382, z -0.615..0.233 (0.85 m tall, top 0.233, 17 cm lower). Fit "arbites" scales the heater 1.15x and
    -- raises it 13.7 cm: y -0.183..0.439, z -0.570..0.405, so its outline covers what the Arbites shield covers on screen
    -- (its straps then sit 14 cm above the hand). Fit "handles" keeps the straps on the forearm instead.
    local depth = (mod:get("shield_depth") or 0) / 100
    local fit = mod:get("heater_fit") ~= "handles"
    local key = tostring(depth) .. (fit and "a" or "h")

    if rec.fit_key ~= key then
        rec.fit_key = key

        local scale = fit and 1.15 or 1

        Unit.set_local_scale(rec.unit, 1, Vector3(scale, scale, scale))
        -- 0.6.2 (user: "not holding shield by grip", 0.6.1 screenshot): the 13.7 cm raise moved the heater off the hand,
        -- so the heater stays on the grip and the arm is raised instead (HEATER_RAISE in arm_mode)
        Unit.set_local_position(rec.unit, 1, Vector3(depth, 0, 0))
    end
end

-- 0.6.3 (user: "blade shows up on ranged weapon equip"): the arm driver re-links the sword's right root (and the
-- shield) away from the item's own unit tree, so the game's recursive hide of an unwielded slot no longer reaches them.
-- Their first-person visibility now follows the slot here. The retail shield only when the heater does not replace it
-- (sync_shield hides it then).
local function sync_relinked(records, slot_name, names, visible)
    local right = unit_named(names, RIGHT_ITEM)
    local retail = unit_named(names, SHIELD_ITEM)
    local key = slot_name .. ":vis"
    local heater = records[slot_name .. ":1p"]
    local state_key = tostring(right) .. tostring(retail) .. tostring(visible) .. tostring(heater ~= nil)

    if records[key] == state_key then
        return
    end

    records[key] = state_key

    if right then
        Unit.set_unit_visibility(right, visible, true)
    end

    if retail and not heater then
        Unit.set_unit_visibility(retail, visible, true)
    end
end

local function place_grip(names)
    local grip = unit_named(names, GRIP_ITEM)

    if grip then
        local offset = (mod:get("grip_offset") or 0) / 100

        Unit.set_local_position(grip, 1, Vector3(0, 0, offset))
    end

    -- 0.5.1 (user: "blade not attached to hilt"): blade_08's mesh starts 2.5 cm above its root (z 0.025..0.783) while
    -- grip_08 ends at its ap_blade_01 (mesh max z 0.105, node z 0.101; A:\Dowloads\staging\swordshield\probe7.py), so the
    -- blade is lowered onto the grip (setting blade_offset, default -2.5 cm)
    local blade = unit_named(names, BLADE_ITEM)

    if blade then
        Unit.set_local_position(blade, 1, Vector3(0, 0, (mod:get("blade_offset") or -2.5) / 100))
    end
end

-- Shield arm lift (0.4.0, QIangIQsSwordShield_arm.lua): sliders in cm, camera space; all 0 = off
local ARM_DRIVER_ASSET, ARM_DRIVER_UNIT = "QIangIQsSwordShield:ss_fp_driver", "content/mods/qiangiq_swordshield/ss_fp_driver"
local driver_ready = false

local Arm = mod:io_dofile("QIangIQsSwordShield/scripts/mods/QIangIQsSwordShield/QIangIQsSwordShield_arm")

Arm.setup({
    fp_nodes = mod:io_dofile("QIangIQsSwordShield/scripts/mods/QIangIQsSwordShield/QIangIQsSwordShield_fp_nodes"),
    driver_path = function()
        return driver_ready and ARM_DRIVER_UNIT or nil
    end,
    -- 0.5.2: the real view (CameraManager camera_rotation/camera_position by viewport), world space; the arm file
    -- falls back to the fp rig's ap_camera_node when this returns nil
    camera_pose = function()
        local ok, rotation, position = pcall(function()
            local camera = Managers.state and Managers.state.camera
            local player = Managers.player and Managers.player:local_player_safe(1)
            local viewport = player and player.viewport_name

            if not camera or not viewport then
                return nil
            end

            return camera:camera_rotation(viewport), camera:camera_position(viewport)
        end)

        if ok and rotation and position then
            return rotation, position
        end
    end,
    shield_sm = POSE_SM_SHIELD,
    sabre_sm = POSE_SM_SABRE,
    error = function(text)
        mod:error("%s", text)
    end,
    info = function(text)
        mod:info("%s", text)
    end,
})

-- 0.6.0: renamed from arm_* (DMF keeps saved values over new defaults; arm_lift was 10) and applied in every mode, on
-- top of the Arbites pose too (user: "the bottom 3 sliders at bottom of options dont work at all")
-- 0.6.1: flow callbacks raised by the hidden pose rigs' clips are dropped (see QIangIQsSwordShield_arm.lua Arm.is_rig).
-- FlowCallbacks is the global table the flow nodes call into (flow_callbacks.lua:33).
local FLOW_EMPTY = {}

local function flow_guard(func, params, ...)
    if type(params) == "table" and (Arm.is_rig(params.first_person_unit) or Arm.is_rig(params.unit)) then
        return FLOW_EMPTY
    end

    return func(params, ...)
end

if type(FlowCallbacks) == "table" then
    local names = {}

    for name, value in pairs(FlowCallbacks) do
        if type(name) == "string" and type(value) == "function" then
            names[#names + 1] = name
        end
    end

    for _, name in ipairs(names) do
        mod:hook(FlowCallbacks, name, flow_guard)
    end
end

local function arm_offset()
    local x, y, z = mod:get("shield_side") or 0, mod:get("shield_forward") or 0, mod:get("shield_lift") or 0

    if x == 0 and y == 0 and z == 0 then
        return nil
    end

    return Vector3(x / 100, y / 100, z / 100)
end

-- 0.5.0 held shield (sword set): the shield's attach frame sits at a camera-space point (x right, y forward, z up, the
-- QIangIQsChainLaspistol 0.4.0 hold frame, HOLD_BASE there -0.2/0.42/-0.2) plus the sliders; while blocking it moves to the
-- block point. Yaw 90 turns the heater's outer face (+x of the shield frame, probe4.py) to face forward. These defaults
-- are a starting point: the sliders change the pose live.
local HOLD_BASE = { x = -0.18, y = 0.45, z = -0.08 }
local BLOCK_BASE = { x = -0.02, y = 0.42, z = -0.02 }
-- 0.5.1 default orientation (camera space): outer face (+x of the shield frame) forward, the forearm line (+y, palm to
-- elbow, QIangIQsSwordShield_arm.lua FOREARM_AXIS) to the left and a little back/down, so the shield's height (z,
-- retail extent -0.6..0.4) stands up, like the Arbites shield in first person. Quaternion.look maps y to the first
-- vector and z to the second; x then is their cross product. The turn/tilt/spin sliders rotate on top of it.
local HOLD_FACE = Vector3Box(0.1, 1, 0.05)
local HOLD_ELBOW = Vector3Box(-0.9, -0.35, -0.15)

local function hold_base_rotation()
    local face = Vector3.normalize(HOLD_FACE:unbox())
    local elbow = HOLD_ELBOW:unbox()

    elbow = Vector3.normalize(elbow - face * Vector3.dot(face, elbow))

    return Quaternion.look(elbow, Vector3.cross(face, elbow))
end
local BLOCK_BLEND_TIME = 0.12

local function blocking(ext)
    local ok, weapon_action = pcall(function()
        local ude = ScriptUnit.has_extension(ext._unit, "unit_data_system")

        return ude and ude:read_component("weapon_action")
    end)

    return ok and weapon_action and weapon_action.template_name == TEMPLATE
        and (weapon_action.current_action_name == "action_block" or weapon_action.current_action_name == "action_parry_special")
end

local function hold_pose(ext)
    local b = ext.__qiangiq_swordshield_block or 0
    local dt = ext.__qiangiq_swordshield_dt or 0

    b = math.clamp(b + (blocking(ext) and 1 or -1) * dt / BLOCK_BLEND_TIME, 0, 1)
    ext.__qiangiq_swordshield_block = b

    local w = b * b * (3 - 2 * b)
    local function axis(key)
        local idle = HOLD_BASE[key] + (mod:get("hold_" .. key) or 0) / 100
        local block = BLOCK_BASE[key] + (mod:get("block_" .. key) or 0) / 100

        return idle + (block - idle) * w
    end

    local rotation = Quaternion.multiply(Quaternion.from_yaw_pitch_roll(math.rad(mod:get("hold_turn") or 0),
        math.rad(mod:get("hold_tilt") or 0), math.rad(mod:get("hold_spin") or 0)), hold_base_rotation())

    return { kind = "hold", offset = Vector3(axis("x"), axis("y"), axis("z")), rotation = rotation }
end

local function current_action(ext)
    local ok, name = pcall(function()
        local ude = ScriptUnit.has_extension(ext._unit, "unit_data_system")
        local weapon_action = ude and ude:read_component("weapon_action")

        return weapon_action and weapon_action.template_name == TEMPLATE and weapon_action.current_action_name
    end)

    return ok and name or nil
end

-- 0.6.0 (user: "shield should be positioned similar to arbites shield", "special parry should have the blade braced
-- alongside the side of the shield and poke forward on successful special action hit like maccabian mk4 duelling sword
-- heavy atk"): kind "anim" = the left arm plays the Arbites shield animations on a hidden pose rig, and through the
-- parry special (combatsword_p1_m1.lua action_parry_special) the right arm takes the duelling sword's heavy stab windup
-- (combatsword_p3_m1.lua action_melee_start_left "heavy_charge_stab_left"), and on a successful parry the riposte
-- (action_attack_special, a stab sweep) plays its heavy stab ("heavy_attack_stab_left"). The scripted hold is the
-- fallback if a rig cannot start, and the option "Held shield pose" can pick it.
local function arm_mode(ext)
    if state.sword_set then
        local hold = hold_pose(ext)

        if mod:get("shield_hold") == "scripted" then
            hold.lift = arm_offset()

            return hold
        end

        local action = current_action(ext)
        -- 0.6.2: heater fit "arbites" raises the arm (and the heater on its grip) 13.7 cm along the shield's height, so
        -- the heater's top edge sits where the Arbites shield's does (model check in sync_shield)
        local raise = assets_ready and mod:get("shield_model") ~= "retail" and mod:get("heater_fit") ~= "handles"

        return {
            kind = "anim",
            offset = arm_offset(),
            frame_offset = raise and Vector3(0, 0, 0.137) or nil,
            phase = action == "action_parry_special" and "brace" or action == "action_attack_special" and "stab" or nil,
            dt = ext.__qiangiq_swordshield_dt or 0,
            fallback = hold,
        }
    end

    local offset = arm_offset()

    return offset and { kind = "lift", offset = offset } or nil
end

local function update_arm(ext)
    local ours, shield

    local sword

    for _, slot in pairs(ext._equipment) do
        if slot.item and slot.item.name == ITEM then
            ours, shield = slot, unit_named(slot.item_name_by_unit_1p, SHIELD_ITEM)
            sword = unit_named(slot.item_name_by_unit_1p, RIGHT_ITEM)
        end
    end

    local ok, err = pcall(Arm.update, ext, ours, shield, ours and arm_mode(ext) or nil, sword)

    if not ok then
        mod:error("arm update: %s", tostring(err))
        pcall(Arm.stop, ext)
    end
end

local function drop_slot(records, slot_name)
    drop_record(records, slot_name .. ":3p")
    drop_record(records, slot_name .. ":1p")
end

-- 0.6.5 (user: "armoryvis shows arbites shield on back not the dauntless shield"): the stowed copy of QIangIQsArmoryVis
-- is spawned from the item (QIangIQsArmoryVis_holster.lua spawn_units), so it carries the retail Arbites shield and
-- never the heater, which is a run-time unit linked to the live shield (sync_shield). ArmoryVis hands each copy to its
-- replacer mods every frame, after setting the copy's visibility (holster.lua:855-908: api.apply(holder, world,
-- equipment) with equipment[slot] shaped like an equipment slot, item_name_by_unit_3p included; api.clear(holder) before
-- the copy is deleted). The same sync_shield puts the heater on the copy. Optional: nothing here needs ArmoryVis.
local armory_vis_api = {
    apply = function(holder, _, equipment)
        local ext = holder and holder._ext

        if not ext or type(equipment) ~= "table" then
            return
        end

        local records = holder.__qiangiq_swordshield

        if not records then
            records = {}
            holder.__qiangiq_swordshield = records
        end

        for slot_name, entry in pairs(equipment) do
            if entry.item and entry.item.name == ITEM then
                place_grip(entry.item_name_by_unit_3p)
                sync_shield(ext, records, slot_name .. ":copy", entry.item_name_by_unit_3p, entry.hidden_3p == false, false)
            end
        end
    end,
    clear = function(holder)
        local records = holder and holder.__qiangiq_swordshield

        if records then
            local keys = {}

            for key in pairs(records) do
                keys[#keys + 1] = key
            end

            for _, key in ipairs(keys) do
                drop_record(records, key)
            end
        end
    end,
}

mod.armory_vis = armory_vis_api

local function register_armory_vis()
    local armory_vis = get_mod("QIangIQsArmoryVis")

    if armory_vis and type(armory_vis.register) == "function" then
        local ok, registered = pcall(armory_vis.register, "QIangIQsSwordShield", armory_vis_api)

        mod:info("ArmoryVis stowed heater: %s", ok and registered and "registered" or "not registered")
    end
end

local function apply_visuals(ext)
    if not ext._is_local_unit or not ext._equipment then
        return
    end

    local records = ext.__qiangiq_swordshield

    if not records then
        records = {}
        ext.__qiangiq_swordshield = records
    end

    for slot_name, slot in pairs(ext._equipment) do
        local item = slot.item

        if item and item.name == ITEM then
            place_grip(slot.item_name_by_unit_3p)
            place_grip(slot.item_name_by_unit_1p)
            sync_shield(ext, records, slot_name .. ":3p", slot.item_name_by_unit_3p, slot.hidden_3p == false, false)
            sync_shield(ext, records, slot_name .. ":1p", slot.item_name_by_unit_1p, slot.hidden_1p == false, true)
            sync_relinked(records, slot_name, slot.item_name_by_unit_1p, slot.hidden_1p == false)
        elseif records[slot_name .. ":3p"] or records[slot_name .. ":1p"] then
            drop_slot(records, slot_name)
        end
    end

    update_arm(ext)
end

mod:hook_safe(CLASS.PlayerUnitVisualLoadoutExtension, "init", function(self, extension_init_context)
    self.__qiangiq_swordshield_world = extension_init_context and extension_init_context.world
end)

mod:hook_safe(CLASS.PlayerUnitVisualLoadoutExtension, "_update_item_visibility", function(self)
    if self._is_local_unit then
        tracked[self] = true
        apply_visuals(self)
    end
end)

mod:hook_safe(CLASS.PlayerUnitVisualLoadoutExtension, "update", function(self, unit, dt)
    if tracked[self] then
        self.__qiangiq_swordshield_dt = dt
        apply_visuals(self)
    end
end)

mod:hook(CLASS.PlayerUnitVisualLoadoutExtension, "_unequip_item_from_slot", function(func, self, slot_name, ...)
    local records = self.__qiangiq_swordshield
    local slot = self._equipment and self._equipment[slot_name]

    -- the shield hangs on the arm driver while lifted: give it back before the game deletes the weapon units
    if slot and slot.item and slot.item.name == ITEM then
        pcall(Arm.stop, self)
    end

    if records then
        drop_slot(records, slot_name)
    end

    return func(self, slot_name, ...)
end)

mod:hook(CLASS.PlayerUnitVisualLoadoutExtension, "destroy", function(func, self, ...)
    local records = self.__qiangiq_swordshield

    pcall(Arm.stop, self)

    if records then
        for key in pairs(records) do
            drop_record(records, key)
        end
    end

    tracked[self] = nil

    return func(self, ...)
end)

-- HUD icon ------------------------------------------------------------------------------------------------------------
-- No retail sword-and-shield icon exists. The icon (assets/swordshield_hud.png, _build/build_hud_icon.py) is compiled
-- into this mod's own Custom Assets build as a texture (_build/build_hud_glb.py wraps it in a one-quad unit, Custom/hud_icon)
-- and becomes resident with the heater; no SimpleAssets (user rule 2026-10-25: mods stand alone). The weapon HUD icon
-- widget (hud_element_player_weapon.lua:813 set_icon) is a texture pass whose value is a material; it is switched to
-- content/ui/materials/base/ui_default_base with material_values.texture_map, the emote wheel's way
-- (hud_element_emote_wheel_definitions.lua:76-83, hud_element_emote_wheel.lua:134). Without Custom Assets the HUD keeps
-- the game's own icon (see build_item). Setting hud_icon picks "game" (default) or "drawn".
local HUD_ICON_MATERIAL = "content/ui/materials/base/ui_default_base"
local HUD_ICON_TEXTURE = "content/mods/qiangiq_swordshield/hud_icon_material_1_bca"
local icon_ready = false

mod:hook_require("scripts/ui/hud/elements/player_weapon/hud_element_player_weapon", function(HudElementPlayerWeapon)
    mod:hook_safe(HudElementPlayerWeapon, "init", function(self, _, _, _, data)
        self.__qiangiq_swordshield = data and data.item and data.item.name == ITEM or false
    end)

    mod:hook_safe(HudElementPlayerWeapon, "update", function(self)
        local texture = self.__qiangiq_swordshield and icon_ready and mod:get("hud_icon") == "drawn" and HUD_ICON_TEXTURE
        local widget = texture and self._widgets_by_name and self._widgets_by_name.icon

        if not widget then
            return
        end

        local style = widget.style.icon

        style.material_values = style.material_values or {}

        if widget.content.icon ~= HUD_ICON_MATERIAL or style.material_values.texture_map ~= texture then
            widget.content.icon = HUD_ICON_MATERIAL
            style.material_values.texture_map = texture
            widget.dirty = true
        end
    end)
end)

-- Anim event guard (QIangIQsMeltagun 0.2.1 pattern): every grafted event is in the assault_shield_maul state machine,
-- this only skips one that is not instead of letting it fail. AuthoritativePlayerUnitAnimationExtension (hosting) has no
-- _local_wielded_weapon_template, so the wielded template name is stored from inventory_slot_wielded.
local skipped_events = {}

local function guard(unit_field)
    return function(func, self, event_name, ...)
        if (self.__qiangiq_swordshield_wielded or self._local_wielded_weapon_template) == TEMPLATE then
            local unit = self[unit_field]

            -- 0.6.0: the Arbites pose rig hears the same first-person events (block, push, equip, movement)
            pcall(Arm.anim_event, unit, event_name)

            if unit and not Unit.has_animation_event(unit, event_name) then
                if not skipped_events[event_name] then
                    skipped_events[event_name] = true
                    mod:info("skipped anim event %s: not in the state machine", tostring(event_name))
                end

                return
            end
        end

        return func(self, event_name, ...)
    end
end

for _, class_name in ipairs({ "PlayerUnitAnimationExtension", "AuthoritativePlayerUnitAnimationExtension" }) do
    mod:hook_safe(CLASS[class_name], "inventory_slot_wielded", function(self, weapon_template)
        self.__qiangiq_swordshield_wielded = weapon_template and weapon_template.name or false
    end)

    for _, method in ipairs({ "anim_event_1p", "anim_event_with_variable_float_1p", "anim_event_with_variable_floats_1p" }) do
        mod:hook(CLASS[class_name], method, guard("_first_person_unit"))
    end
end

mod.update = function()
    poll()
end

-- Custom Assets API 1, the QIangIQsDauntlessArmory acquire call. Optional: without Custom Assets the weapon works with
-- the retail shield and the combat sword HUD icon (user rule 2026-10-25: no other mod is needed to function).
local function acquire(asset_id, on_ready)
    local custom_assets = get_mod("CustomAssets")

    if not custom_assets or not custom_assets.is_api_compatible or not custom_assets.is_api_compatible(1) then
        mod:info("Custom Assets (API 1) is not installed: %s is not shown, the retail look stays", asset_id)

        return
    end

    local ticket, err = custom_assets.acquire(mod, asset_id, function(_, _, load_error)
        if load_error then
            mod:info("%s did not load: %s (run CUSTOM_ASSETS_PATCH.bat with the game closed)", asset_id, tostring(load_error))

            return
        end

        on_ready()
        mod:info("%s loaded", asset_id)
    end, { resident = true, reference_name = asset_id })

    if not ticket then
        mod:info("%s could not be requested: %s", asset_id, tostring(err))
    end
end

local function acquire_assets()
    acquire(SHIELD_ASSET, function()
        assets_ready = true
    end)
    acquire(ARM_DRIVER_ASSET, function()
        driver_ready = true
    end)
    acquire(HUD_ICON_ASSET, function()
        icon_ready = true
    end)
end

mod.on_all_mods_loaded = function()
    add_to_unlock_list()
    acquire_assets()
    register_armory_vis()
end

mod.on_unload = function()
    local ok, cache = pcall(MasterItems.get_cached)

    if ok and cache then
        for _, name in ipairs({ ITEM, GRIP_ITEM, BLADE_ITEM, SHIELD_ITEM }) do
            cache[name] = nil
        end
    end

    if state.template_ours then
        WeaponTemplates[TEMPLATE] = nil
    end
end

-- Equip without the backend (QIangIQsShardStaff override): only where this client hosts ----------------------------
local function local_player()
    local players = Managers.player

    return players and players:local_player_safe(1)
end

local function equipped_item_name(player, slot)
    local unit = player and player.player_unit

    if not unit or not Unit.alive(unit) then
        return nil
    end

    local extension = ScriptUnit.has_extension(unit, "visual_loadout_system")
    local item = extension and extension:item_from_slot(slot)

    return item and item.name
end

local previous = {}

local function override(slot, item_name)
    local player = local_player()
    local sync = Managers.profile_synchronization
    local host = sync and sync:synchronizer_host()

    if not player then
        say("no local player")

        return false
    end

    if not host then
        say("not the host here. Use the Psykhanium, a SoloPlay game or a game you host")

        return false
    end

    host:override_slot(player:peer_id(), player:local_player_id(), slot, item_name)
    say("override_slot(%s, %s) sent", slot, tostring(item_name))

    return true
end

local function package_state(path)
    local ok, exists = pcall(Application.can_get_resource, "package", path)

    return ok and tostring(exists) or "?"
end

local function status()
    say("template %s (id %s, from %s), item %s (id %s, slot %s, archetypes %s)", tostring(state.template_ok),
        tostring(state.template_id), SOURCE_TEMPLATE, tostring(state.item_ok), tostring(state.item_id), tostring(state.slot),
        table.concat(state.archetypes or {}, ","))
    say("  grip_08 package found: %s, blade_08 package found: %s", package_state(GRIP_UNIT), package_state(BLADE_UNIT))
    say("  heater model loaded: %s (shield model setting: %s), HUD icon loaded: %s", tostring(assets_ready),
        tostring(mod:get("shield_model")), tostring(icon_ready))
    say("  1P animations: %s; arm driver loaded: %s", state.sword_set and "combat_sword" or state.retail_anims and "combat_sword_shield" or "assault_shield_maul",
        tostring(driver_ready))

    local player = local_player()
    local unit = player and player.player_unit
    local ext = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "visual_loadout_system")

    if ext then
        say("  %s", Arm.debug(ext))
    end

    if #state.notes > 0 then
        say("  %s", table.concat(state.notes, "; "))
    end
end

mod:command("swordshield", mod:localize("command_swordshield"), function(action)
    action = action or "status"

    if action == "status" then
        status()
    elseif action == "equip" then
        if not (state.template_ok and state.item_ok and state.slot) then
            say("not ready yet (template %s, item %s)", tostring(state.template_ok), tostring(state.item_ok))

            return
        end

        local player = local_player()

        previous[state.slot] = previous[state.slot] or (player and equipped_item_name(player, state.slot))
        override(state.slot, ITEM)
    elseif action == "restore" then
        local any = false

        for slot, item_name in pairs(previous) do
            if item_name and override(slot, item_name) then
                previous[slot] = nil
                any = true
            end
        end

        if not any then
            say("nothing to restore (equip first)")
        end
    else
        say("usage: /swordshield [status|equip|restore]")
    end
end)
