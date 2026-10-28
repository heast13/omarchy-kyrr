import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Texts.js" as Texts
import "Views.js" as Views

// kyrr in Omarchy's bar. On Omarchy kyrr has no window and no tray icon:
// this menu is all of it, the switches, every setting and the first-run
// setup, walked with the keyboard like Omarchy's own menus. kyrr itself
// runs in the background; the plugin starts it, and turning the plugin off
// ends it.
//
// kyrr keeps its whole state as one line of JSON in
// $XDG_RUNTIME_DIR/kyrr/state (README.md, "State"). The menu changes
// something by writing one line to kyrr's socket, $XDG_RUNTIME_DIR/kyrr.sock
// ("set filter.strength 2", "toggle voice", …); kyrr answers by rewriting
// the file. The widget renews $XDG_RUNTIME_DIR/kyrr-widget every few
// seconds; kyrr quits once that file goes stale.
Panel {
  id: root
  moduleName: "io.github.heast13.kyrr"
  ipcTarget: "io.github.heast13.kyrr"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDir + "/kyrr.sock"

  // The last state kyrr wrote, and whether it still answers on its socket.
  property var kyrr: null
  property bool alive: false
  // Whether kyrr is installed; unknown until looked.
  property bool installed: true
  // When the plugin last started kyrr, so a kyrr that fails to start is
  // not started again every few seconds.
  property real startedAt: 0
  // The state file's text as last read, so an unchanged file changes nothing.
  property string stateText: ""
  // How many looks in a row kyrr answered without a state this plugin knows.
  property int oddLooks: 0

  readonly property bool running: alive && kyrr !== null && kyrr.v === 2
  // A kyrr that answers but speaks another version of the state: an older
  // kyrr wants an update, a newer one a newer plugin. A minute of looks, so
  // a kyrr still starting up is not taken for an old one.
  readonly property bool mismatch: !running && alive && oddLooks >= 15
  readonly property bool pluginOld: mismatch && kyrr !== null && kyrr.v > 2
  readonly property string mode: running ? String(kyrr.mode || "idle") : ""
  readonly property bool busy: mode === "listening" || mode === "writing" || mode === "recording"
  // Omarchy's own language (Commons.I18n) came after 4.0; the system's
  // until kyrr says which it speaks.
  readonly property string language: running && kyrr.lang ? kyrr.lang : Qt.locale().name
  readonly property bool german: language.indexOf("de") === 0

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The pages walked into, the main page first, and where the cursor stood
  // on each.
  property var stack: ["main"]
  property var cursors: ({})
  readonly property string page: stack[stack.length - 1]
  readonly property var updateRow: ({ kind: "action", id: "install", icon: Views.GLYPH.update, label: t("updateKyrr"), caption: t("updateKyrrHint") })
  readonly property var view: {
    if (running) {
      try {
        return Views.build(page, kyrr, t)
      } catch (e) {
        // A field this plugin wants is missing: kyrr is older than it.
        console.warn("kyrr: " + e)
        return { title: "", rows: [updateRow] }
      }
    }
    if (pluginOld) return { title: "", rows: [{ kind: "info", label: t("pluginOld") }] }
    if (mismatch) return { title: "", rows: [updateRow] }
    return { title: "", rows: [installed
      ? { kind: "info", label: t("starting") }
      : { kind: "action", id: "install", icon: Views.GLYPH.install, label: t("install"), caption: t("installHint") }] }
  }
  readonly property var rows: view.rows
  property int cursor: -1
  property bool cursorActive: false
  // A key row listening for the next key press, by row id.
  property string capturing: ""
  // A recording asked to be deleted once already, by row id.
  property string deleting: ""
  // Which button of a row of buttons the cursor is on.
  property int pick: 0
  // Typing into a line or the text of a recording: keys go there.
  property bool typing: false
  // The text of the recording on show, as kyrr's text view has it, and the
  // field showing it (one at a time).
  property string sheetText: ""
  property string sheetId: ""
  property var editorItem: null

  function t(key, value) {
    return Texts.text(root.german, key, value)
  }

  function glyph(code) {
    return String.fromCodePoint(code)
  }

  // One line to the running kyrr. The line goes in through the helper's
  // standard input, never through its arguments: memo names, titles and
  // search text must not show in the process list.
  function send(line) {
    sender.createObject(root, { line: line })
  }

  Component {
    id: sender
    Process {
      property string line: ""
      command: ["socat", "-", "UNIX-CONNECT:" + root.socketPath]
      stdinEnabled: true
      running: true
      onStarted: {
        write(line + "\n")
        stdinEnabled = false
      }
      onExited: destroy()
    }
  }

  function command(row, value) {
    if (!row.cmd) return
    // A function, so a "$" in the value is no pattern of replace().
    root.send(value === undefined ? row.cmd : row.cmd.replace("{}", function() { return String(value) }))
  }

  // kyrr sits in ~/.local/bin, which the shell's own PATH may leave out.
  readonly property string findKyrr: "k=$(command -v kyrr || echo \"$HOME/.local/bin/kyrr\"); "
  readonly property string startCommand: findKyrr + "test -x \"$k\" && exec \"$k\" --background"
  // Installs or updates kyrr in Omarchy's floating terminal, so every step
  // shows: the newest release and its checksum from GitHub, checked before
  // anything runs. kyrr then takes over from a running one in the background,
  // and this menu runs its first-run setup.
  readonly property string releases: "https://github.com/heast13/kyrr/releases/latest/download/"
  // The steps run in a subshell, so a failed one still ends in Omarchy's
  // done message with its code, and the download folder always goes.
  readonly property string installSteps: "d=$(mktemp -d); ( set -e; cd \"$d\"; "
    + "curl -fLO " + releases + "kyrr-x86_64.AppImage; "
    + "curl -fLO " + releases + "kyrr-x86_64.AppImage.sha256; "
    + "sha256sum -c kyrr-x86_64.AppImage.sha256; "
    + "mkdir -p ~/.local/bin; install -m 755 kyrr-x86_64.AppImage ~/.local/bin/kyrr.new; "
    + "mv -f ~/.local/bin/kyrr.new ~/.local/bin/kyrr; "
    + "command -v fusermount3 >/dev/null || command -v fusermount >/dev/null || "
    + "echo 'kyrr needs FUSE (package fuse3) to start.'; "
    + "setsid -f ~/.local/bin/kyrr --replace --background >/dev/null 2>&1 ); "
    + "r=$?; rm -rf \"$d\"; "
  readonly property string installCommand: installSteps + "(exit $r)"

  // An update of an installed kyrr brings this menu along, in the same
  // window: the plugin is updated too (added again where updating does not
  // work) and the shell restarts to load it, detached and after two seconds
  // so the window can still say it is done. A first install needs neither.
  readonly property string pluginId: "io.github.heast13.kyrr"
  readonly property string pluginUrl: "https://github.com/heast13/omarchy-kyrr.git"
  readonly property string updateCommand: installSteps
    + "if [ $r -eq 0 ]; then "
    + "omarchy plugin update " + pluginId + " --yes || omarchy plugin add " + pluginUrl + " --enable; "
    + "setsid -f sh -c 'sleep 2; omarchy-restart-shell' >/dev/null 2>&1; fi; (exit $r)"

  function startKyrr() {
    if (!root.bar || root.running || !root.installed) return
    if (Date.now() - root.startedAt < 60000) return
    root.startedAt = Date.now()
    root.bar.run(root.startCommand)
  }

  // ------------------------------------------------------------ pages

  function openPage(name) {
    root.flushEdit()
    var saved = Object.assign({}, root.cursors)
    saved[root.page] = root.cursor
    root.cursors = saved
    root.stack = root.stack.concat([name])
    root.deleting = ""
    root.capturing = ""
    root.cursor = root.firstSelectable()
  }

  function back() {
    if (root.stack.length <= 1) return false
    root.flushEdit()
    root.stack = root.stack.slice(0, root.stack.length - 1)
    root.deleting = ""
    root.capturing = ""
    var at = root.cursors[root.page]
    root.cursor = at !== undefined ? at : root.firstSelectable()
    return true
  }

  function firstSelectable() {
    for (var i = 0; i < root.rows.length; i++) if (Views.selectable(root.rows[i])) return i
    return -1
  }

  function enabled(row) {
    return row.enabled !== false
  }

  // ------------------------------------------------------------ keyboard

  function moveCursor(dy) {
    if (!root.cursorActive || root.cursor < 0) {
      root.cursorActive = true
      if (root.cursor < 0) root.cursor = root.firstSelectable()
      return
    }
    var i = root.cursor
    do { i += dy } while (i >= 0 && i < root.rows.length && !Views.selectable(root.rows[i]))
    if (i >= 0 && i < root.rows.length) root.cursor = i
    root.deleting = ""
    root.pick = 0
  }

  // ← and →: a choice or slider moves, anything with a page opens it, and
  // otherwise ← is one page back.
  function sideways(dx) {
    var row = root.rows[root.cursor]
    if (root.cursorActive && row && root.enabled(row)) {
      if (row.kind === "choice") return root.step(row, dx)
      if (row.kind === "slider") return root.command(row, Math.max(row.min, Math.min(row.max, row.value + dx * row.step)))
      if (row.kind === "buttons" && root.pick + dx >= 0 && root.pick + dx < row.buttons.length) {
        root.pick += dx
        root.deleting = ""
        return
      }
      if (dx > 0 && row.page) return root.openPage(row.page)
    }
    if (dx < 0) root.back()
  }

  function step(row, dx) {
    var at = 0
    for (var i = 0; i < row.options.length; i++) if (row.options[i].value === row.value) at = i
    var next = Math.max(0, Math.min(row.options.length - 1, at + dx))
    if (next !== at) root.command(row, row.options[next].value)
  }

  function activate(index) {
    var row = root.rows[index]
    if (!row || !Views.selectable(row)) return
    root.cursor = index
    if (row.id === "install") {
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation "
        + Util.shellQuote(root.installed ? root.updateCommand : root.installCommand))
      root.close()
      return
    }
    if (!root.enabled(row)) return
    switch (row.kind) {
    case "buttons":
      return root.press(row, root.pick)
    case "edit":
    case "editor":
      var item = rowRepeater.itemAt(index)
      if (item && item.item) item.item.startTyping()
      return
    case "choice":
      var at = 0
      for (var i = 0; i < row.options.length; i++) if (row.options[i].value === row.value) at = i
      root.command(row, row.options[(at + 1) % row.options.length].value)
      return
    case "key":
      // A second click on a listening key row stops listening.
      root.capturing = root.capturing === row.id ? "" : row.id
      if (root.capturing === "") keyCatcher.forceActiveFocus()
      return
    case "slider":
      return
    case "memo":
      return root.openPage(row.page)
    case "action":
      if (row.page) root.openPage(row.page)
      else root.command(row)
      return
    default:
      root.command(row)
    }
  }

  // One button of a row of buttons, by click or Enter.
  function press(row, at) {
    var b = row.buttons[at]
    if (!b) return
    root.pick = at
    if (b.id === "deleteMemo") return root.remove()
    root.deleting = ""
    if (b.enabled === false) return
    if (b.id === "copy") return root.copySheet()
    if (b.id === "here") return root.playHere()
    // What was typed into the text goes first, so the language model and
    // the original see the text as it is on the screen.
    if (b.id === "rework" || b.id === "restore") root.flushEdit()
    root.command(b)
  }

  // A recording: Space plays it, as its ▶ does for the mouse.
  function play() {
    var row = root.rows[root.cursor]
    if (row && row.kind === "memo") root.send(row.play)
  }

  // x, or a recording's bin: once asks, twice deletes. On a recording's own
  // page the way back follows.
  function remove() {
    var row = root.rows[root.cursor]
    if (!row || (row.kind !== "memo" && !(row.kind === "buttons" && row.memo))) return
    if (row.kind === "buttons") {
      for (var i = 0; i < row.buttons.length; i++) if (row.buttons[i].id === "deleteMemo") root.pick = i
    }
    if (root.deleting === row.id) {
      root.send("memo delete " + row.memo.id)
      root.deleting = ""
      if (row.kind === "buttons") root.back()
    } else {
      root.deleting = row.id
    }
  }

  // A line typed into: a recording's new title, or what to search for.
  function submitEdit(row, text) {
    if (row.rename) {
      if (text.trim() === "" || text === row.value) return
      root.flushEdit()
      root.send("memo rename " + JSON.stringify([row.rename, text.trim()]))
    } else if (row.cmd) {
      root.send(row.cmd.replace("{}", function() { return text }))
    }
  }

  // UTF-8 bytes in front of a place in the text: kyrr counts in bytes.
  function bytes(text) {
    var n = 0
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i)
      if (c < 0x80) n += 1
      else if (c < 0x800) n += 2
      else if (c >= 0xD800 && c < 0xDC00) { n += 4; i++ }
      else n += 3
    }
    return n
  }

  // What was typed into the recording's text goes to kyrr through a file
  // (a long text does not fit on a command line); kyrr takes it before each
  // of the commands below, so they see the text as it is on the screen.
  function flushEdit() {
    var e = root.editorItem
    if (!e || !e.dirty || editFile.path === "" || e.memo === "") return
    editFile.setText(e.memo + "\n" + e.text)
    e.sent = e.text
    e.dirty = false
    root.send("memo edit")
  }

  function copySheet() {
    var e = root.editorItem
    root.flushEdit()
    if (!e) return root.send("memo copy 0 0")
    root.send("memo copy " + root.bytes(e.text.slice(0, e.selectionStart)) + " " + root.bytes(e.text.slice(0, e.selectionEnd)))
  }

  function playHere() {
    var e = root.editorItem
    root.flushEdit()
    root.send("memo here " + (e ? root.bytes(e.text.slice(0, e.cursorPosition)) : 0))
  }

  function closeRequested() {
    if (root.capturing !== "") { root.capturing = ""; return }
    if (!root.back()) root.close()
  }

  // The names kyrr knows keys by (X keysym names), for the keys it offers.
  function keyName(event) {
    if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) return "F" + (event.key - Qt.Key_F1 + 1)
    if (event.key === Qt.Key_Pause) return "Pause"
    if (event.key === Qt.Key_ScrollLock) return "Scroll_Lock"
    if (event.key === Qt.Key_Menu) return "Menu"
    if (event.key === Qt.Key_Control && event.nativeScanCode === 105) return "Control_R"
    return ""
  }

  function pointAt(index) {
    if (root.capturing !== "") return
    root.cursorActive = true
    if (root.cursor !== index) {
      root.pick = 0
      root.deleting = ""
    }
    root.cursor = index
  }

  function statusText() {
    if (!root.installed && !root.running) return root.t("notInstalled")
    if (!root.running) return root.t("starting")
    if (root.mode === "listening") return root.t("listening")
    if (root.mode === "writing") return root.t("writing")
    if (root.mode === "recording") return root.t("recording")
    return root.kyrr.dictation.on && root.kyrr.dictation.ready ? root.t("readyKey", root.kyrr.dictation.key) : root.t("ready")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onRowsChanged: {
    if (root.cursor >= root.rows.length || (root.cursor >= 0 && !Views.selectable(root.rows[root.cursor])))
      root.cursor = root.firstSelectable()
  }
  onCursorChanged: Qt.callLater(root.showCursor)
  // kyrr puts the text of the recording on show into its state, and counts
  // the list as seen once it was open.
  onPageChanged: {
    // The text of the recording shown before is not this one's.
    root.sheetId = ""
    root.sheetText = ""
    if (root.page.indexOf("text:") === 0) Qt.callLater(sheetFile.reload)
    if (!root.running) return
    root.send(root.page.indexOf("text:") === 0 ? "memo show " + root.page.slice(5) : "memo show")
    if (root.page === "recordings") root.send("memo seen")
    // A server's page opened with no address yet: kyrr looks for one on
    // this computer and offers it.
    if (root.page === "ai") root.send("set ai.look language")
    else if (root.page === "asr") root.send("set ai.look speech")
  }
  // While the menu is open kyrr keeps its status line, notes and meters
  // going for it; it hears "menu-open" every few seconds.
  onOpenedChanged: {
    if (root.running) root.send(opened ? "menu-open" : "menu-closed")
    if (opened) openMenu()
    else { root.capturing = ""; root.deleting = "" }
  }

  function openMenu() {
    root.flushEdit()
    if (root.running && root.kyrr.memos && root.kyrr.memos.query) root.send("memo search ")
    root.stack = ["main"]
    root.cursors = ({})
    root.cursorActive = false
    root.cursor = root.firstSelectable()
    stateFile.reload()
    aliveProbe.running = true
    if (!root.running) lookForKyrr.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function showCursor() {
    var item = rowRepeater.itemAt(root.cursor)
    if (!item) return
    var top = item.y
    var bottom = item.y + item.height
    if (top < list.contentY) list.contentY = top
    else if (bottom > list.contentY + list.height) list.contentY = bottom - list.height
  }

  // ------------------------------------------------------------ kyrr

  FileView {
    id: stateFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/kyrr/state" : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      var content = text()
      // The same as last time: every page and row stays as it is.
      if (content === root.stateText) return
      var parsed = null
      try {
        parsed = JSON.parse(content)
      } catch (e) {
        // A read in the middle of kyrr's write: keep what was there.
        return
      }
      root.stateText = content
      root.kyrr = parsed
      // kyrr writes a recording's text before the state that names it; a
      // watch does not see a file that was not there yet.
      if (root.page.indexOf("text:") === 0) sheetFile.reload()
      if (!root.alive) aliveProbe.running = true
    }
    onLoadFailed: {
      root.stateText = ""
      root.kyrr = null
    }
    onFileChanged: reload()
  }

  // A kyrr that crashed leaves its file behind: whether something answers
  // on its socket says if it still runs (and an older kyrr answers without
  // writing the file). "background" is the word kyrr ignores. The shell
  // cannot read /proc.
  Process {
    id: aliveProbe
    command: ["sh", "-c", "printf background | socat - \"UNIX-CONNECT:$1\" 2>/dev/null", "sh", root.socketPath]
    onExited: function(exitCode) {
      root.alive = exitCode === 0
      root.oddLooks = root.alive && !root.running ? root.oddLooks + 1 : 0
    }
  }

  // The text of the recording on show, and what was typed into it.
  FileView {
    id: sheetFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/kyrr/sheet" : ""
    printErrors: false
    watchChanges: true
    // The first line names the recording, the rest is its text.
    onLoaded: {
      var all = text()
      var cut = all.indexOf("\n")
      root.sheetId = cut < 0 ? "" : all.slice(0, cut)
      root.sheetText = cut < 0 ? "" : all.slice(cut + 1)
    }
    onLoadFailed: { root.sheetId = ""; root.sheetText = "" }
    onFileChanged: reload()
  }

  FileView {
    id: editFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/kyrr/edit" : ""
    printErrors: false
    blockWrites: true
  }

  // Tells kyrr that this widget sits in the bar.
  FileView {
    id: widgetFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/kyrr-widget" : ""
    printErrors: false
  }

  Process {
    id: lookForKyrr
    command: ["sh", "-c", "command -v kyrr >/dev/null || test -x \"$HOME/.local/bin/kyrr\""]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.startKyrr()
    }
  }

  // The state file comes and goes with kyrr, which a watch on it does not see.
  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    property int ticks: 0
    onTriggered: {
      stateFile.reload()
      // Looks at kyrr's socket every 4 s while the menu is open or kyrr is
      // starting, else every 30 s (also while kyrr is not installed).
      var often = root.opened || (!root.running && root.installed)
      if (ticks % (often ? 2 : 15) === 0) aliveProbe.running = true
      if (root.opened && root.running && ticks % 2 === 0) root.send("menu-open")
      if (ticks % 5 === 0 && widgetFile.path !== "") widgetFile.setText(Date.now() + "\n")
      if (ticks % 15 === 0 && !root.running && !root.alive) lookForKyrr.running = true
      ticks++
    }
  }

  // ------------------------------------------------------------ the bar

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph(0xF147D)
    active: root.busy
    activeColor: root.mode === "recording" ? root.urgent : Commons.Color.accent
    dimmed: !root.running
    tooltipText: root.opened ? "" : "kyrr: " + root.statusText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && root.running) root.send("dictate")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // A recording's text gets room to be read.
    contentWidth: panel.fittedContentWidth(Style.space(root.page.indexOf("text:") === 0 ? 520 : 360))
    // As tall as the page needs: Omarchy keeps the card on the screen.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(4000))

    // A plain child rather than `content:`, which Omarchy 4.0 does not know.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.capturing !== "" || root.typing
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.sideways(dx)
      }
      // Enter comes with returnRequested first, Space without: on a
      // recording, Enter opens it and Space plays it.
      property bool viaReturn: false
      onReturnRequested: viaReturn = true
      onActivateRequested: {
        var enter = viaReturn
        viaReturn = false
        if (!root.cursorActive) { root.cursorActive = true; return }
        var row = root.rows[root.cursor]
        if (row && row.kind === "memo" && !enter) return root.play()
        root.activate(root.cursor)
      }
      onDeleteRequested: root.remove()
      onCloseRequested: root.closeRequested()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Listens for the dictation or memo key while a key row waits for one.
      Item {
        id: keyListener
        focus: root.capturing !== ""
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
          event.accepted = true
          if (event.key === Qt.Key_Escape) { root.capturing = ""; keyCatcher.forceActiveFocus(); return }
          var name = root.keyName(event)
          if (name === "") return
          var row = null
          for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === root.capturing) row = root.rows[i]
          if (row) root.command(row, name)
          root.capturing = ""
          keyCatcher.forceActiveFocus()
        }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // The main page: kyrr's name, what it does, and the line under it.
        PanelHero {
          id: hero
          visible: root.page === "main" || !root.running || !root.kyrr.setupDone
          width: parent.width
          title: root.running && !root.kyrr.setupDone ? root.view.title : "kyrr"
          meta: root.running && !root.kyrr.setupDone ? "" : root.statusText()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.running ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.glyph(0xF147D)
              color: root.busy ? (root.mode === "recording" ? root.urgent : Commons.Color.accent) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // The line under the name, and the little wave after it as in
        // kyrr's window: it sways while kyrr works and breathes slowly while
        // it waits for an app to use the microphone.
        Row {
          id: statusRow
          visible: root.page === "main" && statusLine.text !== ""
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: statusLine
            width: Math.min(implicitWidth, parent.width - pulse.width - parent.spacing)
            textFormat: Text.PlainText
            text: root.running && root.kyrr.setupDone && root.kyrr.line ? root.kyrr.line : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
            wrapMode: Text.WordWrap
          }

          Item {
            id: pulse
            readonly property string state_: root.running ? String(root.kyrr.pulse || "") : ""
            readonly property bool working: state_ === "working"
            readonly property bool moving: state_ !== ""
            // Sways so far (1 = one full sway); slow on purpose, this is
            // kyrr after all.
            property real phase: 0
            width: 14
            height: 16

            // Driven by the screen's frames, not a timer, so it glides.
            FrameAnimation {
              running: pulse.moving && root.opened && pulse.parent.visible
              onTriggered: pulse.phase = (pulse.phase + Math.min(frameTime, 0.1) * 1000 / (pulse.working ? 2200 : 4500)) % 1
            }

            Repeater {
              model: 4
              Item {
                readonly property real level: pulse.moving
                  ? (pulse.working ? 1 : 0.3) * (0.5 + 0.5 * Math.sin((pulse.phase * 360 + index * 75) * Math.PI / 180)) : 0
                // As in kyrr's window: whole pixels (an even number, so it
                // stays centred) as a solid middle, the rest as a fading
                // pixel at each end, so the bar grows smoothly.
                readonly property real size: 2 + 10 * level
                readonly property real middle: 2 * Math.floor(size / 2)
                readonly property real rest: (size - middle) / 2
                readonly property real alpha: pulse.moving ? 0.85 : 0.4
                x: index * 4
                width: 2
                height: pulse.height

                Rectangle {
                  y: (parent.height - height) / 2
                  width: 2
                  height: parent.middle
                  color: Commons.Color.accent
                  opacity: parent.alpha
                }
                Rectangle {
                  y: (parent.height - parent.middle) / 2 - 1
                  width: 2
                  height: 1
                  color: Commons.Color.accent
                  opacity: parent.alpha * parent.rest
                }
                Rectangle {
                  y: (parent.height + parent.middle) / 2
                  width: 2
                  height: 1
                  color: Commons.Color.accent
                  opacity: parent.alpha * parent.rest
                }
              }
            }
          }
        }

        // A page below the main one: its title, and the way back.
        CursorSurface {
          id: header
          visible: root.page !== "main" && root.running && root.kyrr.setupDone
          width: parent.width
          foreground: root.foreground
          hasCursor: headerMouse.containsMouse
          implicitHeight: headerRow.implicitHeight + Style.spacing.rowPaddingX

          MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.back()
          }

          RowLayout {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: root.glyph(0xF0141)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.view.title
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              text: "Esc"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { id: separator; foreground: root.foreground }

        // Every page shows whole; only a screen too small for it scrolls.
        Flickable {
          id: list
          readonly property real room: {
            var card = panel.availableCardHeight > 0 ? panel.availableCardHeight : Screen.height - Style.space(60)
            var used = panel.padding * 2 + Style.space(8) + separator.height + column.spacing * 2
            if (hero.visible) used += hero.height + column.spacing
            if (statusRow.visible) used += statusRow.height + column.spacing
            if (header.visible) used += header.height + column.spacing
            if (note.visible) used += note.height + column.spacing
            return Math.max(Style.space(240), card - used)
          }
          width: parent.width
          height: Math.min(rowColumn.implicitHeight, room)
          contentHeight: rowColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: rowColumn
            width: list.width
            spacing: Style.space(4)

            Repeater {
              id: rowRepeater
              // By count, not by the rows themselves: kyrr's state comes
              // every few hundred milliseconds, and new rows each time would
              // make new row items, losing a click pressed on the old one.
              model: root.rows.length
              delegate: Loader {
                required property int index
                readonly property var row: root.rows[index] || ({})
                readonly property int rowIndex: index
                width: rowColumn.width
                sourceComponent: row.kind === "edit" ? editRow
                  : row.kind === "editor" ? editorRow
                  : row.kind === "section" ? sectionRow
                  : row.kind === "info" ? infoRow
                  : row.kind === "progress" ? progressRow
                  : row.kind === "separator" ? separatorRow
                  : row.kind === "buttons" ? buttonsRow
                  : selectableRow
              }
            }
          }
        }

        // The note at the bottom of kyrr's window elsewhere: problems in red,
        // a microphone that came back in the accent.
        Text {
          id: note
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.running && root.kyrr.note ? root.kyrr.note : ""
          color: root.running && root.kyrr.noteGood ? Commons.Color.accent : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ------------------------------------------------------------ rows

  Component {
    id: sectionRow
    PanelSectionHeader {
      width: parent ? parent.width : 0
      leftPadding: Style.space(10)
      topPadding: Style.space(8)
      text: parent ? parent.row.label : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  Component {
    id: separatorRow
    Item {
      width: parent ? parent.width : 0
      height: Style.space(9)
      PanelSeparator {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        foreground: root.foreground
      }
    }
  }

  Component {
    id: infoRow
    Text {
      readonly property var r: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      textFormat: Text.PlainText
      text: r.label || ""
      color: r.body ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: r.body ? Style.font.body : Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Component {
    id: progressRow
    Column {
      readonly property var r: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: parent.r.label || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        width: parent.width - parent.leftPadding - parent.rightPadding
        height: Style.space(4)
        color: Qt.darker(root.foreground, 3)
        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, parent.parent.r.value || 0))
          height: parent.height
          color: Commons.Color.accent
        }
      }
    }
  }

  // Every row the cursor can stop on: switch, choice, slider, key, action,
  // radio, memo.
  Component {
    id: selectableRow
    CursorSurface {
      id: rowItem
      readonly property var r: parent ? parent.row : ({})
      readonly property int rowIndex: parent ? parent.rowIndex : -1
      readonly property bool on: root.enabled(r)
      readonly property color ink: r.urgent ? root.urgent : r.accent ? Commons.Color.accent : root.foreground

      width: parent ? parent.width : 0
      hasCursor: root.cursorActive && root.cursor === rowIndex
      foreground: ink
      implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
      opacity: on ? 1 : 0.45

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onEntered: root.pointAt(rowItem.rowIndex)
        onClicked: function(mouse) {
          root.pointAt(rowItem.rowIndex)
          var r = rowItem.r
          // A choice's arrows step back and forth; a click elsewhere on it
          // takes the next option, as Enter does.
          var left = content.x + valueText.x
          var arrows = r.kind === "choice" || r.kind === "slider"
          var dx = arrows && mouse.x >= left - Style.space(6) && mouse.x < left + Style.space(16) ? -1
            : arrows && mouse.x > left + valueText.width - Style.space(16) ? 1 : 0
          if (dx !== 0) root.sideways(dx)
          else root.activate(rowItem.rowIndex)
        }
      }

      RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        // A recording's ▶ (or ■ while it plays) is a button of its own: a
        // click elsewhere on the row opens the recording.
        PanelActionButton {
          visible: rowItem.r.kind === "memo"
          iconText: root.glyph(rowItem.r.playing ? 0xF04DB : 0xF040A)
          tooltipText: rowItem.r.playing ? root.t("stop") : root.t("play")
          foreground: rowItem.r.playing || (rowItem.r.memo && rowItem.r.memo.isNew) ? Commons.Color.accent : rowItem.ink
          hoverColor: Commons.Color.accent
          fontFamily: root.fontFamily
          Layout.preferredWidth: Style.font.icon * 1.4
          Layout.alignment: Qt.AlignVCenter
          onClicked: {
            root.pointAt(rowItem.rowIndex)
            root.play()
          }
        }

        Text {
          visible: !!rowItem.r.icon || rowItem.r.kind === "radio"
          textFormat: Text.PlainText
          text: rowItem.r.kind === "radio" ? root.glyph(rowItem.r.checked ? 0xF0134 : 0xF0130)
            : rowItem.r.icon ? root.glyph(rowItem.r.icon) : ""
          color: rowItem.r.kind === "radio" && rowItem.r.checked ? Commons.Color.accent : rowItem.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.preferredWidth: Style.font.icon * 1.4
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(1)

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: rowItem.r.label || ""
            color: rowItem.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            readonly property string caption: root.deleting === rowItem.r.id ? root.t("deleteForGood") : (rowItem.r.caption || "")
            visible: caption !== ""
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: caption
            color: root.deleting === rowItem.r.id ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // A choice: ‹ the option ›. A key: the key, or a prompt to press one.
        // An action: a value, and an arrow when it opens a page.
        Text {
          id: valueText
          readonly property string label: {
            var r = rowItem.r
            if (r.kind === "choice") {
              for (var i = 0; i < r.options.length; i++) if (r.options[i].value === r.value) return r.options[i].label
              return ""
            }
            if (r.kind === "slider") return (r.value > 0 ? "+" : r.value < 0 ? "−" : "") + Math.abs(r.value) + " " + r.unit
            if (r.kind === "key") return root.capturing === r.id ? root.t("pressKey") : r.value
            return r.value || ""
          }
          visible: label !== ""
          textFormat: Text.PlainText
          text: rowItem.r.kind === "choice" || rowItem.r.kind === "slider" ? "‹ " + label + " ›" : rowItem.r.kind === "key" && root.capturing !== rowItem.r.id ? "[ " + label + " ]" : label
          color: rowItem.r.kind === "choice" || rowItem.r.kind === "key" || rowItem.r.kind === "slider" ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: rowItem.r.kind === "choice" || rowItem.r.kind === "key" || rowItem.r.kind === "slider"
          elide: Text.ElideRight
          Layout.maximumWidth: Style.space(170)
          Layout.alignment: Qt.AlignVCenter
        }

        // A recording: its bin, click twice like x twice.
        PanelActionButton {
          visible: rowItem.r.kind === "memo"
          iconText: root.glyph(0xF01B4)
          tooltipText: root.t("delete")
          foreground: root.deleting === rowItem.r.id ? root.urgent : root.dim
          hoverColor: root.deleting === rowItem.r.id ? root.urgent : root.foreground
          fontFamily: root.fontFamily
          Layout.alignment: Qt.AlignVCenter
          onClicked: {
            root.pointAt(rowItem.rowIndex)
            root.remove()
          }
        }

        Text {
          visible: !!rowItem.r.page && rowItem.r.kind !== "switch"
          textFormat: Text.PlainText
          text: root.glyph(0xF0142)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.alignment: Qt.AlignVCenter
        }

        PanelActionButton {
          visible: rowItem.r.kind === "switch" && !!rowItem.r.page
          iconText: root.glyph(0xF0493)
          tooltipText: rowItem.r.label || ""
          foreground: root.dim
          hoverColor: root.foreground
          fontFamily: root.fontFamily
          Layout.alignment: Qt.AlignVCenter
          onClicked: root.openPage(rowItem.r.page)
        }

        ToggleSwitch {
          visible: rowItem.r.kind === "switch"
          checked: !!rowItem.r.checked
          interactive: false
          foreground: root.foreground
          Layout.alignment: Qt.AlignVCenter
        }
      }

      // How far a recording has played.
      Rectangle {
        visible: rowItem.r.bar !== undefined
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(10)
        anchors.bottomMargin: Style.space(2)
        width: (parent.width - Style.space(20)) * Math.max(0, Math.min(1, rowItem.r.bar || 0))
        height: Style.space(2)
        color: Commons.Color.accent
      }
    }
  }

  // A row of buttons: ← and → pick one, Enter or a click presses it. The
  // bin asks once, like x.
  Component {
    id: buttonsRow
    Item {
      id: buttonsItem
      readonly property var r: parent ? parent.row : ({})
      readonly property int rowIndex: parent ? parent.rowIndex : -1
      readonly property bool asking: root.deleting !== "" && root.deleting === r.id

      width: parent ? parent.width : 0
      implicitHeight: buttonFlow.implicitHeight + (askText.visible ? askText.implicitHeight + Style.space(4) : 0)

      Flow {
        id: buttonFlow
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: buttonsItem.r.buttons ? buttonsItem.r.buttons.length : 0
          delegate: CursorSurface {
            id: button
            required property int index
            readonly property var b: buttonsItem.r.buttons[index] || ({})
            readonly property color ink: b.urgent ? root.urgent : root.foreground

            hasCursor: root.cursorActive && root.cursor === buttonsItem.rowIndex && root.pick === index
            opacity: b.enabled === false ? 0.45 : 1
            bordered: true
            foreground: ink
            implicitWidth: buttonContent.implicitWidth + Style.space(20)
            implicitHeight: buttonContent.implicitHeight + Style.space(12)

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.pointAt(buttonsItem.rowIndex)
                if (root.pick !== button.index) root.deleting = ""
                root.pick = button.index
              }
              onClicked: {
                root.pointAt(buttonsItem.rowIndex)
                root.press(buttonsItem.r, button.index)
              }
            }

            Row {
              id: buttonContent
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                visible: !!button.b.icon
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: button.b.icon ? root.glyph(button.b.icon) : ""
                color: button.ink
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: button.b.label || ""
                color: button.ink
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }

      Text {
        id: askText
        visible: buttonsItem.asking
        anchors.top: buttonFlow.bottom
        anchors.topMargin: Style.space(4)
        width: parent.width
        leftPadding: Style.space(10)
        textFormat: Text.PlainText
        text: root.t("deleteForGood")
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  // A line to type into: the search over the recordings, a recording's
  // title. Enter (or a click) starts typing, Enter takes it, Esc leaves it.
  Component {
    id: editRow
    CursorSurface {
      id: editItem
      readonly property var r: parent ? parent.row : ({})
      readonly property int rowIndex: parent ? parent.rowIndex : -1

      function startTyping() {
        input.forceActiveFocus()
        input.selectAll()
      }

      width: parent ? parent.width : 0
      hasCursor: root.cursorActive && root.cursor === rowIndex && !input.activeFocus
      foreground: root.foreground
      implicitHeight: editLayout.implicitHeight + Style.spacing.rowPaddingX

      // kyrr's value, while nobody types.
      onRChanged: if (!input.activeFocus && input.text !== (r.value || "")) input.text = r.value || ""

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.pointAt(editItem.rowIndex)
        onClicked: input.forceActiveFocus()
      }

      RowLayout {
        id: editLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          visible: !!editItem.r.icon
          textFormat: Text.PlainText
          text: editItem.r.icon ? root.glyph(editItem.r.icon) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.preferredWidth: Style.font.icon * 1.4
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          visible: !!editItem.r.label
          textFormat: Text.PlainText
          text: editItem.r.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          Layout.alignment: Qt.AlignVCenter
        }

        TextField {
          id: input
          // Taken with Enter: leaving the line afterwards takes it no more.
          property bool taken: false
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          placeholderText: editItem.r.placeholder || ""
          foreground: root.foreground
          font.family: root.fontFamily
          verticalPadding: Style.space(3)
          Component.onCompleted: {
            text = editItem.r.value || ""
            // A key shows as dots, whatever the field offers to hide it.
            if (editItem.r.secret && input.echoMode !== undefined) input.echoMode = TextInput.Password
          }
          onActiveFocusChanged: {
            root.typing = activeFocus
            if (activeFocus) root.pointAt(editItem.rowIndex)
            // A title left by a click elsewhere is taken as typed.
            else if (editItem.r.rename && !taken) root.submitEdit(editItem.r, text)
            taken = false
          }
          onTextEdited: if (editItem.r.live) liveTimer.restart()
          onAccepted: {
            liveTimer.stop()
            root.submitEdit(editItem.r, text)
            // A key is not kept in the field once it is sent.
            if (editItem.r.secret) text = ""
            taken = true
            keyCatcher.forceActiveFocus()
          }
          Keys.onEscapePressed: {
            if (!editItem.r.live) text = editItem.r.value || ""
            taken = true
            keyCatcher.forceActiveFocus()
          }
          // ↑ and ↓ leave the line for the rows around it.
          Keys.onUpPressed: { keyCatcher.forceActiveFocus(); root.moveCursor(-1) }
          Keys.onDownPressed: { keyCatcher.forceActiveFocus(); root.moveCursor(1) }
        }
      }

      Timer {
        id: liveTimer
        interval: 250
        onTriggered: root.submitEdit(editItem.r, input.text)
      }
    }
  }

  // A recording's text, as in kyrr's text view: read it, correct it (kyrr
  // saves it), select and copy it. Enter (or a click) goes in, Esc out.
  Component {
    id: editorRow
    CursorSurface {
      id: editorItem
      readonly property int rowIndex: parent ? parent.rowIndex : -1
      readonly property string memo: parent && parent.row.memo ? parent.row.memo : ""
      // The language model is working on the text: it is read-only meanwhile.
      readonly property bool locked: !!(parent && parent.row && parent.row.locked)

      function startTyping() {
        area.forceActiveFocus()
      }

      width: parent ? parent.width : 0
      hasCursor: root.cursorActive && root.cursor === rowIndex && !area.activeFocus
      bordered: true
      foreground: root.foreground
      implicitHeight: Style.space(440)

      // A click below the last line goes into the text too.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: {
          area.forceActiveFocus()
          area.cursorPosition = area.length
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Style.space(10)
        contentWidth: width
        contentHeight: area.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function follow(r) {
          if (contentY > r.y) contentY = r.y
          else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
        }

        TextEdit {
          id: area
          // Typed and not yet handed to kyrr; handed and not yet back.
          property bool dirty: false
          property var sent: null
          property bool loading: false
          readonly property string memo: editorItem.memo

          width: flick.width
          wrapMode: TextEdit.Wrap
          textFormat: TextEdit.PlainText
          readOnly: editorItem.locked
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          selectByMouse: true
          persistentSelection: true
          selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
          selectedTextColor: root.foreground

          // kyrr's text of this recording, unless something typed is on its
          // way.
          function load() {
            if (root.sheetId === "" || root.sheetId !== memo) return
            if (sent !== null) {
              if (root.sheetText !== sent) return
              sent = null
            }
            if (dirty || text === root.sheetText) return
            var at = cursorPosition
            loading = true
            text = root.sheetText
            cursorPosition = Math.min(at, length)
            loading = false
          }

          Component.onCompleted: {
            root.editorItem = area
            load()
          }
          Component.onDestruction: {
            root.flushEdit()
            if (root.editorItem === area) root.editorItem = null
            if (activeFocus) root.typing = false
          }
          onTextChanged: {
            if (loading) return
            dirty = true
            editTimer.restart()
          }
          onCursorPositionChanged: cursorTimer.restart()
          onCursorRectangleChanged: flick.follow(cursorRectangle)
          onActiveFocusChanged: {
            root.typing = activeFocus
            if (activeFocus) root.pointAt(editorItem.rowIndex)
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.flushEdit()
              keyCatcher.forceActiveFocus()
              event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
              // Copied by kyrr, which leaves the times behind.
              root.copySheet()
              event.accepted = true
            }
          }
        }
      }

      Connections {
        target: root
        function onSheetTextChanged() { area.load() }
        function onSheetIdChanged() { area.load() }
      }

      // Saved a moment after the last key, as in kyrr's window.
      Timer {
        id: editTimer
        interval: 400
        onTriggered: root.flushEdit()
      }

      // Tells kyrr where the cursor is, for "Play from here (1:30)".
      Timer {
        id: cursorTimer
        interval: 250
        onTriggered: root.send("memo cursor " + root.bytes(area.text.slice(0, area.cursorPosition)))
      }

      // Text handed to kyrr that never came back (kyrr gone, say).
      Timer {
        interval: 3000
        running: area.sent !== null
        onTriggered: { area.sent = null; area.load() }
      }
    }
  }
}
