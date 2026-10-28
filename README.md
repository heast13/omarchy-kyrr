# kyrr for Omarchy

[kyrr](https://github.com/heast13/kyrr) in the bar of [Omarchy](https://omarchy.org) 4:
local noise suppression, dictation and voice memos, free and offline.

kyrr comes in three versions, all the same app:

- **Windows:** the [installer](https://github.com/heast13/kyrr/releases/latest/download/kyrr-setup.exe).
- **Linux:** the AppImage for other desktops (beta), see [kyrr's install notes](https://github.com/heast13/kyrr#install-on-linux).
- **Omarchy:** this plugin. It installs the Linux AppImage for you.

More about kyrr in general: [github.com/heast13/kyrr](https://github.com/heast13/kyrr).

- **Icon.** The waveform lights up in your theme's accent while kyrr listens
  or writes, and in red while it records a voice memo. Dimmed: kyrr is not
  running.
- **Menu** (click): all of kyrr. Its status line and notes, the four
  switches (isolate your voice, improve voice, dictation, voice memo) with a
  page of settings each, the recordings with their texts, Setup (language,
  microphone, performance, check, updates) and the first-run setup. Walked
  with the keyboard like Omarchy's own menus: arrows or hjkl move, ← → change
  a choice, → opens a page, Enter takes, Esc goes back, x deletes a
  recording (twice). On a recording, Enter or a click opens it and Space or
  its ▶ plays it.
- **Local AI** (kyrr 0.8.0, experimental): Setup > Experimental AI features
  adds a Local AI row to the menu. Its page sets your language model
  (address, model, key, a test), what it does to each dictation (fix
  mishearings, reword, professional) and the language it translates into.
  A switch lets fixing also correct the word order, by rearranging words
  only. The instruction the model gets for each task can be read there,
  changed and saved, or set back to kyrr's. The same rework and translation
  work on a recording's text, with "Restore original"; once reworked, the recording's
  page can show the text beside the one before (View: Text | Compare; red is
  what changed, green what is worded anew). Setup > Own dictation model
  sends dictation to a speech server of your own.
- **Middle click:** start or stop dictating.
- **Not installed yet?** The menu offers "Install kyrr". It downloads the
  newest kyrr and its checksum from GitHub in a terminal, so you see every
  step, checks it and starts it. kyrr is one file, `~/.local/bin/kyrr`
  (about 50 MB, plus the speech model it downloads in its setup). A new kyrr
  version shows an "Install update" row; one click updates kyrr, this plugin
  (`omarchy plugin update`) and reloads the bar (`omarchy-restart-shell`) in
  the same terminal window. An older kyrr gets an "Update kyrr" row the same
  way. (From plugin 1.2.0 on; before that, update the plugin by hand once.)
- **A new plugin on its own.** When kyrr's "check for updates automatically"
  is on, the menu asks GitHub (the plugin's `manifest.json`, at most every six
  hours) whether this plugin has a newer version, and Setup > Check for
  updates asks right away. If so, the menu offers "Update plugin": one click
  loads it, reloads the bar and leaves kyrr as it is. (From plugin 1.4.0 on.)

On Omarchy with this widget kyrr has no window and no tray icon. The widget
starts kyrr; to switch kyrr off, disable the plugin in Omarchy's menu
(Setup > Plugins), and kyrr ends with it. The dictation pill at the bottom of
the screen stays. kyrr also joins Omarchy's dictation (Setup > Defaults >
Dictation, Omarchy 4.5 and newer) and takes your theme's colours and font.

## Requirements

- Omarchy 4.0 or newer (joining Omarchy's dictation needs 4.5).
- kyrr itself, which the menu installs: an AppImage, so it needs FUSE
  (`fuse3`, usually there through Nautilus), PipeWire, glibc 2.39 and, for the
  noise filter, a processor with AVX2.
- `curl` and `socat`, both part of Omarchy.

## Install

```sh
omarchy plugin add https://github.com/heast13/omarchy-kyrr.git --enable
```

Or in the Omarchy menu: Setup > Plugins > Add. Then click the kyrr icon in
the bar.

## What kyrr changes on your system

The widget writes nothing but `$XDG_RUNTIME_DIR/kyrr-widget` and, for what
you type into a text, files beside kyrr's state (see "State"). Its only
network call is the look at its own version on GitHub (see above). kyrr, once
installed, adds:

- `~/.local/bin/kyrr`, and on Omarchy 4.5 and newer the scripts
  `~/.local/bin/omarchy-dictation-kyrr` and
  `~/.local/bin/omarchy-install-dictation-kyrr`, so it shows up in Setup >
  Defaults > Dictation. It picks itself there only when no dictation program
  is chosen or the chosen one is not installed.
- A marked block (`>>> kyrr` … `<<< kyrr`) in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` for that menu row, and a
  marked block with its dictation and voice memo keys in Hyprland's
  configuration.
- Its settings in `~/.config/kyrr`, the speech model in `~/.local/share/kyrr`,
  voice memos in `~/Documents/kyrr`, and a microphone called "kyrr" in
  PipeWire.

It never writes over a file of yours: its scripts carry a mark, and its
blocks are replaced in place.

## Remove

```sh
omarchy plugin remove io.github.heast13.kyrr
```

That turns kyrr off too. To remove kyrr itself and everything above, see
[Uninstalling](https://github.com/heast13/kyrr/blob/main/docs/install.md#uninstall-on-linux).

## How it works

The widget is QML only:

- While kyrr runs it keeps its whole state as one line of JSON in
  `$XDG_RUNTIME_DIR/kyrr/state` and deletes the file when it quits.
- The menu changes something by writing one line to kyrr's socket,
  `$XDG_RUNTIME_DIR/kyrr.sock`, with `socat` (part of Omarchy). The line goes
  in through `socat`'s standard input, never its arguments, so memo names,
  titles and search text do not show in the process list. kyrr answers by
  rewriting the state file.
- Every 10 seconds the widget renews `$XDG_RUNTIME_DIR/kyrr-widget`. kyrr
  quits once that file is older than 30 seconds.

Needs a kyrr newer than 0.6.2, and 0.8.0 or newer for Local AI. With an older
kyrr the menu simply has no Local AI and no own dictation model.

### State

`v` (2), `pid` (kyrr's process id), `mode` (`idle`, `listening`, `writing`, `recording`), `lang`
(`de`, `en`: the menu's language), `version`, `line` (the status line),
`note` and `noteGood`, `alert` (4: the microphone is muted), `overloadNote`
(`""`, `switched`, `pauses`), `oldCpu`, `levels` (`active`, `before`,
`after`: the meters, 0 to 1), `pulse` (`working`, `waiting` or `""`: the
little wave after the line), `setupDone`, `setupStep` (1 to 3), `news` (what
this version brings), `probe` (`idle`, `recording`, `playing`), `hasProbe`,
`probeError`, `listen`, and:

- `filter`: `on`, `strength` (0 to 2), `attached` (on a microphone), `setup` (`""`, `settingUp`, `error`,
  `unsupported`), `error`, `state` (`running`, `checking`, `off`,
  `passthrough`, `notAttached`, `notInstalled`, `settingUp`, `error`,
  `detached`, `unsupported`), `mic`, `moveTo` and `moveUnplugged` (the
  microphone the system switched to)
- `voice`: `on`, `tone` (`neutral`, `warm`, `clear`, `bright`, `custom`),
  `body`, `presence`, `air` (dB, −6 to 6), `comp`, `ess` (0 to 3), `rumble`,
  `rumbleHz`, `pops`, `distance`, `autoLevel`, `levelDb` (null while off),
  `isDefault`
- `dictation`: `on`, `ready`, `key`, `hold`, `note`, `state` (`off`,
  `noModel`, `downloading`, `loading`, `ready`, `recording`, `transcribing`,
  `error`), `message`, `keyCustom`, `keyFixed`, `keyUnbound`, `keyButton`
- `memos`: `on`, `recording`, `elapsed`, `key`, `keyCustom`, `keyNote`,
  `hold`, `canHold`, `autoText`, `canWrite`, `folder`, `message`, `query`,
  `count` (all, found or not), `playTime` and `playFraction` (the one
  playing), `list` (newest first, as the search finds them: `id` = file
  name, `title`, `when`, `length`, `pending`, `text` =
  `none`/`writing`/`ready`/`failed`, `waiting`, `progress`, `left`, `isNew`,
  `playing`), `sheet` (null, or the recording opened with `memo show <id>`:
  `id`, `title`, `when`, `stamps` (0 off, 1 position, 2 time of day),
  `view` (0 the text, 1 the text beside the one before the rework; absent in
  kyrr 0.8.0), `saved`, `copied`, `empty`, `here` (where "Play from here" starts),
  `rework`: the language model on this text, `ready` (Local AI is set
  up), `busy`, `progress` (0 to 1), `note`, `action` (0 off, 1 fix, 2
  reword, 3 professional), `target` (language code, `""` for none),
  `original` (an earlier text is kept and can be brought back); absent in
  kyrr before 0.8.0)
- `general`: `language` (`de`, `en`, `multi`), `effort` (`lean`, `best`,
  `custom`), `liveText`, `overload`, `updateCheck`
- `mic`: `name` and `current` (name and list `id` of the one in use, -1 for
  none), `index` (the one picked in the first-run setup), `list` (`id`,
  `name`)
- `model`: `state` (`off`, `none`, `downloading`, `loading`, `ready`,
  `error`), `progress`, `size`
- `update`: `state` (`idle`, `checking`, `latest`, `available`, `failed`,
  `downloading`), `phase` (`""`, `installing`, `downloadFailed`), `version`,
  `progress`, `news`, `installable`, `dismissed`
- `ai` (kyrr 0.8.0; absent before, then the menu has no Local AI): the
  language model and the speech server of your own. `features` (Setup >
  Experimental AI features: the menu shows Local AI only with it on), `on`
  (Local AI), `ready` (address and model are set), `rework` (0 off, 1 fix
  mishearings, 2 reword, 3 professional), `translate` (language code, `""`
  for none; the 17 languages `en de fr es it nl pt pl cs sk sv da no fi hu ro
  hr`), `url`, `model`, `models` (what the server offers, at most 30),
  `keySet` (whether a key is saved; the key itself is never in the state),
  `busy` (asking the server), `note` (how the last test went), `found` (name
  of a server found on this computer, `""` for none), `prompt` (`index` 0 to 3:
  fix, reword, professional, translate; `own`: that instruction is yours, not
  kyrr's; `edit`: the wording can be read and changed through the files below,
  absent in kyrr 0.8.0), and `asr`: the speech server, with `on` and the same `url`,
  `model`, `models`, `keySet`, `busy`, `note`, `found`

Longer texts do not travel in the state but in files beside it, in
`$XDG_RUNTIME_DIR/kyrr/`. The first line of each names the recording (its
file name) or task (0 to 3) it belongs to, so a text never lands on another
one.

- `sheet`: the text of the recording in `sheet`, as kyrr's text view shows it
  (with the chosen stamps). What the menu types into it goes to `edit`; kyrr
  takes that file with `memo edit` and before `memo copy|here|stamps|opentext`.
- `compare`: while `sheet.view` is 1 (`memo view 1`), the text before and
  after the language model: a JSON list of `{before, after}`, one entry per
  paragraph, in rich text (`<font color>` marks what changed).
- `prompt`: the instruction the language model gets for the task in
  `ai.prompt.index`. What the menu wants it to say goes to `promptedit`; kyrr
  takes that file with `set ai.promptSave`.

### Commands

- `toggle filter|voice|dictation|memos|voice.rumble|voice.pops|voice.distance|voice.autoLevel|memos.autoText|general.liveText|general.overload|general.updateCheck|listen|ai.features|ai.on`
- `set filter.strength <0-2>`, `set voice.tone <name>`,
  `set voice.body|presence|air <dB>`, `set voice.comp|ess <0-3>`,
  `set voice.reset`, `set dictation.key|memos.key <keysym name>` (F1 to
  F24, Pause, Scroll_Lock, Control_R, Menu), `set dictation.keyReset|memos.keyReset`,
  `set dictation.hold|memos.hold true|false`,
  `set general.language de|en|multi`, `set general.effort lean|best`
- Local AI: `set ai.rework <0-3>`, `set ai.translate <code>|off`,
  `set ai.prompt <0-3>`, `set ai.promptSave` (takes the wording in the file
  `promptedit`), `set ai.promptReset` (the shown instruction back to
  kyrr's), and for the language model `set ai.url|ai.model|ai.key <text>`
  (address and key are saved and tried at once), `set ai.connect` (connect
  and test), `set ai.take` (use the server found on this computer),
  `set ai.look language|speech` (look for one). The speech server has
  `set asr.on true|false`, `set asr.url|asr.model|asr.key <text>`,
  `set asr.connect` and `set asr.take`. On the open recording:
  `set memos.reworkAction <0-3>`, `set memos.reworkTarget <code>|off`, then
  `memo rework` (apply), `memo stoprework`, `memo restore` (the original
  back) and `memo view 0|1` (the text, or the text beside the one before). The key goes through the socket like any other line, never through
  an argument.
- `mic <id>` (first-run setup: picks it; else: moves the filter to it),
  `mic unmute|repair|default`
- `memo start|stop|folder|seen|edit|opentext`,
  `memo play|text|cancel|reveal|delete <id>`, `memo show [<id>]`,
  `memo rename ["<id>","<title>"]`, `memo search [<words>]`,
  `memo copy <from> <to>` (UTF-8 byte offsets in the text, both 0 for all),
  `memo cursor|here <offset>`, `memo stamps <0-2>`
- `model download|cancel|retry`, `test start|before|after|delete`,
  `update check|install|dismiss|page`, `setup next|skip|done|keybutton|overloadSeen`,
  `open feedback|licenses`
- Also: `dictate`, `menu-open` (every few seconds while the menu is open:
  kyrr keeps its status line, notes and meters going), `menu-closed`

## Development

CI checks that the plugin loads on Omarchy, that every page builds from every
state kyrr writes, that the update flow works, and that the menu and kyrr
agree on the socket's commands. Run the checks on your own machine as
`tests/README.md` says.

## License

MIT, see [LICENSE](LICENSE).
