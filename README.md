# kyrr for Omarchy

[kyrr](https://github.com/heast13/kyrr) in the bar of [Omarchy](https://omarchy.org) 4:
local noise suppression and dictation, free and offline.

- **Icon.** The waveform lights up in your theme's accent while kyrr listens
  or writes, and in red while it records a voice memo. Dimmed: kyrr is not
  running.
- **Menu** (click): the switches of kyrr's main page (isolate your voice,
  improve voice, dictation, voice memo), each with its gear for its
  settings; stop a running recording, open recordings, install an update,
  Setup.
- **Middle click:** start or stop dictating. **Right click:** quit kyrr.
- **Not installed yet?** The menu offers "Install kyrr": it runs the install
  command from kyrr's website in a terminal, so you see every step. kyrr is
  one file, `~/.local/bin/kyrr` (about 50 MB, plus the speech model you pick
  in its setup).

While the widget is in the bar, kyrr leaves out its tray icon and the
window's buttons to hide or quit; the widget does both. kyrr also joins
Omarchy's dictation (Setup > Defaults > Dictation, Omarchy 4.5 and newer) and
takes your theme's colours and font.

## Install

```sh
omarchy plugin add https://github.com/heast13/omarchy-kyrr.git --enable
```

Or in the Omarchy menu: Setup > Plugins > Add. Remove the widget with
`omarchy plugin remove heast13.kyrr`. To remove kyrr itself, see
[Uninstalling](https://github.com/heast13/kyrr/blob/main/docs/install.md).

## How it works

The widget is QML only and starts no program of its own:

- While kyrr runs it keeps one line of JSON in `$XDG_RUNTIME_DIR/kyrr/state`
  (what it does, its switches, its process id) and deletes the file when it
  quits. The widget reads it and checks that the process is still kyrr.
- A switch in the menu writes one word to kyrr's socket,
  `$XDG_RUNTIME_DIR/kyrr.sock`, with `socat` (part of Omarchy).
- Every 10 seconds the widget renews `$XDG_RUNTIME_DIR/kyrr-widget`, so kyrr
  knows the widget is in the bar.

Needs a kyrr newer than 0.6.2; older ones do not tell the widget what they
do yet.

## License

MIT, see [LICENSE](LICENSE).
