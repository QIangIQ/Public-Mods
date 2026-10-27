local mod = get_mod("QIangIQsTwinShields")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "raise_twin_shields",
				type = "checkbox",
				default_value = true,
				title = "raise_twin_shields",
				tooltip = "raise_twin_shields_tooltip",
			},
			{
				setting_id = "block_ownerless_companions",
				type = "checkbox",
				default_value = true,
				title = "block_ownerless_companions",
				tooltip = "block_ownerless_companions_tooltip",
			},
			{
				setting_id = "fix_capped_killing_blow",
				type = "checkbox",
				default_value = true,
				title = "fix_capped_killing_blow",
				tooltip = "fix_capped_killing_blow_tooltip",
			},
			{
				setting_id = "log_capped_hits",
				type = "checkbox",
				default_value = false,
				title = "log_capped_hits",
				tooltip = "log_capped_hits_tooltip",
			},
		},
	},
}
