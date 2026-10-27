# QIangIQsBell 0.2.16 (Vermintide 2's The Bell in Darktide)

The map is 898 MB, more than GitHub allows in one file, so it is split into 10 parts.

**Get it:** download all 10 `QIangIQsBell.zip.0xx` files and `JOIN_BELL.bat` into one folder (on GitHub: open each file and press the download button). Then either
- open `QIangIQsBell.zip.001` with 7-Zip or WinRAR (they read the other parts by themselves), or
- double-click `JOIN_BELL.bat`, which makes `QIangIQsBell.zip`.

SHA-256 of the joined zip: `ea0466d1b2d836526a9f0e4529a3aafa6a2ea357df32d5552050aba2ac88c6fd`

**Install**
1. Extract into `Warhammer 40,000 DARKTIDE/mods` so you get `mods/QIangIQsBell/QIangIQsBell.mod`.
2. Add `QIangIQsBell` to `mods/mod_load_order.txt`, below `CustomAssets`.
3. With the game closed, run `CUSTOM_ASSETS_PATCH.bat` in the game folder (the map is a Custom Assets build).

**Needs:** Darktide Mod Framework, Custom Assets, SoloPlay. For co-op through Realms: Realms, QIangIQsSyncChannel and Vox Manifold. Optional: QIangIQsSprayerOgryn (boss).

**Play:** start "The Bell (Vermintide 2) - QIangIQ" from the SoloPlay mission list. Blow the brick seal with the breach charge, follow the path to the bell, break its three chain holds, then escape.

**Hotfix 6 (crash and co-op fixes):** after installing, also extract `QIangIQsBell-0.2.16-hotfix6.zip` into `mods` and overwrite. It replaces three scripts and includes everything from hotfixes 1 to 5: Havoc mutators no longer crash the Bell at start, renegade snipers and trickle hordes no longer crash it mid-mission, players joining someone else's run no longer crash on the breach charge or the Sprayer Ogryn boss, a melee swing at a pickup on the ground no longer crashes, enemies start once players leave the start building, and the breach charge sits at chest height facing the players (height and turn are in the mod options).

**Low VRAM?** The `lite` folder has an overlay with 512 px textures and simplified meshes, for graphics cards that run out of memory.
