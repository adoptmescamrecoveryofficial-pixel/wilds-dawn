# Wild's Dawn 1.0

A customized native Breath of the Wild recompilation launcher, with cel-shaded forest artwork, an animated sword logo, gentle foliage movement, Hylia Serif menus and optional menu music.

Open **Wild's Dawn.exe**, then choose **Play**. Settings and Game Files are available from the launcher. In Game Files, choose Import from: NSP packages. Select your own full Switch base-game NSP, and the matching 1.8.2 or 1.9.0 update NSP; then choose Extract and set up. The bundled extractor merges the update and continues setup automatically. Already extracted exefs/romfs folders are also supported. Game files are not included.

Settings panels, tabs and dropdowns use short eased entrances. Menu highlights follow mouse or keyboard/controller input, and main-menu labels grow gently on hover.

Music files in the music folder are shuffled automatically. Use Music on/off, Next song and the volume slider at the bottom of the launcher. The music stops when the game begins.

Press F2 to open or close in-game settings. Escape or the close button also closes settings. The mouse becomes visible and free while settings are open, and camera capture returns on closing when mouse-camera control is enabled. Settings and saves remain local. The --play command-line option skips the launcher when explicitly requested.

Maxed-out mode is in Settings > Prelaunch > Save enhancements. It loads existing Switch BOTW 1.8/1.9 saves with 30 hearts, full stamina, max currencies and inventory space, upgraded equipment and full quest/map completion. Enabling it first makes an independent copy of the save folder in save-backups. It applies on the next save load. Turning it off stops future overrides; changes the game has saved can remain, so use the backup to return to the original progress. It is off by default in the distributable build.

Build on Windows with MSYS2 UCRT64 and the dependencies described in docs/BUILD-windows.md:

    make -j8 B=build/win-release DEPS=$PWD/build/deps-win RELEASE=1 all

See LICENSE and CREDITS.txt for upstream authorship and third-party license information. See ART-NOTES.txt in the packaged build for artwork details.


For NSP setup, select the base-game NSP and a supported update NSP.

Open **F2 → Cheats** for infinite air jumps, fly/hover, auto-heal and one-hit enemies. Options start off each launch. See CHEATS.txt for movement controls.
