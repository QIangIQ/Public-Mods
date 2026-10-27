# Public Mods

Darktide mods by QIangIQ. Each mod is a separate zip in [`mods/`](mods).

## Install
1. Install the Darktide Mod Framework (DMF) and Darktide Mod Loader.
2. Unzip a mod into `Warhammer 40,000 DARKTIDE\mods\` so you get `mods\<ModName>\<ModName>.mod`.
3. Add the mod name on its own line to `mods\mod_load_order.txt`, below `dmf`.
   Mods that depend on others (for example anything using `QIangIQsSyncChannel`) must come after them.

## Notes
- `QIangIQsAnotherScoreboard` is based on AnotherScoreboard and `QIangIQsMultiBind` is based on MultiBind by Seph. Credit to their original authors.
- The `*Prime`, `QIangIQsEmber` and `QIangIQsEmberWF` mods contain character models and textures converted from other games. They belong to their respective owners and are shared for personal use only.

## Recently added
- **The Bell map** (`QIangIQsBell` 0.2.16, Vermintide 2's The Bell): too big for one file, so it is in [`bell/`](bell) as 10 parts plus a join script. See [`bell/README.md`](bell/README.md).
- `QIangIQsNovitiate`: a Zealot-variant "class" with its own talent tree and abilities (press F8 on a Zealot to mark it as a Novitiate). Needs `realms_loadout` for its gear screen. The optional Sister Lacrima model is not included (too large); the default Dauntless look works without it.
- `QIangIQsJavelin` (throwing spear) and `QIangIQsSprayerOgryn` (enemy used by The Bell map). `QIangIQsCrossbow`, `QIangIQsFlamerPistol`, `QIangIQsAnotherScoreboard`, `QIangIQsSyncChannel`, `QIangIQsSwordShield` and `QIangIQsPowerAxe` were updated.
- Mods with custom models (Novitiate, Javelin, Crossbow, Flamer Pistol, SwordShield: heater shield and HUD icon) need Custom Assets: run its `CUSTOM_ASSETS_PATCH.bat` with the game closed after installing.
- Weapons: `QIangIQsCrossbow`, `QIangIQsFlamerPistol`, `QIangIQsMeltagun`, `QIangIQsSwordShield`, `QIangIQsChainLaspistol`, `QIangIQsPowerAxe`.
- Utilities: `QIangIQsSpillway`, `QIangIQsTalentHeat`, `QIangIQsInstantCharacterChange`. `QIangIQsEnemyBeams` was updated.
- The new weapons are fresh and may still have bugs; report them in the Discord.
