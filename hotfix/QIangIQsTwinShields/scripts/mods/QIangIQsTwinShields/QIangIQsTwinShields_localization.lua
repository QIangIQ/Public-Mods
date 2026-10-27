return {
	mod_name = {
		en = "QIangIQ's Twin Shields",
	},
	mod_description = {
		en = "Fixes for Rinda and Rodin (the Karnak Twins): they spawn with their void shields up when spawned by creature_spawner or other mods in SoloPlay / the Psykanium, and one huge hit no longer counts as a 'killing blow' on a twin that survives it (the source of invisible twins in Havoc). Host-side.",
	},
	raise_twin_shields = {
		en = "Give spawned Twins their void shields",
	},
	raise_twin_shields_tooltip = {
		en = "A Twin spawned without its shield (creature_spawner, SoloPlay, Psykanium) gets it raised, the same call the game makes when it spawns them itself. Twins the game already shields are unchanged, and the 'depleted captain shields' modifier is respected.",
	},
	block_ownerless_companions = {
		en = "Block companion spawns without an owner",
	},
	block_ownerless_companions_tooltip = {
		en = "Spawning the Arbites dog or the servo-skull with creature_spawner (or any mod) without a player owner crashes the game a moment later. The game itself always spawns companions for a player; this refuses owner-less companion spawns.",
	},
	fix_capped_killing_blow = {
		en = "Fix Twins treated as killed by a huge hit",
	},
	fix_capped_killing_blow_tooltip = {
		en = "The Twins can only lose 20%% of their max health per hit, but the game decides 'killed' from the uncapped hit. A huge hit (e.g. a charged Thunder Hammer) on a Twin below that is treated as a kill - killing-blow wound sent to everyone, kill feed and on-kill effects - while the Twin lives on. With this on, such a hit counts as a normal hit.",
	},
	log_capped_hits = {
		en = "Log capped killing blows",
	},
	log_capped_hits_tooltip = {
		en = "Write a line to the log for every hit the fix above catches. Off by default: it can fire on every hit in a Twins fight.",
	},
}
