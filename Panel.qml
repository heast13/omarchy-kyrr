import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
  moduleName: "heast13.kyrr"
  ipcTarget: "heast13.kyrr"

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

  readonly property bool running: alive && kyrr !== null && kyrr.v === 2
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
  readonly property var view: running ? Views.build(page, kyrr, t)
    : { title: "", rows: [installed
        ? { kind: "info", label: t("starting") }
        : { kind: "action", id: "install", icon: Views.GLYPH.install, label: t("install"), caption: t("installHint") }] }
  readonly property var rows: view.rows
  property int cursor: -1
  property bool cursorActive: false
  // A key row listening for the next key press, by row id.
  property string capturing: ""
  // A recording asked to be deleted once already, by row id.
  property string deleting: ""

  function t(key, value) {
    return Texts.text(root.german, key, value)
  }

  function glyph(code) {
    return String.fromCodePoint(code)
  }

  // One line to the running kyrr.
  function send(line) {
    if (root.bar) root.bar.run("printf '%s\\n' " + Util.shellQuote(line) + " | socat - UNIX-CONNECT:" + Util.shellQuote(root.socketPath))
  }

  function command(row, value) {
    if (!row.cmd) return
    root.send(value === undefined ? row.cmd : row.cmd.replace("{}", String(value)))
  }

  // kyrr sits in ~/.local/bin, which the shell's own PATH may leave out.
  readonly property string findKyrr: "k=$(command -v kyrr || echo \"$HOME/.local/bin/kyrr\"); "
  readonly property string startCommand: findKyrr + "test -x \"$k\" && exec \"$k\" --background"
  // The install command from kyrr's website, in Omarchy's floating terminal so
  // every step shows; kyrr then starts in the background and this menu runs
  // its first-run setup.
  readonly property string installCommand: "mkdir -p ~/.local/bin && "
    + "curl -fL -o ~/.local/bin/kyrr.new https://github.com/heast13/kyrr/releases/latest/download/kyrr-x86_64.AppImage && "
    + "chmod +x ~/.local/bin/kyrr.new && mv -f ~/.local/bin/kyrr.new ~/.local/bin/kyrr && "
    + "setsid -f ~/.local/bin/kyrr --background >/dev/null 2>&1"

  function startKyrr() {
    if (!root.bar || root.running || !root.installed) return
    if (Date.now() - root.startedAt < 60000) return
    root.startedAt = Date.now()
    root.bar.run(root.startCommand)
  }

  // ------------------------------------------------------------ pages

  function openPage(name) {
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
  }

  // ← and →: a choice or slider moves, anything with a page opens it, and
  // otherwise ← is one page back.
  function sideways(dx) {
    var row = root.rows[root.cursor]
    if (root.cursorActive && row && root.enabled(row)) {
      if (row.kind === "choice") return root.step(row, dx)
      if (row.kind === "slider") return root.command(row, Math.max(row.min, Math.min(row.max, row.value + dx * row.step)))
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
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(root.installCommand))
      root.close()
      return
    }
    if (!root.enabled(row)) return
    switch (row.kind) {
    case "choice":
      var at = 0
      for (var i = 0; i < row.options.length; i++) if (row.options[i].value === row.value) at = i
      root.command(row, row.options[(at + 1) % row.options.length].value)
      return
    case "key":
      root.capturing = row.id
      return
    case "slider":
      return
    case "action":
      if (row.page) root.openPage(row.page)
      else root.command(row)
      return
    default:
      root.command(row)
    }
  }

  function remove() {
    var row = root.rows[root.cursor]
    if (!row || row.kind !== "memo") return
    if (root.deleting === row.id) {
      root.send("memo delete " + row.memo.id)
      root.deleting = ""
    } else {
      root.deleting = row.id
    }
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
    if (!root.running) return
    root.send(root.page.indexOf("text:") === 0 ? "memo show " + root.page.slice(5) : "memo show")
    if (root.page === "recordings") root.send("memo seen")
  }
  // While the menu is open kyrr keeps its status line, notes and meters
  // going for it; it hears "menu-open" every few seconds.
  onOpenedChanged: {
    if (root.running) root.send(opened ? "menu-open" : "menu-closed")
    if (opened) openMenu()
    else { root.capturing = ""; root.deleting = "" }
  }

  function openMenu() {
    root.stack = ["main"]
    root.cursors = ({})
    root.cursorActive = false
    root.cursor = root.firstSelectable()
    stateFile.reload()
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
      var parsed = null
      try {
        parsed = JSON.parse(text())
      } catch (e) {
        // A read in the middle of kyrr's write: keep what was there.
        return
      }
      root.kyrr = parsed
      if (!root.alive) aliveProbe.running = true
    }
    onLoadFailed: {
      root.kyrr = null
      root.alive = false
    }
    onFileChanged: reload()
  }

  // A kyrr that crashed leaves its file behind: whether something answers
  // on its socket says if it still runs. "background" is the word kyrr
  // ignores. The shell cannot read /proc.
  Process {
    id: aliveProbe
    command: ["sh", "-c", "printf background | socat - UNIX-CONNECT:" + Util.shellQuote(root.socketPath) + " 2>/dev/null"]
    onExited: function(exitCode) { root.alive = exitCode === 0 && root.kyrr !== null }
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
      if (root.kyrr !== null && ticks % 2 === 0) aliveProbe.running = true
      if (root.opened && root.running && ticks % 2 === 0) root.send("menu-open")
      if (ticks % 5 === 0) {
        if (widgetFile.path !== "") widgetFile.setText(Date.now() + "\n")
        if (!root.running) lookForKyrr.running = true
      }
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(660))

    // A plain child rather than `content:`, which Omarchy 4.0 does not know.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.capturing !== ""
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.sideways(dx)
      }
      onActivateRequested: {
        if (!root.cursorActive) { root.cursorActive = true; return }
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
            // Sways so far (1 = one full sway); slow on purpose.
            property real phase: 0
            property real lastTick: 0
            width: 14
            height: Math.max(16, statusLine.font.pixelSize * 1.3)

            Timer {
              interval: pulse.working ? 33 : 66
              running: pulse.moving && root.opened
              repeat: true
              onRunningChanged: pulse.lastTick = Date.now()
              onTriggered: {
                var now = Date.now()
                var step = Math.min(now - pulse.lastTick, 100)
                pulse.lastTick = now
                pulse.phase = (pulse.phase + step / (pulse.working ? 2200 : 4500)) % 1
              }
            }

            Repeater {
              model: 4
              Rectangle {
                readonly property real level: pulse.moving
                  ? (pulse.working ? 1 : 0.3) * (0.5 + 0.5 * Math.sin((pulse.phase * 360 + index * 75) * Math.PI / 180)) : 0
                x: index * 4
                width: 2
                height: Math.round(2 + 10 * level)
                y: (pulse.height - height) / 2
                color: Commons.Color.accent
                opacity: pulse.moving ? 0.85 : 0.4
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

        PanelSeparator { foreground: root.foreground }

        Flickable {
          id: list
          width: parent.width
          height: Math.min(rowColumn.implicitHeight, Style.space(520))
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
              model: root.rows
              delegate: Loader {
                required property var modelData
                required property int index
                readonly property var row: modelData
                readonly property int rowIndex: index
                width: rowColumn.width
                sourceComponent: modelData.kind === "section" ? sectionRow
                  : modelData.kind === "info" ? infoRow
                  : modelData.kind === "progress" ? progressRow
                  : modelData.kind === "separator" ? separatorRow
                  : selectableRow
              }
            }
          }
        }

        // The note at the bottom of kyrr's window elsewhere: problems in red,
        // a microphone that came back in the accent.
        Text {
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

        Text {
          visible: !!rowItem.r.icon || rowItem.r.kind === "radio" || rowItem.r.kind === "memo"
          textFormat: Text.PlainText
          text: rowItem.r.kind === "radio" ? root.glyph(rowItem.r.checked ? 0xF0134 : 0xF0130)
            : rowItem.r.kind === "memo" ? root.glyph(rowItem.r.memo.isNew ? 0xF0765 : 0xF040A)
            : rowItem.r.icon ? root.glyph(rowItem.r.icon) : ""
          color: rowItem.r.kind === "memo" && rowItem.r.memo.isNew ? Commons.Color.accent
            : rowItem.r.kind === "radio" && rowItem.r.checked ? Commons.Color.accent : rowItem.ink
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
    }
  }
}
