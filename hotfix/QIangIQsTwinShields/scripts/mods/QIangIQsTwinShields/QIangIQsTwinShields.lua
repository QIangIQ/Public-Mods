local mod = get_mod("QIangIQsTwinShields")

-- --------------------------------------------------------------------------
-- Twins spawn with their void shields up
-- --------------------------------------------------------------------------
--
-- Why they spawn bare (decompiled source, Aussiemon/Darktide-Source-Code 1.12.5):
--   * Both twins use toughness template twin_captain_one
--     (renegade_twin_captain_breed.lua:73, renegade_twin_captain_two_breed.lua:82),
--     which has start_depleted = true (minion_toughness_templates.lua:64-73).
--     Regular captains' templates do not, so they spawn shielded.
--   * Every place the game itself spawns the twins raises the shield right
--     after spawn_minion with
--         toughness_extension:set_toughness_damage(0, reactivation_override = true)
--     - their mission:  mutator_toxic_gas_twins.lua:810-815 and 830-834
--     - Havoc / injected twins: mutator_monster_spawner_injection_templates.lua:27-31
--     - survival:       game_mode_survival.lua:680
--   * creature_spawner calls MinionSpawnManager.spawn_minion directly
--     (creature_spawner.lua:481 and :568) and never makes that call, so
--     its twins keep the depleted template's empty shield.
--
-- What this does: after MinionSpawnManager.spawn_minion returns a twin whose
-- shield is fully depleted, make the same set_toughness_damage(0, true) call.
-- The reactivation flag is what the game uses to turn the shield collider and
-- effects on (MinionToughnessExtension._update_toughness: was_reactivated ->
-- linked actor c_captain_void_shield enabled). Twins the game already
-- shields are untouched: their shield is raised by the game's own call a line
-- later, exactly as before.
--
-- Left alone on purpose: the "depleted captain shields" mission modifier
-- (mutator_depleted_captain_shields, mutator_modify_pacing_templates.lua:53),
-- which MinionSpawnManager.spawn_minion uses to spawn captains without shields
-- (minion_spawn_manager.lua:137-145), and any spawn that explicitly asks for
-- optional_void_shield_start_depleted.
--
-- spawn_minion runs on the host; in SoloPlay and the Psykanium you are the host.

local MinionSpawnManager = require("scripts/managers/minion/minion_spawn_manager")

local TWINS = {
	renegade_twin_captain = true,
	renegade_twin_captain_two = true,
}

local function depleted_shields_mutator_active()
	local mutator_manager = Managers.state and Managers.state.mutator

	if not mutator_manager or not mutator_manager.mutator then
		return false
	end

	local ok, mutator = pcall(mutator_manager.mutator, mutator_manager, "mutator_depleted_captain_shields")

	return ok and mutator ~= nil and mutator ~= false
end

local function raise_shield(unit)
	if not unit or not Unit.alive(unit) then
		return false
	end

	local toughness_extension = ScriptUnit.has_extension(unit, "toughness_system")

	if not toughness_extension or not toughness_extension.set_toughness_damage
		or not toughness_extension.max_toughness or not toughness_extension.toughness_damage then
		return false
	end

	local max_toughness = toughness_extension:max_toughness()
	local toughness_damage = toughness_extension:toughness_damage()

	if type(max_toughness) ~= "number" or type(toughness_damage) ~= "number" or toughness_damage < max_toughness then
		return false
	end

	local reactivation_override = true

	toughness_extension:set_toughness_damage(0, reactivation_override)

	return true
end

-- --------------------------------------------------------------------------
-- Companions spawned without an owner
-- --------------------------------------------------------------------------
-- Crash 2026-09-29 03:24: creature_spawner's spawn key spawned "companion_dog"
-- with no owner. Its setup failed at once
--   companion_visual_loadout_extension.lua:158: attempt to index field '_owner_player'
-- and the half-built dog left in the enemy broadphase then crashed the
-- player's melee check:
--   player_unit_attack_intensity_extension.lua:179: 'unit_data_extension' (a nil value)
-- The game spawns companions only through CompanionSpawnerExtension, always
-- with optional_owner_player_unit (companion_spawner_extension.lua:227;
-- minion_companion_dog_unit_template.lua:38-39 reads it). The companion
-- breeds are the ones with a minion_companion_* unit template
-- (companion_dog_breed.lua:40, companion_servo_skull_breed.lua:29).
-- So a companion spawn without that owner is refused (returns nil, which
-- creature_spawner reports as "not available") instead of crashing.
local Breeds = require("scripts/settings/breed/breeds")

local function ownerless_companion(breed_name, optional_param_table)
	local breed = Breeds[breed_name]
	local template = breed and breed.unit_template_name

	if type(template) ~= "string" or string.sub(template, 1, 17) ~= "minion_companion_" then
		return false
	end

	return type(optional_param_table) ~= "table" or optional_param_table.optional_owner_player_unit == nil
end

mod:hook(MinionSpawnManager, "spawn_minion", function (func, self, breed_name, position, rotation, side_id, optional_param_table, ...)
	if mod:get("block_ownerless_companions") ~= false and ownerless_companion(breed_name, optional_param_table) then
		mod:echo("Blocked spawning %s without an owner - companions need a player and would crash the game.", tostring(breed_name))

		return nil
	end

	local asked_depleted = type(optional_param_table) == "table" and optional_param_table.optional_void_shield_start_depleted == true

	local unit = func(self, breed_name, position, rotation, side_id, optional_param_table, ...)

	if unit and TWINS[breed_name] and mod:get("raise_twin_shields") ~= false
		and not asked_depleted and not depleted_shields_mutator_active() then
		local ok, raised = pcall(raise_shield, unit)

		if not ok then
			mod:error("could not raise %s's void shield: %s", tostring(breed_name), tostring(raised))
		elseif raised then
			mod:info("%s spawned without a void shield - shield raised", tostring(breed_name))
		end
	end

	return unit
end)

