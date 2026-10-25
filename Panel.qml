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
// to hide or quit, since this menu does both.
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
  readonly property string mode: running ? String(kyrr.mode || "idle") : ""
  readonly property bool busy: mode === "listening" || mode === "writing" || mode === "recording"
  readonly property string language: running && kyrr.lang ? kyrr.lang : Commons.I18n.language
  readonly property bool german: language.indexOf("de") === 0

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The menu's rows, top to bottom; the keyboard cursor walks them.
  readonly property var rows: {
    if (!running) return installed ? ["start"] : ["install"]
    var list = ["filter", "voice", "dictation"]
    if (kyrr.memos) list.push("memo", "memos")
    if (kyrr.update) list.push("update")
    list.push("open", "quit")
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

  readonly property string openCommand: "command -v kyrr >/dev/null && exec kyrr; "
    + "exec gio launch \"${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.heast13.kyrr.desktop\""
  readonly property string startCommand: "command -v kyrr >/dev/null && exec kyrr --background; " + openCommand
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
    case "memo": root.send("toggle-memo"); return
    case "memos": root.send("open-memos"); root.close(); return
    case "update": root.send("install-update"); root.close(); return
    case "open": root.send("show"); root.close(); return
    case "quit": root.send("quit"); root.close(); return
    case "start": if (root.bar) root.bar.run(root.startCommand); return
    case "install":
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(root.installCommand))
      root.close()
      return
    }
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
  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    stateFile.reload()
    lookForKyrr.running = true
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
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
      processFile.reload()
    }
    onLoadFailed: {
      root.kyrr = null
      root.alive = false
      root.wanted = ({})
    }
    onFileChanged: reload()
  }

  // A kyrr that crashed leaves its file behind: its process is gone.
  FileView {
    id: processFile
    path: root.kyrr && root.kyrr.pid ? "/proc/" + root.kyrr.pid + "/comm" : ""
    printErrors: false
    onLoaded: root.alive = text().trim() === "kyrr"
    onLoadFailed: root.alive = false
  }

  // Tells kyrr that this widget sits in the bar.
  FileView {
    id: widgetFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/kyrr-widget" : ""
    printErrors: false
  }

  Process {
    id: lookForKyrr
    command: ["bash", "-lc", "command -v kyrr >/dev/null || test -f \"${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.heast13.kyrr.desktop\""]
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
      processFile.reload()
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
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
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

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(4)

          SwitchRow {
            name: "filter"
            icon: 0xF036C
            label: root.t("filter")
            caption: root.t(root.checked("filter") ? "filterOn" : "filterOff")
          }
          SwitchRow {
            name: "voice"
            icon: 0xF0068
            label: root.t("voice")
            caption: root.t(root.checked("voice") ? "voiceOn" : "voiceOff")
          }
          SwitchRow {
            name: "dictation"
            icon: 0xF030C
            label: root.t("dictation")
            caption: !root.running ? ""
              : !root.checked("dictation") ? root.t("dictationOff", root.kyrr.key)
              : root.kyrr.ready ? root.t("dictationOn", root.kyrr.key)
              : root.t("dictationNotReady")
          }
          ActionRow {
            name: "memo"
            icon: root.running && root.kyrr.memo ? 0xF04DB : 0xF044A
            iconColor: root.running && root.kyrr.memo ? root.urgent : root.foreground
            label: root.t(root.running && root.kyrr.memo ? "memoStop" : "memoStart")
            caption: root.running && root.kyrr.memoKey ? root.t("memoKey", root.kyrr.memoKey) : ""
          }
          ActionRow {
            name: "memos"
            icon: 0xF1359
            label: root.t("memos")
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
            name: "open"
            icon: 0xF0493
            label: root.t("open")
          }
          ActionRow {
            name: "quit"
            icon: 0xF0425
            label: root.t("quit")
            hoverColor: root.urgent
          }
        }
      }
    }
  }

  // A row with kyrr's switch on the right; a click anywhere flips it.
  component SwitchRow: CursorSurface {
    id: switchRow
    property string name: ""
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
