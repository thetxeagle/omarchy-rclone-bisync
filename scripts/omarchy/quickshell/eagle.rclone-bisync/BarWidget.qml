import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "eagle.rclone-bisync"
  ipcTarget: "eagle.rclone-bisync"

  readonly property string statusScript: Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, "")
  property var syncStatus: ({
    timer: "unknown",
    service: "unknown",
    logPath: "",
    journalUnit: "google-drive-bisync.service",
    lastLogTime: "",
    lastSuccess: "",
    errors: [],
    warnings: [],
    conflicts: [],
    pairs: [],
    timers: []
  })

  readonly property var watchedTimers: setting("watchedTimers", []) instanceof Array
    ? setting("watchedTimers", []) : []
  readonly property bool timerSelectionConfigured: setting("watchTimersConfigured", false) === true
  property bool showingSettings: false

  readonly property bool healthy: syncStatus.timer === "active" && syncStatus.service !== "failed"
  readonly property bool running: syncStatus.service === "active"
  readonly property var watchedTimerRows: syncStatus.timers.filter(function(row) { return row.watched })
  readonly property int syncingCount: watchedTimerRows.filter(function(row) { return row.status === "SYNCING" }).length
  readonly property int failedCount: watchedTimerRows.filter(function(row) { return row.status === "FAILED" }).length
  readonly property string icon: syncStatus.service === "failed" ? "" : (running ? "󰑐" : (healthy ? "󰄬" : "󰅙"))
  readonly property color foregroundColor: "#cacccc"
  readonly property color urgentColor: "#a55555"
  readonly property string fontFamily: "monospace"
  readonly property color iconColor: syncStatus.service === "failed" ? root.urgentColor : (healthy ? root.foregroundColor : "#888888")

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function persistWatchedTimers(next) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.watchedTimers = next
    entry.watchTimersConfigured = true
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    Qt.callLater(root.refresh)
  }

  function toggleWatched(timer, checked) {
    var next = root.watchedTimers.slice()
    var index = next.indexOf(timer)
    if (checked && index < 0) next.push(timer)
    else if (!checked && index >= 0) next.splice(index, 1)
    root.persistWatchedTimers(next)
  }

  function openLog() {
    if (root.bar && syncStatus.logPath) root.bar.run("omarchy-launch-editor " + Util.shellQuote(syncStatus.logPath))
  }

  function openJournal() {
    Quickshell.execDetached(["omarchy", "launch", "tui", "journalctl", "--user", "-u", syncStatus.journalUnit, "-n", "240", "--no-pager"])
  }

  function askAgent() {
    var prompt = "Review the Google Drive rclone bisync status. Read " + syncStatus.logPath
      + " and the recent journal for " + syncStatus.journalUnit
      + ". Explain failures, warnings, duplicate objects, or conflicts in plain language."
      + " Do not modify files, restart services, delete locks, or run rclone commands."
    Quickshell.execDetached(["omarchy", "agent", "prompt", prompt])
  }

  function setTimer(action) {
    var timer = root.syncStatus.timers.length > 0 ? root.syncStatus.timers[0].timer : "google-drive-bisync.timer"
    Quickshell.execDetached(["systemctl", "--user", action, timer])
    refreshTimer.restart()
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["python3", root.statusScript, JSON.stringify({
      timers: root.watchedTimers,
      configured: root.timerSelectionConfigured
    })]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.syncStatus = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.iconColor
    slotSize: Style.bar.iconSlot
    tooltipText: "Rclone bisync: " + root.syncStatus.service
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      Text {
        text: "Rclone Bisync"
        color: root.foregroundColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        text: root.failedCount > 0
          ? root.failedCount + " timer" + (root.failedCount === 1 ? "" : "s") + " failed"
          : (root.syncingCount > 0
            ? root.syncingCount + " timer" + (root.syncingCount === 1 ? " is" : "s are") + " syncing"
            : "All watched timers healthy")
        color: root.iconColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: root.syncStatus.lastLogTime !== ""
        text: "Last log activity: " + root.syncStatus.lastLogTime
        color: Qt.darker(root.foregroundColor, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.foregroundColor }

      Text {
        text: "Timer status"
        color: root.foregroundColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Repeater {
        model: root.watchedTimerRows
        delegate: RowLayout {
          width: column.width
          Text {
            Layout.fillWidth: true
            text: modelData.timer
            color: root.foregroundColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            text: modelData.status
            color: modelData.status === "FAILED" ? root.urgentColor
              : (modelData.status === "SYNCING" ? "#d6b85a" : root.foregroundColor)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Text {
        text: "Google Drive pairs"
        color: root.foregroundColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Repeater {
        model: root.syncStatus.pairs
        delegate: RowLayout {
          width: column.width
          Text {
            Layout.fillWidth: true
            text: modelData.name
            color: root.foregroundColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            text: modelData.state
            color: modelData.state === "failed" ? root.urgentColor : (modelData.state === "ok" ? root.foregroundColor : "#888888")
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        visible: root.syncStatus.errors.length > 0
        text: "Recent errors: " + root.syncStatus.errors.length
        color: root.urgentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.syncStatus.warnings.length > 0
        text: "Warnings: " + root.syncStatus.warnings.length
        color: "#888888"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { visible: root.syncStatus.conflicts.length > 0; foreground: root.foregroundColor }

      Text {
        visible: root.syncStatus.conflicts.length > 0
        text: "Conflicts: " + root.syncStatus.conflicts.length
        color: root.urgentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Repeater {
        model: root.syncStatus.conflicts
        delegate: Text {
          width: column.width
          text: modelData.drive + " · " + modelData.detail
          color: root.foregroundColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      RowLayout {
        width: column.width
        Button { text: "Refresh"; onClicked: root.refresh() }
        Button { text: "Open log"; onClicked: root.openLog() }
        Button { text: "Journal"; onClicked: root.openJournal() }
      }

      PanelSeparator { foreground: root.foregroundColor }

      RowLayout {
        width: column.width
        Text {
          Layout.fillWidth: true
          text: "Watched timers"
          color: root.foregroundColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Button {
          text: root.showingSettings ? "Hide settings" : "Settings"
          onClicked: root.showingSettings = !root.showingSettings
        }
      }

      Text {
        visible: root.showingSettings && root.syncStatus.timers.length === 0
        text: "No active rclone or bisync user timers found."
        color: "#888888"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        visible: root.showingSettings
        model: root.syncStatus.timers
        delegate: Toggle {
          width: column.width
          label: modelData.timer
          description: modelData.service + " · " + modelData.status + " · result " + modelData.result
          foreground: root.foregroundColor
          accent: root.foregroundColor
          checked: modelData.watched
          onClicked: root.toggleWatched(modelData.timer, !modelData.watched)
        }
      }

      RowLayout {
        width: column.width
        Button { text: "Ask default agent"; onClicked: root.askAgent() }
        Button {
          text: root.syncStatus.timer === "active" ? "Stop timer" : "Start timer"
          onClicked: root.setTimer(root.syncStatus.timer === "active" ? "stop" : "start")
        }
      }
    }
  }
}
