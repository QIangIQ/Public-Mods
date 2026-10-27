# Public Mods

Darktide mods by QIangIQ. Each mod is a separate zip in [`mods/`](mods).

## Install
1. Install the Darktide Mod Framework (DMF) and Darktide Mod Loader.
2. Unzip a mod into `Warhammer 40,000 DARKTIDE\mods\` so you get `mods\<ModName>\<ModName>.mod`.
3. Add the mod name on its own line to `mods\mod_load_order.txt`, below `dmf`.
   Mods that depend on others (for example anything using `QIangIQsSyncChannel`) must come after them.

## Load order
DMF loads `mod_load_order.txt` from top to bottom; the dependencies written in a `.mod` file do not reorder anything. Put each mod below the ones it uses. Recommended fragment (everything marked optional can be left out):

```
dmf
CustomAssets                # optional: only for mods with custom models/icons
QIangIQsSyncChannel         # needed by the mods that sync between players
QIangIQsLegacyTalents       # optional for Novitiate
QIangIQsMartyrdom           # optional for Novitiate (do not run both trees at once)
QIangIQsScumHook            # optional for Novitiate (gives the Chain Hook its hook head model)
QIangIQsNovitiate
QIangIQsJavelin
QIangIQsSwordShield
QIangIQsBell                # below CustomAssets and below SoloPlay if you use it
```

- `QIangIQsNovitiate` works on its own. LegacyTalents, Martyrdom, ScumHook and CustomAssets are optional lookups; without them the Novitiate just skips the matching extra (no legacy-tree detection, the chain keeps its own spear head, no Martyrdom conflict warning). `realms_loadout` is only needed for its gear screen.
- `QIangIQsJavelin` and `QIangIQsSwordShield` do not need `SimpleAudio` or any other helper mod; Custom Assets only adds the models and icons.
- If you see `AnimationStateMachine ... does not exist` after pressing F8 or using the Chain Hook, re-download the current Novitiate zip, run `CUSTOM_ASSETS_PATCH.bat` with the game closed, and check the order above.

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
