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

## Single-file fixes (2026-10-27)
Loose copies of the `.lua` files that changed, under [`hotfix/`](hotfix). Each one goes to the same relative path under `Warhammer 40,000 DARKTIDE\mods\` (the folder inside `hotfix/` is the mod folder). Close the game first. No Custom Assets patcher run is needed for these.

## Notes
- `QIangIQsAnotherScoreboard` is based on AnotherScoreboard and `QIangIQsMultiBind` is based on MultiBind by Seph. Credit to their original authors.
- The `*Prime`, `QIangIQsEmber` and `QIangIQsEmberWF` mods contain character models and textures converted from other games. They belong to their respective owners and are shared for personal use only.

## Recently added
**2026-11-13**
- New: `QIangIQsReviveDance` 0.1.0 (your character dances California Gurls while you revive or free a teammate; only you see it). Needs Custom Assets: run `CUSTOM_ASSETS_PATCH.bat` with the game closed after installing. The dance motion is retargeted from a Helldivers 2 community emote mod.
**2026-11-12**
- QIangIQsAntiSpecialist 0.3.2: fixes a possible crash (raycasts no longer run while the physics thread is busy); tuning log now off by default.
**2026-11-09**
- New tools: `QIangIQsAntiSpecialist` (counters for Trapper, Poxburster, Pox Hound and Mutant), `QIangIQsAutoQuell` (automatic quelling for Psyker staves, stop percentage per staff, optional Warp Siphon toggle), `QIangIQsBuffExpiryFlash` (flash when an attack buff from an action runs out), `QIangIQsToughnessGauge` (toughness speedometer on the HUD), `QIangIQsRichPresence` (Discord Rich Presence, no DLL needed).
- New CS2 weapons: `QIangIQsButterflyKnife` 1.8.10, `QIangIQsBayonet`, `QIangIQsStiletto`, `QIangIQsBowieKnife` (Combat Knife, optional Duelling Swords for the Butterfly Knife), `QIangIQsDeagle` and `QIangIQsGlock` (pistols). They need Custom Assets: run `CUSTOM_ASSETS_PATCH.bat` with the game closed after installing. CS2 sounds play through `SimpleAudio` if you have it.
- New: `QIangIQsModelSync` 2.0.0 (party members see each other's QIangIQ model and weapon replacer mods; needs `QIangIQsSyncChannel` and Vox Manifold), `QIangIQsStatTotals` (HUD box with your live combined stat totals), `QIangIQsMMJHud` (Mullet Mad Jack style HUD frame; split into parts, see [`mods/QIangIQsMMJHud`](mods/QIangIQsMMJHud)).
- The CS2 weapons contain models, animations and sounds from Counter-Strike 2, and `QIangIQsMMJHud` contains art and sound from Mullet Mad Jack. They belong to their respective owners.
- Updated: `QIangIQsTrappers` (now with its own Trapper auto-dodge), `QIangIQsFingerGun` 0.1.2, `QIangIQsMMJPistol` 0.1.1, `QIangIQsMMJChainPistol` 0.1.1, `QIangIQsTaunts`, `QIangIQsTalentHeat`, `QIangIQsCoherencyZone`, `QIangIQsBismuthSword`.
- The Bell: hotfix 7 in [`bell/`](bell) (new VT2 sky and lighting options, host mission setting, a far-horde crash fix, navmesh fix). Run `CUSTOM_ASSETS_PATCH.bat` after extracting it.
**2026-11-04**
- New custom weapons: `QIangIQsFingerGun`, the `QIangIQsMMJ*` weapons (Arcade Pistol, Bat, Chain Pistol, Double Barrel, Flame Katana, Ice Katana, Katana, Magic Glove, Minigun, Pistol, Plasma Gun, Rail Gun, Rifle, Shotgun, Silenced Uzi, Sniper, Uzi) and the `QIangIQsBoltgun*` weapons (Bolter, Chainsword, Flamer, Plasma Pistol, Power Sword). `QIangIQsTaunts` adds taunts. `QIangIQsHorizonMaulShields` adds maul and shield skins.
- These contain art and sound from Mullet Mad Jack, Warhammer 40,000: Boltgun and Horizon Walker. They belong to their respective owners.
- `QIangIQsMMJPlasmaGun` and `QIangIQsMMJRailGun` are split into parts: see [`mods/QIangIQsMMJPlasmaGun`](mods/QIangIQsMMJPlasmaGun) and [`mods/QIangIQsMMJRailGun`](mods/QIangIQsMMJRailGun).
- New weapons: `QIangIQsStubRifle`, `QIangIQsChainaxe2h`, `QIangIQsChainsword2h`, `QIangIQsDauntlessMaul`. They turn unreleased game weapons into usable ones and have not been tested in game yet, so expect bugs.
- New crash fixes: `QIangIQsActionLookupFix` (crash on Fatshark servers when weapon mods are loaded) and `QIangIQsAbilityPackagePin` (crash when a grenade or ability package unloads while still in use).
- New tools: `QIangIQsCoherencyZone` (filled circle showing coherency range), `QIangIQsTrappers` (overlay for Trappers: target, net loaded, firing range), `QIangIQsHitboxView` (shows enemy hit shapes coloured by armour), `QIangIQsPhotoMode`, `QIangIQsTreeZoom`.
- Updated from the current versions: `QIangIQsAnubis`, `QIangIQsBismuthSword`, `QIangIQsChainLaspistol`, `QIangIQsCrossbow`, `QIangIQsEmber`, `QIangIQsEnemyBeams`, `QIangIQsFlamerPistol`, `QIangIQsInstantCharacterChange`, `QIangIQsJavelin`, `QIangIQsMeltagun`, `QIangIQsOraxia`, `QIangIQsPowerAxe`, `QIangIQsPrototype`, `QIangIQsRearview`, `QIangIQsShardStaff`, `QIangIQsSpecialTracer`, `QIangIQsSpillway`, `QIangIQsSwordShield`, `QIangIQsTalentHeat`, `QIangIQsTwinShields`, `QIangIQsVoicelineSpammer9000`, `QIangIQsWallclimber`. These zips also drop leftover development files.

**Earlier**
- **The Bell map** (`QIangIQsBell` 0.2.16, Vermintide 2's The Bell): too big for one file, so it is in [`bell/`](bell) as 10 parts plus a join script. See [`bell/README.md`](bell/README.md).
- `QIangIQsNovitiate`: a Zealot-variant "class" with its own talent tree and abilities (press F8 on a Zealot to mark it as a Novitiate). Needs `realms_loadout` for its gear screen. The optional Sister Lacrima model is not included (too large); the default Dauntless look works without it.
- `QIangIQsJavelin` (throwing spear) and `QIangIQsSprayerOgryn` (enemy used by The Bell map). `QIangIQsCrossbow`, `QIangIQsFlamerPistol`, `QIangIQsAnotherScoreboard`, `QIangIQsSyncChannel`, `QIangIQsSwordShield` and `QIangIQsPowerAxe` were updated.
- Mods with custom models (Novitiate, Javelin, Crossbow, Flamer Pistol, SwordShield: heater shield and HUD icon) need Custom Assets: run its `CUSTOM_ASSETS_PATCH.bat` with the game closed after installing.
- Weapons: `QIangIQsCrossbow`, `QIangIQsFlamerPistol`, `QIangIQsMeltagun`, `QIangIQsSwordShield`, `QIangIQsChainLaspistol`, `QIangIQsPowerAxe`.
- Utilities: `QIangIQsSpillway`, `QIangIQsTalentHeat`, `QIangIQsInstantCharacterChange`. `QIangIQsEnemyBeams` was updated.
- The new weapons are fresh and may still have bugs; report them in the Discord.