-- --------------------------------------------------------------------------
-- A huge hit counted as a killing blow on a Twin that survives it
-- --------------------------------------------------------------------------
--
-- Report 2026-09-28: in Havoc the Twins sometimes stop rendering but keep
-- moving, shooting and throwing mines, after one very large hit (usually a
-- Thunder Hammer).
--
-- What the source shows (Aussiemon/Darktide-Source-Code 1.12.5):
--   * The Twins are the ONLY breeds with clamp_health_percent_damage
--     (renegade_twin_captain_breed.lua:32, renegade_twin_captain_two_breed.lua;
--     no other breed file sets it): one hit can take at most 20% of max health.
--   * That cap is applied late, inside Damage.deal_damage
--     (damage.lua:58-64), on the host only.
--   * The hit's result is decided earlier, from the UNCAPPED damage:
--     Attack -> _handle_attack -> DamageTakenCalculation.calculate_attack_result
--     (attack.lua:497; damage_taken_calculation.lua:97-107, where
--     _calculate_health_damage returns "died" when the hit exceeds the
--     remaining health).
--   So a hit bigger than a Twin's remaining health, on a Twin with more than
--   20% left, comes out as attack_result "died" while the Twin survives the
--   capped damage. Everything that reads the result then treats a living Twin
--   as killed: the killing-blow wound is applied and sent to every client
--   (damage.lua:299-313 -> WoundsExtension.add_wounds is_killing_blow,
--   rpc_minion_add_wounds), kill feed/on-kill procs (attack.lua:385, 653,
--   attack_report_manager.lua:201).
--
-- Not provable from Lua: the Twin's model is drawn by the engine, so the
-- source cannot show which of those makes it vanish. This is the one code
-- path in which a single very large hit makes the game treat a living Twin
-- as dead, and it exists only for the Twins - which is why it is fixed here.
-- If a Twin still goes invisible with this on, the console log will not
-- show "capped killing blow" lines for it, which rules this path out.
--
-- The fix: when calculate_attack_result returns "died" for a breed with
-- clamp_health_percent_damage, apply the same cap Damage.deal_damage will
-- apply; if the capped hit does not kill, the result becomes "damaged".
-- The damage numbers are untouched (Damage.deal_damage still caps them), and
-- instakills are left alone (the cap does not apply to them either).

local DamageTakenCalculation = require("scripts/utilities/attack/damage_taken_calculation")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local attack_results = AttackSettings.attack_results

local function capped_hit_survives(attacked_unit, remaining_damage, current_health_damage, max_health)
	local unit_data_extension = ScriptUnit.has_extension(attacked_unit, "unit_data_system")
	local breed = unit_data_extension and unit_data_extension:breed()
	local clamp = breed and breed.clamp_health_percent_damage

	if not clamp or type(max_health) ~= "number" or type(current_health_damage) ~= "number"
		or type(remaining_damage) ~= "number" then
		return false, nil, nil
	end

	-- Same arithmetic as damage.lua:58-64 and :107-110.
	local capped_damage = math.min(remaining_damage, max_health * clamp)
	local remaining_health = max_health - current_health_damage - capped_damage

	return remaining_health > 0, breed.name, clamp
end

mod:hook(DamageTakenCalculation, "calculate_attack_result", function (func, damage_amount, damage_profile, attack_type, attack_direction, instakill, is_invulnerable, damage_allowed, health_setting, current_health_damage, current_permanent_damage, max_health, max_wounds, toughness_template, weapon_toughness_template, current_toughness_damage, movement_state, shield_setting, attacked_unit_stat_buffs, attacked_unit_keywords, attacked_unit, damage_type, attacking_unit_stat_buffs, shield_template, ...)
	local attack_result, remaining_damage, remaining_permanent_damage, toughness_damage, damage_absorbed = func(damage_amount, damage_profile, attack_type, attack_direction, instakill, is_invulnerable, damage_allowed, health_setting, current_health_damage, current_permanent_damage, max_health, max_wounds, toughness_template, weapon_toughness_template, current_toughness_damage, movement_state, shield_setting, attacked_unit_stat_buffs, attacked_unit_keywords, attacked_unit, damage_type, attacking_unit_stat_buffs, shield_template, ...)

	if attack_result == attack_results.died and not instakill and attacked_unit
		and mod:get("fix_capped_killing_blow") ~= false then
		local ok, survives, breed_name, clamp = pcall(capped_hit_survives, attacked_unit, remaining_damage, current_health_damage, max_health)

		if ok and survives then
			attack_result = attack_results.damaged

			if mod:get("log_capped_hits") then
				pcall(mod.info, mod, "capped killing blow on %s: %.0f damage capped to %.0f percent of max health, not a kill - counted as a normal hit",
					tostring(breed_name), remaining_damage or 0, (clamp or 0) * 100)
			end
		end
	end

	return attack_result, remaining_damage, remaining_permanent_damage, toughness_damage, damage_absorbed
end)
