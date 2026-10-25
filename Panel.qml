import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Texts.js" as Texts

// kyrr in Omarchy's bar: an icon that shows what kyrr does, and a menu with
// kyrr's switches. kyrr itself is a separate program (an AppImage); the menu
// installs it when it is missing.
//
// While kyrr runs it keeps one line of JSON in $XDG_RUNTIME_DIR/kyrr/state:
// what it does (mode: idle, listening, writing, recording), its switches and
// its process id. The menu flips a switch by writing one word to kyrr's
// socket, $XDG_RUNTIME_DIR/kyrr.sock; kyrr answers by rewriting the file.
// The widget renews $XDG_RUNTIME_DIR/kyrr-widget every few seconds: while
// that file is fresh, kyrr leaves out its tray icon and the window's buttons
// to hide or quit: the widget's menu opens kyrr's window, and turning kyrr
// off is turning the plugin off in Omarchy's menu.
Panel {
  id: root
  moduleName: "heast13.kyrr"
  ipcTarget: "heast13.kyrr"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDir + "/kyrr.sock"

  // The last state kyrr wrote, and whether its process still runs.
  property var kyrr: null
  property bool alive: false
  // Whether kyrr is installed (a command, or an entry in the app menu).
  property bool installed: true
  // Switches flipped here that kyrr has not confirmed yet, by name.
  property var wanted: ({})

  readonly property bool running: alive && kyrr !== null
  // A kyrr that writes the status line also knows "menu-open"; an older
  // one would show its window for every word it does not know.
  readonly property bool live: running && kyrr.line !== undefined
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

  // The menu's rows, top to bottom; the keyboard cursor walks them.
  readonly property var rows: {
    if (!running) return installed ? ["start"] : ["install"]
    // The switches of kyrr's main page, in its order.
    var list = ["filter", "voice", "dictation", "memos"]
    if (kyrr.memos && kyrr.memo) list.push("stop")
    if (kyrr.memos) list.push("recordings")
    if (kyrr.update) list.push("update")
    list.push("setup")
    return list
  }
  property int cursorIndex: 0
  property bool cursorActive: false

  function t(key, value) {
    return Texts.text(root.german, key, value)
  }

  function glyph(code) {
    return String.fromCodePoint(code)
  }

  function checked(name) {
    if (root.wanted[name] !== undefined) return root.wanted[name]
    return root.running && !!root.kyrr[name]
  }

  // One word to the running kyrr, the way its own dictation adapter does.
  function send(word) {
    if (root.bar) root.bar.run("printf %s " + word + " | socat - UNIX-CONNECT:" + Util.shellQuote(root.socketPath))
  }

  function flip(name, word) {
    var next = Object.assign({}, root.wanted)
    next[name] = !root.checked(name)
    root.wanted = next
    root.send(word)
  }

  // kyrr sits in ~/.local/bin, which the shell's own PATH may leave out.
  readonly property string findKyrr: "k=$(command -v kyrr || echo \"$HOME/.local/bin/kyrr\"); "
  readonly property string openCommand: findKyrr + "test -x \"$k\" && exec \"$k\"; "
    + "exec gio launch \"${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.heast13.kyrr.desktop\""
  readonly property string startCommand: findKyrr + "test -x \"$k\" && exec \"$k\" --background; " + openCommand
  // The install command from kyrr's website, in Omarchy's floating terminal so
  // every step shows, then kyrr's first start (its setup window).
  readonly property string installCommand: "mkdir -p ~/.local/bin && "
    + "curl -fL -o ~/.local/bin/kyrr.new https://github.com/heast13/kyrr/releases/latest/download/kyrr-x86_64.AppImage && "
    + "chmod +x ~/.local/bin/kyrr.new && mv -f ~/.local/bin/kyrr.new ~/.local/bin/kyrr && "
    + "setsid -f ~/.local/bin/kyrr >/dev/null 2>&1"

  function activate(name) {
    switch (name) {
    case "filter": root.flip("filter", "toggle-filter"); return
    case "voice": root.flip("voice", "toggle-voice"); return
    case "dictation": root.flip("dictation", "toggle-dictation"); return
    case "memos": root.flip("memos", "toggle-memos"); return
    case "stop": root.send("toggle-memo"); return
    case "recordings": root.send("open-memos"); root.close(); return
    case "update": root.send("install-update"); root.close(); return
    case "setup": root.openPage(1); return
    case "start": if (root.bar) root.bar.run(root.startCommand); return
    case "install":
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(root.installCommand))
      root.close()
      return
    }
  }

  // A page of kyrr's window: 1 Setup, 2 to 5 a switch's settings (its gear).
  function openPage(page) {
    root.send("page-" + page)
    root.close()
  }

  function moveCursor(dy) {
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    root.cursorIndex = Math.max(0, Math.min(root.rows.length - 1, root.cursorIndex + dy))
  }

  function pointAt(name) {
    root.cursorActive = true
    root.cursorIndex = Math.max(0, root.rows.indexOf(name))
  }

  function hasCursor(name) {
    return root.cursorActive && root.rows[root.cursorIndex] === name
  }

  function statusText() {
    if (!root.installed && !root.running) return root.t("notInstalled")
    if (!root.running) return root.t("notRunning")
    if (root.mode === "listening") return root.t("listening")
    if (root.mode === "writing") return root.t("writing")
    if (root.mode === "recording") return root.t("recording")
    return root.kyrr.dictation && root.kyrr.ready ? root.t("readyKey", root.kyrr.key) : root.t("ready")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onRowsChanged: if (cursorIndex >= rows.length) cursorIndex = Math.max(0, rows.length - 1)
  // While the menu is open kyrr keeps its status line and notes going for
  // it, as for its window; it hears "menu-open" every few seconds.
  onOpenedChanged: {
    if (live) send(opened ? "menu-open" : "menu-closed")
    if (opened) openMenu()
  }

  function openMenu() {
    cursorActive = false
    cursorIndex = 0
    stateFile.reload()
    lookForKyrr.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

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
      root.wanted = ({})
      if (!root.alive) aliveProbe.running = true
    }
    onLoadFailed: {
      root.kyrr = null
      root.alive = false
      root.wanted = ({})
    }
    onFileChanged: reload()
  }

  // A kyrr that crashed leaves its file behind: whether something answers
  // on its socket says if it still runs. "background" is the word kyrr
  // ignores (a start at sign-in while it runs). The shell cannot read /proc.
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
    command: ["bash", "-lc", "command -v kyrr >/dev/null || test -x \"$HOME/.local/bin/kyrr\" || test -f \"${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.heast13.kyrr.desktop\""]
    onExited: function(code) { root.installed = code === 0 }
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
      if (root.opened && root.live && ticks % 2 === 0) root.send("menu-open")
      if (ticks % 5 === 0) {
        if (widgetFile.path !== "") widgetFile.setText(Date.now() + "\n")
        if (!root.running) lookForKyrr.running = true
      }
      ticks++
    }
  }

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
      else if (buttonCode === Qt.RightButton && root.running) root.send("show")
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    // A plain child rather than `content:`, which Omarchy 4.0 does not know.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activate(root.rows[root.cursorIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "kyrr"
          meta: root.statusText()
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

        // The line under kyrr's name in its window.
        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.running && root.kyrr.line ? root.kyrr.line : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(4)

          SwitchRow {
            name: "filter"
            page: 2
            icon: 0xF036C
            label: root.t("filter")
            caption: root.t(root.checked("filter") ? "filterOn" : "filterOff")
          }
          SwitchRow {
            name: "voice"
            page: 3
            icon: 0xF0068
            label: root.t("voice")
            caption: root.t(root.checked("voice") ? "voiceOn" : "voiceOff")
          }
          SwitchRow {
            name: "dictation"
            page: 4
            icon: 0xF030C
            label: root.t("dictation")
            caption: !root.running ? ""
              : !root.checked("dictation") ? root.t("dictationOff", root.kyrr.key)
              : root.kyrr.ready ? root.t("dictationOn", root.kyrr.key)
              : root.t("dictationNotReady")
          }
          SwitchRow {
            name: "memos"
            page: 5
            // Like the window: the gear only while recordings are on.
            gear: root.checked("memos")
            icon: 0xF044A
            label: root.t("memos")
            caption: !root.running ? ""
              : !root.checked("memos") ? root.t("memosOff")
              : root.kyrr.memo ? root.t(root.kyrr.memoKey ? "memosRecordingKey" : "memosRecording", root.kyrr.memoKey)
              : root.t(root.kyrr.memoKey ? "memosOnKey" : "memosOn", root.kyrr.memoKey)
          }
          // Started with the key; only a running one gets a button, as in
          // the window.
          ActionRow {
            name: "stop"
            icon: 0xF04DB
            iconColor: root.urgent
            hoverColor: root.urgent
            label: root.t("stop")
          }
          ActionRow {
            name: "recordings"
            icon: 0xF1359
            label: root.t("recordings")
          }
          ActionRow {
            name: "update"
            icon: 0xF01DA
            label: root.t("update", root.running ? root.kyrr.update : "")
          }
          ActionRow {
            name: "start"
            icon: 0xF040A
            label: root.t("start")
            caption: root.t("startHint")
          }
          ActionRow {
            name: "install"
            icon: 0xF01DA
            label: root.t("install")
            caption: root.t("installHint")
          }
        }

        PanelSeparator {
          visible: root.running
          foreground: root.foreground
        }

        Column {
          visible: root.running
          width: parent.width
          spacing: Style.space(4)

          ActionRow {
            name: "setup"
            icon: 0xF066A
            label: root.t("setup")
          }
        }

        // The note at the bottom of kyrr's window: problems in red, a
        // microphone that came back in the accent.
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

  // A row with kyrr's switch on the right; a click anywhere flips it.
  component SwitchRow: CursorSurface {
    id: switchRow
    property string name: ""
    // The window's page with this switch's settings.
    property int page: 0
    property bool gear: true
    property int icon: 0
    property string label: ""
    property string caption: ""

    visible: root.rows.indexOf(name) >= 0
    width: parent ? parent.width : 0
    hasCursor: root.hasCursor(name)
    foreground: root.foreground
    implicitHeight: switchContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.pointAt(switchRow.name)
      onClicked: root.activate(switchRow.name)
    }

    RowLayout {
      id: switchContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      RowIcon { code: switchRow.icon }

      RowLabels {
        label: switchRow.label
        caption: switchRow.caption
      }

      PanelActionButton {
        visible: switchRow.page > 0 && switchRow.gear && root.running
        iconText: root.glyph(0xF0493)
        tooltipText: root.t("settingsOf", switchRow.label)
        foreground: root.dim
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openPage(switchRow.page)
      }

      ToggleSwitch {
        checked: root.checked(switchRow.name)
        interactive: false
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A row that does one thing when clicked.
  component ActionRow: CursorSurface {
    id: actionRow
    property string name: ""
    property int icon: 0
    property color iconColor: root.foreground
    property color hoverColor: root.foreground
    property string label: ""
    property string caption: ""

    visible: root.rows.indexOf(name) >= 0
    width: parent ? parent.width : 0
    hasCursor: root.hasCursor(name)
    foreground: hoverColor
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.pointAt(actionRow.name)
      onClicked: root.activate(actionRow.name)
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      RowIcon {
        code: actionRow.icon
        color: actionRow.hasCursor ? actionRow.hoverColor : actionRow.iconColor
      }

      RowLabels {
        label: actionRow.label
        caption: actionRow.caption
        color: actionRow.hasCursor ? actionRow.hoverColor : root.foreground
      }
    }
  }

  component RowIcon: Text {
    property int code: 0
    textFormat: Text.PlainText
    text: code ? root.glyph(code) : ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.icon
    Layout.preferredWidth: Style.font.icon * 1.4
    Layout.alignment: Qt.AlignVCenter
  }

  component RowLabels: ColumnLayout {
    property string label: ""
    property string caption: ""
    property color color: root.foreground
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: Style.space(1)

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: parent.label
      color: parent.color
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: parent.caption !== ""
      Layout.fillWidth: true
      text: parent.caption
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
