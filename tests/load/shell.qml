import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A bare Omarchy shell for the load job: one bar with the kyrr widget in it,
// made the way Omarchy's Bar.qml and shell.qml make a plugin's bar widget (the
// component loaded from the plugin's folder, `bar` handed over as a
// PluginBarApi, the other properties injected afterwards). Commons and Ui are
// Omarchy's own, copied next to this file. Everything below the "test hooks"
// line exists for the test only; the plugin has none of it.
ShellRoot {
  id: shell

  readonly property string pluginId: "io.github.heast13.kyrr"
  readonly property string pluginDir: Quickshell.env("KYRR_PLUGIN_DIR")
  readonly property string runLog: Quickshell.env("KYRR_RUN_LOG")
  property var widgetComponent: null
  readonly property var widget: slot.item

  // bar.run() runs a command through a login shell in Omarchy. Here it is
  // only written down, so the test can read what the menu would have run.
  function logRun(command) {
    Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >> \"$2\"", "sh", command, shell.runLog])
  }

  PluginBarApi {
    id: api
    pluginId: shell.pluginId
    moduleName: shell.pluginId
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    background: Commons.Color.bar.background
    urgent: Commons.Color.bar.active
    fontFamily: Style.font.family
    position: "top"
    barSize: Style.bar.sizeHorizontal
    _run: function(command) { shell.logRun(command) }
    _registerClickTarget: function(target) {
      if (api.clickTargets.indexOf(target) === -1) api.clickTargets = api.clickTargets.concat([target])
    }
    _unregisterClickTarget: function(target) {
      api.clickTargets = api.clickTargets.filter(function(item) { return item !== target })
    }
    _targetBelongsToWindow: function(target, window) { return true }
    _requestPopout: function(owner) {
      if (api.activePopout === owner) return
      if (api.activePopout && "close" in api.activePopout) api.activePopout.close()
      api.activePopout = owner
    }
    _releasePopout: function(owner) { if (api.activePopout === owner) api.activePopout = null }
    _showTooltip: function(target, text) {}
    _hideTooltip: function(target) {}
  }

  // As shell.qml's loadPluginWidget does.
  Component.onCompleted: {
    var url = "file://" + shell.pluginDir + "/Panel.qml"
    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) shell.widgetComponent = comp
      else if (comp.status === Component.Error) console.warn("Plugin widget " + shell.pluginId + " failed: " + comp.errorString())
    }
    if (comp.status === Component.Loading) comp.statusChanged.connect(finalize)
    else finalize()
  }

  // As Bar.qml's ModuleSlot.injectProps does, once the item exists.
  function inject() {
    var target = slot.item
    if (!target) return
    if ("bar" in target) target.bar = api
    if ("moduleName" in target) target.moduleName = shell.pluginId
    if ("settings" in target) target.settings = ({})
  }

  PanelWindow {
    id: barWindow
    anchors {
      top: true
      left: true
      right: true
    }
    implicitHeight: Style.bar.sizeHorizontal
    color: Commons.Color.bar.background
    WlrLayershell.namespace: "omarchy-bar"

    Loader {
      id: slot
      anchors.right: parent.right
      anchors.rightMargin: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      sourceComponent: shell.widgetComponent
      onItemChanged: Qt.callLater(shell.inject)
    }
  }

  // ------------------------------------------------------ test hooks

  // The popup the widget makes, and the Flickable of its rows (the first one
  // below the popup's content; the recording's text field has one too).
  function findPanel(w) {
    for (var i = 0; i < w.data.length; i++) {
      var o = w.data[i]
      if (o && o.fittedContentWidth !== undefined) return o
    }
    return null
  }

  function findList(items) {
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it.interactive !== undefined && it.contentHeight !== undefined && it.boundsBehavior !== undefined) return it
      var inner = findList(it.children)
      if (inner) return inner
    }
    return null
  }

  function measure() {
    var w = shell.widget
    if (!w) return { loaded: false }
    var panel = shell.findPanel(w)
    var list = panel ? shell.findList(panel.contentItem) : null
    return {
      loaded: true,
      opened: w.opened,
      running: w.running,
      page: w.page,
      pid: w.kyrr ? w.kyrr.pid : -1,
      rows: w.rows.length,
      rowIds: w.rows.map(function(row) { return row.id || "" }),
      title: w.view.title,
      panel: panel ? {
        visible: panel.visible,
        contentWidth: panel.contentWidth,
        contentHeight: panel.contentHeight,
        screenW: panel.screenW,
        screenH: panel.screenH,
        x: panel.cardOrigin.x,
        y: panel.cardOrigin.y,
        availableCardHeight: panel.availableCardHeight
      } : null,
      list: list ? {
        interactive: list.interactive,
        contentHeight: list.contentHeight,
        height: list.height,
        room: list.room
      } : null
    }
  }

  IpcHandler {
    target: "kyrrtest"

    function metrics(): string { return JSON.stringify(shell.measure()) }

    // Goes to a page the way a click on a row does.
    function page(name: string): void {
      var w = shell.widget
      if (!w) return
      w.stack = ["main"]
      w.cursors = ({})
      if (name !== "main") w.openPage(name)
    }

    // Presses the row with this id, as Enter or a click would.
    function activate(id: string): string {
      var w = shell.widget
      if (!w) return "no widget"
      for (var i = 0; i < w.rows.length; i++) {
        if (w.rows[i].id === id) {
          w.activate(i)
          return "ok"
        }
      }
      return "no row " + id
    }
  }
}
