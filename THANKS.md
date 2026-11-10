# Thanks

Vortex for Linux gets better because people report what breaks, send test files
and try the fixes. In order of appearance:

- **lrn09** found that the AppImage launcher blocked the native FOMOD installer (#3)
- **ctomadao** reported the Cyberpunk 2077 install that vanished from staging (#4)
  and fixed Vortex's own data being redirected into the Proton prefix (#5)
- **MJ-asa** asked for the older Vortex versions that became `recipes/` (#10),
  reported the Gamebryo extensions failing on 2.6.2 (#12), supplied the archives
  that pinned down the backslash bug (#16), found the mixed-case folder problem
  (#20) and the 2.6.2 build failures (#24)
- **bmgolley** reported UE4 config deployment failing in Local AppData (#11)
- **gokacinlar** suggested AppImage update metadata for Gear Lever (#13)
- **CaptSilver** fixed extensions behind a symlinked home and the casing of
  declared game paths (#14, #15)
- **lyssieth** reported mods with backslashes in their archives (#16)
- **sevencard** reported nxm:// links not working from the AppImage (#18)
- **pancakedevourer** reported the plain Wine prefix problem (#22)
- **gsebos** reported `plugins.txt` landing in the Linux home instead of the
  Proton prefix (#31)
- **catsgomoo** showed that Steam can keep a game's Proton prefix on another
  drive than the game, and shared the launch options for starting Vortex from
  Steam (#22)

Found something? [Open an issue](https://github.com/Arkazzae/VortexLinux/issues/new).
