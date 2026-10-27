# QIangIQsBell low-VRAM version (for GPUs that run out of video memory)

Same full-size map, same collision and gameplay, much lighter on VRAM:
- textures 512 px instead of 1024 px (218 MB down to 56 MB)
- vertices merged and render meshes simplified within 3 cm (15.5M down to 6.7M triangles; units 1029 MB down to 566 MB)

It is an overlay for an existing QIangIQsBell 0.2.16 install, and includes hotfix 6.

**Get it:** download the 5 `QIangIQsBell-lite.zip.00x` files and `JOIN_BELL_LITE.bat` into one folder. Open `QIangIQsBell-lite.zip.001` with 7-Zip or WinRAR, or double-click `JOIN_BELL_LITE.bat` to make `QIangIQsBell-lite.zip`.

SHA-256 of the joined zip: `3320fdcac86f4bad0585f61b1857970ec8e2cd84c3bcc89d952f83b0096830fd`

**Install**
1. Install the normal QIangIQsBell first (see the folder above).
2. Extract `QIangIQsBell-lite.zip` into `Warhammer 40,000 DARKTIDE/mods` and overwrite.
3. With the game closed, run `CUSTOM_ASSETS_PATCH.bat` in the game folder.

Co-op works with players on the normal version: only how the map looks differs, not where you can walk. To go back, reinstall the normal version and run the patcher again.
