# Tests

CI (`.github/workflows/ci.yml`) runs everything below. Nothing needs npm.

kyrr and the menu share `packaging/omarchy/contract.json` in
[heast13/kyrr](https://github.com/heast13/kyrr): the lines kyrr's socket takes,
how each control of kyrr's window is done in the menu, and a sample of the state
file. The tests read it from the ref in `KYRR_REF` (`main` unless set; CI sets
it in the workflow). `KYRR_CONTRACT=/path/to/contract.json` reads a local copy
instead.

## Pages and texts (`node --test tests/*.test.mjs`)

Plain node, no dependencies. `Texts.js` and `Views.js` are loaded the way QML
does (without the `.pragma`) into a `vm` context.

- `pages.test.mjs` builds every page `Views.js` knows (and every recording's
  text page) from every state in `variants.mjs`, in German and English. The
  states start from the contract's sample: first-run setup steps, the filter
  not attached, detached or not installed, dictation without a model, with an
  error or an unbound key, memos recording or off or empty, no `ai` at all
  (kyrr 0.7), Local AI on and not ready, the own speech server, updates in each
  phase, notes. Each build must not throw (Panel.qml turns a throw into "kyrr is
  too old", so a page that needs `ai` must fall back to the main page without
  it), every `t(key)` must exist in both languages, no text may contain
  `undefined`, `null`, `NaN` or a bare `{}`, every row must be a kind Panel.qml
  draws and do something (a `cmd`, a `page`, or a handler in Panel.qml), every
  `cmd` and `play` must be a command of the contract, every `page` a row opens
  must be one `Views.js` builds, and a choice's value must be one of its options.
- The same file reads the `send(...)` lines in `Panel.qml` and checks them
  against the contract, and checks the contract's `parity` list: every window
  control with a `plugin` entry must have its command sent somewhere in the
  menu. A control that is knowingly missing goes into `known-gaps.json` with a
  reason; the test fails when such an entry is not needed any more.
- `texts.test.mjs`: `de` and `en` have the same keys and the same `{}` count, and
  every key written out in `Panel.qml` and `Views.js` exists.
- `node tests/warnings.mjs` prints the contract's `gap` controls (and the
  acknowledged ones) as warnings. They never fail.

## Update flow (`bash tests/update-flow.test.sh`)

Runs `update.sh` with stub `curl`, `omarchy`, `git`, `setsid` and `fusermount3` first
on `PATH` and a temporary `HOME`, and checks the calls: an install downloads,
checks and installs kyrr only; an update also updates the plugin and restarts
the shell; a plugin that cannot be updated is removed and cloned again; a bad
checksum or a failed download leaves kyrr alone and does nothing else.

## Load (`bash tests/load/run.sh <omarchy checkout> 1366x768,1920x1080 <out folder>`)

Needs Arch with `quickshell`, `sway`, `grim`, `socat`, `jq`, `nodejs` and a Nerd
font; CI does it in an `archlinux` container, on the oldest supported Omarchy
(v4.0.6) and the newest stable tag.

It builds a Quickshell config out of Omarchy's own `shell/Commons` and `shell/Ui`
and `tests/load/shell.qml`, which puts a bar on a headless sway and loads this
plugin's `Panel.qml` into it the way Omarchy's `Bar.qml` does (a `PluginBarApi`
as `bar`, the other properties injected afterwards). A fake kyrr writes the
states of `tests/load/states.mjs` into `$XDG_RUNTIME_DIR/kyrr/state` and logs
what reaches its socket. The menu is opened over Quickshell's IPC
(`io.github.heast13.kyrr open`), and for each screen size each page of each
state is measured and photographed (`grim`; the screenshots are the artifact of
the run). `judge.mjs` fails the job on:

- a QML error in Quickshell's log that names the plugin's files or Omarchy's
  `Commons` or `Ui` (`is not a type`, `ReferenceError`, `TypeError`, `Unable to
  assign`, `Cannot assign to non-existent property`, binding loops, ...);
- the widget not loading, or the menu not opening or not seeing the fake kyrr;
- a menu card that is bigger than the screen or leaves it;
- a page that scrolls on a screen 1080 px high or more (smaller screens may
  scroll; the summary lists which pages do);
- a line reaching the socket that is no command of the contract;
- the install or update button not running this plugin's `update.sh`, or the
  menu not offering to install a kyrr that is not there.

## Limits of the load test

- It is not the whole Omarchy shell: no Hyprland (a stub `hyprctl` answers the
  corner radius and gaps), no `shell.json`, no plugin registry, no other widgets,
  and the bar is a plain `PanelWindow`. The widget's component, its `bar`
  object and the popup (`KeyboardPanel`, a layer-shell window) are the real
  ones.
- Rendering is Qt's software backend on sway's headless output, so
  screenshots show layout, not the GPU's output. Keys are not pressed: pages
  are reached over IPC (`tests/load/shell.qml`, the test only), and the
  keyboard code runs only as far as page changes and the install button go.
- The fake kyrr only writes down what it is sent. Whether kyrr understands a
  line is what the contract is for.
- The font is JetBrains Mono Nerd Font at Omarchy's default size. A user who
  makes the text bigger may see pages scroll that do not here.
