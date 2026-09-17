import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sexy Screenshot: camera on the bar, a popup of stock Omarchy capture
// commands. Right-click shoots immediately; the panel closes before grim
// so the popup is not in the freeze.
Panel {
  id: root
  moduleName: "unicadesign.sexy-screenshot"
  ipcTarget: "unicadesign.sexy-screenshot"
  manageIpc: false

  property bool recording: false
  property string recordingKind: "idle"
  property bool hasWebcam: false
  property string pendingCommand: ""
  property int cursorIndex: -1
  property bool cursorActive: false
  property bool cursorFromPointer: false

  readonly property string pinnedScriptPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/unicadesign.sexy-screenshot/scripts/pinned-window-record"
  readonly property string pinnedStartCommand: "\"" + pinnedScriptPath + "\""
  readonly property string pinnedStopCommand: "\"" + pinnedScriptPath + "\" --stop"
  readonly property string stopCommand: pinnedStopCommand + "; omarchy-capture-screenrecording --stop-recording >/dev/null 2>&1 || true"

  readonly property bool primaryInstance: {
    var w = root.QsWindow.window
    var screens = Quickshell.screens
    if (!w || !w.screen || screens.length === 0) return true
    return String(w.screen.name) === String(screens[0].name)
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property var screenshotCommands: ({
    "smart": "omarchy-capture-screenshot",
    "region": "omarchy-capture-screenshot region",
    "windows": "omarchy-capture-screenshot windows",
    "fullscreen": "omarchy-capture-screenshot fullscreen",
    "copy": "omarchy-capture-screenshot smart copy",
    "save": "omarchy-capture-screenshot fullscreen save"
  })

  readonly property var recordCommands: ({
    "region": "omarchy-capture-screenrecording",
    "fullscreen": "omarchy-capture-screenrecording --fullscreen",
    "desktop-audio": "omarchy-capture-screenrecording --with-desktop-audio",
    "microphone": "omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio",
    "webcam": "omarchy-capture-screenrecording-with-webcam"
  })

  readonly property var actions: {
    var list = [
      { section: "SCREENSHOT", id: "smart", icon: "", label: "Smart capture", hint: "1", command: screenshotCommands.smart },
      { section: "SCREENSHOT", id: "region", icon: "󰒉", label: "Region", hint: "2", command: screenshotCommands.region },
      { section: "SCREENSHOT", id: "windows", icon: "󰖲", label: "Window", hint: "3", command: screenshotCommands.windows },
      { section: "SCREENSHOT", id: "fullscreen", icon: "󰹑", label: "Fullscreen", hint: "4", command: screenshotCommands.fullscreen },
      { section: "SCREENSHOT", id: "copy", icon: "󰅍", label: "Copy only", hint: "y", command: screenshotCommands.copy },
      { section: "SCREENSHOT", id: "save", icon: "󰉉", label: "Save to disk", hint: "s", command: screenshotCommands.save },
      { section: "MORE", id: "text", icon: "󰴑", label: "Extract text", hint: "t", command: "omarchy-capture-text" },
      { section: "MORE", id: "qr", icon: "󰐲", label: "QR code", hint: "q", command: "omarchy-capture-qr" },
      { section: "MORE", id: "color", icon: "󰃉", label: "Color picker", hint: "p", command: "pkill hyprpicker || hyprpicker -a" }
    ]
    if (recording) {
      list.push({ section: "RECORD", id: "stop", icon: "󰓛", label: recordingKind === "pinned" ? "Stop pinned recording" : "Stop recording", hint: "r", command: stopCommand })
    } else {
      list.push({ section: "RECORD", id: "record-region", icon: "", label: "Record region", hint: "r", command: recordCommands.region })
      list.push({ section: "RECORD", id: "record-full", icon: "󰹑", label: "Record fullscreen", hint: "f", command: recordCommands.fullscreen })
      list.push({ section: "RECORD", id: "record-pinned", icon: "󰖲", label: "Pin window + desktop audio", hint: "w", command: pinnedStartCommand })
      list.push({ section: "RECORD", id: "record-desktop", icon: "", label: "With desktop audio", hint: "", command: recordCommands["desktop-audio"] })
      list.push({ section: "RECORD", id: "record-mic", icon: "󰍬", label: "With desktop + mic", hint: "", command: recordCommands.microphone })
      if (hasWebcam)
        list.push({ section: "RECORD", id: "record-webcam", icon: "󰄀", label: "With webcam", hint: "", command: recordCommands.webcam })
    }
    return list
  }

  function sectionFor(index) {
    if (index < 0 || index >= actions.length) return ""
    if (index === 0) return actions[0].section
    if (actions[index].section !== actions[index - 1].section) return actions[index].section
    return ""
  }

  function launch(command) {
    if (!command) return
    // Classic KMS recording would otherwise start beside a pinned portal
    // capture. Stop pinned first when the user asks for a live-screen record.
    if (command.indexOf("omarchy-capture-screenrecording") === 0 && command.indexOf("--stop-recording") < 0)
      command = pinnedStopCommand + " >/dev/null 2>&1 || true; " + command
    pendingCommand = command
    if (opened) {
      close()
      captureTimer.interval = Math.min(1000, Math.max(100, Number(setting("closeDelayMs", 300)) || 300))
      captureTimer.restart()
      return
    }
    if (root.bar) root.bar.run(command)
    pendingCommand = ""
    recordPollTimer.restart()
  }

  function runIndex(index) {
    if (index < 0 || index >= actions.length) return
    launch(actions[index].command)
  }

  function runHint(key) {
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].hint === key) {
        runIndex(i)
        return true
      }
    }
    return false
  }

  function screenshot(mode) {
    var key = String(mode || "smart").trim()
    if (key === "") key = "smart"
    var command = screenshotCommands[key]
    if (!command) return "error: unknown mode: " + key
    launch(command)
    return "ok"
  }

  function record(mode) {
    if (recording) {
      launch(stopCommand)
      return "ok"
    }
    var key = String(mode || "region").trim()
    if (key === "" || key === "region") key = "region"
    if (key === "pinned" || key === "window") {
      launch(pinnedStartCommand)
      return "ok"
    }
    var command = recordCommands[key]
    if (!command) return "error: unknown mode: " + key
    launch(command)
    return "ok"
  }

  function moveCursor(dy) {
    if (actions.length === 0) return
    cursorActive = true
    cursorFromPointer = false
    if (cursorIndex < 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(actions.length - 1, cursorIndex + dy))
  }

  function refreshRecording() {
    if (statusProc.running) return
    statusProc.running = true
  }

  function refreshWebcam() {
    if (webcamProc.running) return
    webcamProc.running = true
  }

  Component.onCompleted: {
    refreshRecording()
    refreshWebcam()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = -1
      cursorFromPointer = false
      refreshRecording()
      refreshWebcam()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  onRecordingChanged: {
    if (cursorIndex >= actions.length) cursorIndex = actions.length - 1
  }

  IpcHandler {
    enabled: root.primaryInstance
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function capture(): string { return root.screenshot("smart") }
    function screenshot(mode: string): string { return root.screenshot(mode) }
    function record(mode: string): string { return root.record(mode) }
    function stop(): string {
      root.launch(root.stopCommand)
      return "ok"
    }
    function status(): string { return root.recordingKind || (root.recording ? "recording" : "idle") }
  }

  Process {
    id: statusProc
    command: [root.pinnedScriptPath, "--status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: {
      var s = String(statusOut.text || "").trim()
      if (s === "") s = "idle"
      root.recordingKind = s
      root.recording = (s === "pinned" || s === "classic")
    }
  }

  Process {
    id: webcamProc
    command: ["omarchy-hw-webcam"]
    onExited: function(exitCode) {
      root.hasWebcam = exitCode === 0
    }
  }

  Timer {
    id: recordPollTimer
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshRecording()
  }

  Timer {
    id: captureTimer
    interval: 300
    onTriggered: {
      if (root.bar && root.pendingCommand !== "") root.bar.run(root.pendingCommand)
      root.pendingCommand = ""
      recordPollTimer.restart()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? "󰻂" : ""
    active: root.recording
    tooltipText: root.recordingKind === "pinned"
      ? "Pinned window recording — switch workspaces freely, Stop in the panel"
      : (root.recording
        ? "Recording — click for options, click Stop in the panel"
        : "Screenshot — click for options, right-click to capture")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        var mode = String(root.setting("rightClickAction", "smart") || "smart")
        root.screenshot(mode)
      } else if (buttonCode === Qt.MiddleButton) {
        root.screenshot("fullscreen")
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: {
        if (root.cursorActive && root.cursorIndex >= 0) root.runIndex(root.cursorIndex)
      }
      onTextKey: function(t) {
        if (root.runHint(t)) return
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.actions

          delegate: Column {
            id: block
            required property int index
            required property var modelData
            readonly property string headerText: root.sectionFor(index)
            width: column.width
            spacing: Style.space(2)

            PanelSectionHeader {
              visible: block.headerText !== ""
              width: column.width
              text: block.headerText
              foreground: root.foreground
              fontFamily: root.fontFamily
              topPadding: block.index === 0 ? 0 : Style.space(6)
            }

            CursorSurface {
              id: row
              width: column.width
              height: Style.space(34)
              foreground: root.foreground
              hasCursor: root.cursorActive && root.cursorIndex === block.index
              current: block.modelData.id === "stop"

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runIndex(block.index)
                onContainsMouseChanged: {
                  if (containsMouse) {
                    root.cursorActive = true
                    root.cursorIndex = block.index
                    root.cursorFromPointer = true
                  } else if (root.cursorFromPointer && root.cursorIndex === block.index) {
                    root.cursorActive = false
                    root.cursorIndex = -1
                    root.cursorFromPointer = false
                  }
                }
              }

              Text {
                id: rowIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: block.modelData.icon
                color: block.modelData.id === "stop"
                  ? (root.bar ? root.bar.urgent : Color.urgent)
                  : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: rowHint.visible ? rowHint.left : parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: block.modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: rowHint
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                visible: String(block.modelData.hint || "") !== ""
                text: block.modelData.hint
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
