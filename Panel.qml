import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.opteon-sdc.reolink"
  ipcTarget: "reolink"

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // Resolved here: inside an inline component `Color` does not reach the qs.Commons singleton.
  readonly property color accentColor: Color.accent
  readonly property color panelBackground: Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int fps: Math.max(1, Math.min(15, Number(setting("fps", 8)) || 8))
  readonly property int panelWidth: Math.max(420, Math.min(1400, Number(setting("panelWidth", 640)) || 640))
  property string stream: String(setting("stream", "sub")) === "main" ? "main" : "sub"
  property int speed: 24
  property bool namingPreset: false
  property string pendingCamera: ""
  property bool managing: false
  // When a manage request arrived; it only applies to a panel that opens right after it.
  property real manageRequestedAt: 0
  // With nothing registered, camera management is all the panel can offer.
  readonly property bool showManager: managing || (svc.loaded && svc.devices.length === 0 && svc.gatewayUp)

  readonly property string glyphCamera: String.fromCodePoint(0xF07AE)   // nf-md-cctv
  readonly property string glyphSnap: String.fromCodePoint(0xF0100)     // nf-md-camera
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)  // nf-md-refresh
  readonly property string glyphClose: String.fromCodePoint(0xF0156)    // nf-md-close
  readonly property string glyphManage: String.fromCodePoint(0xF0493)   // nf-md-cog
  readonly property string glyphBell: String.fromCodePoint(0xF009A)     // nf-md-bell
  readonly property string glyphBellOff: String.fromCodePoint(0xF009B)  // nf-md-bell_off

  readonly property bool currentMuted: events !== null && currentCamera !== null && events.mutedCameras.indexOf(currentCamera.name) >= 0

  // The shared event service (manifest kind "service"). The shell may create it
  // after this widget, and serviceFor() is not a binding, so look until it is there.
  property var events: null
  function findEvents() {
    if (!events && bar && bar.shell && typeof bar.shell.serviceFor === "function")
      events = bar.shell.serviceFor(moduleName) || null
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.events === null
    triggeredOnStart: true
    onTriggered: root.findEvents()
  }
  readonly property int unseen: events ? events.unseen : 0
  readonly property int maxListedEvents: 8

  function tr(key, fallback) { return strings.t(key, fallback) }

  // Status keys from the service are translated; anything else is a device message shown as-is.
  function message(text) {
    var s = String(text || "")
    return /^[a-z]+\.[a-zA-Z]+$/.test(s) ? tr(s, s) : s
  }

  function selectDefaultCamera() {
    var list = svc.cameras
    if (list.length === 0) { svc.camera = ""; return }
    // A notification click may ask for a camera before the list has loaded.
    if (pendingCamera !== "") {
      var asked = pendingCamera
      pendingCamera = ""
      for (var k = 0; k < list.length; k++) if (list[k].name === asked) { svc.camera = asked; return }
    }
    for (var i = 0; i < list.length; i++) if (list[i].name === svc.camera) return
    var wanted = String(setting("defaultCamera", ""))
    for (var j = 0; j < list.length; j++) if (list[j].name === wanted) { svc.camera = wanted; return }
    svc.camera = list[0].name
  }

  function cycleCamera(step) {
    var list = svc.cameras
    if (list.length < 2) return
    var at = 0
    for (var i = 0; i < list.length; i++) if (list[i].name === svc.camera) at = i
    svc.camera = list[(at + step + list.length) % list.length].name
  }

  readonly property var currentCamera: {
    for (var i = 0; i < svc.cameras.length; i++) if (svc.cameras[i].name === svc.camera) return svc.cameras[i]
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      svc.lastError = ""
      namingPreset = false
      managing = Date.now() - manageRequestedAt < 3000
      manageRequestedAt = 0
      svc.refresh()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
      if (events) events.markSeen()
    } else {
      svc.stopNow()
    }
  }

  // A notification click asks for a camera.
  Connections {
    target: root.events
    ignoreUnknownSignals: true
    function onFocusSerialChanged() {
      root.pendingCamera = root.events.focusCamera
      root.selectDefaultCamera()
    }
    function onManageSerialChanged() {
      if (root.opened) root.managing = true
      else root.manageRequestedAt = Date.now()
    }
  }

  function showCamera(camera) {
    for (var i = 0; i < svc.cameras.length; i++)
      if (svc.cameras[i].name === camera) { svc.camera = camera; return }
  }

  function eventTime(ms) {
    var d = new Date(ms)
    var today = new Date()
    var time = Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat))
    return d.toDateString() === today.toDateString() ? time : Qt.formatDate(d, Qt.locale().dateFormat(Locale.ShortFormat)) + " " + time
  }

  Service {
    id: svc
    settings: root.settings
    onCamerasChanged: root.selectDefaultCamera()
    // The event service maps event hosts to camera names from the same registry.
    onRegistryChanged: if (root.events && root.events.lookupCameras) root.events.lookupCameras()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphCamera
    labelText: root.unseen > 0 ? (root.unseen > 99 ? "99+" : String(root.unseen)) : ""
    fixedWidth: root.unseen > 0 ? -1 : button.slotSize
    active: root.unseen > 0
    tooltipText: root.unseen > 0 ? root.tr("events.unseen", "New camera events") : ""
    onPressed: function (b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(1000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) {
        if (root.showManager) return
        if (!svc.ptzSupported) { if (dx !== 0) root.cycleCamera(dx); return }
        var h = dx < 0 ? "left" : dx > 0 ? "right" : ""
        var v = dy < 0 ? "up" : dy > 0 ? "down" : ""
        svc.nudge(h !== "" && v !== "" ? h + "-" + v : (h || v), root.speed)
      }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") svc.refresh()
        else if (root.showManager) return
        else if (key === "s") svc.snapshot("main")
        else if (key === "m") root.stream = root.stream === "main" ? "sub" : "main"
        else if (key === "c") root.cycleCamera(1)
        else if (key >= "1" && key <= "9") {
          var p = svc.presets[Number(key) - 1]
          if (p) svc.gotoPreset(p.id)
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height && !svc.moving
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

          // Header: camera name, details, actions
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: root.showManager ? root.tr("action.manage", "Manage cameras")
                  : root.currentCamera ? root.currentCamera.name : root.tr("title", "Reolink cameras")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: root.currentCamera && !root.showManager
                  ? [root.currentCamera.description, root.currentCamera.host].filter(function (x) { return x !== "" }).join("  ·  ")
                  : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            ButtonGroup {
              visible: root.currentCamera !== null && !root.showManager
              options: [
                { value: "sub", label: root.tr("stream.sub", "Sub") },
                { value: "main", label: root.tr("stream.main", "Main") }
              ]
              value: root.stream
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              onChanged: function (v) { root.stream = v }
            }

            PanelActionButton {
              visible: root.currentCamera !== null && !root.showManager
                && root.events !== null && root.events.enabled && root.events.notify
              iconText: root.currentMuted ? root.glyphBellOff : root.glyphBell
              tooltipText: root.currentMuted
                ? root.tr("action.unmute", "Notifications for this camera are off. Click to turn them on.")
                : root.tr("action.mute", "Turn off notifications for this camera")
              foreground: root.currentMuted ? root.dim : root.foreground
              fontFamily: root.fontFamily
              onClicked: root.events.setMuted(root.currentCamera.name, !root.currentMuted)
            }

            PanelActionButton {
              visible: root.currentCamera !== null && !root.showManager
              iconText: root.glyphSnap
              tooltipText: root.tr("action.snapshot", "Save snapshot (S)")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: svc.snapshot("main")
            }

            PanelActionButton {
              iconText: root.glyphRefresh
              tooltipText: root.tr("action.refresh", "Refresh (R)")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: { svc.refresh(); live.reload() }
            }

            PanelActionButton {
              iconText: root.glyphManage
              tooltipText: root.tr("action.manage", "Manage cameras")
              foreground: root.showManager ? root.accentColor : root.foreground
              fontFamily: root.fontFamily
              onClicked: { root.managing = !root.managing; keyCatcher.forceActiveFocus() }
            }
          }

          CameraManager {
            visible: root.showManager
            width: parent.width
            service: svc
            translations: strings
            foreground: root.foreground
            dim: root.dim
            urgent: root.urgent
            accent: root.accentColor
            fontFamily: root.fontFamily
            onDoneEditing: keyCatcher.forceActiveFocus()
          }

          // Camera picker
          Flow {
            visible: svc.cameras.length > 1 && !root.showManager
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: svc.cameras
              Button {
                required property var modelData
                text: modelData.name
                selected: modelData.name === svc.camera
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: svc.camera = modelData.name
              }
            }
          }

          // Gateway down
          Column {
            visible: svc.gatewayChecked && !svc.gatewayUp
            width: parent.width
            spacing: Style.space(6)
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.tr("gateway.down", "The reolink-cli gateway is not running.")
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Button {
              text: svc.status === "gateway.starting" ? root.tr("gateway.starting", "Starting…") : root.tr("gateway.start", "Start gateway")
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: svc.startGateway()
            }
          }

          // Video
          Rectangle {
            visible: root.currentCamera !== null && !root.showManager
            width: parent.width
            height: Math.round(width * 9 / 16)
            color: "black"
            radius: Style.space(6)
            clip: true

            LiveView {
              id: live
              anchors.fill: parent
              cli: svc.cli
              camera: svc.camera
              stream: root.stream
              fps: root.fps
              active: root.opened && svc.camera !== "" && svc.gatewayUp && !root.showManager
            }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - Style.space(32)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              visible: !live.hasFrame
              text: live.error !== "" ? root.message(live.error)
                : !svc.gatewayUp ? ""
                : root.tr("stream.connecting", "Connecting…")
              color: live.error !== "" ? root.urgent : "#bbbbbb"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Button {
              visible: live.error !== ""
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(16)
              text: root.tr("stream.retry", "Retry")
              bordered: true
              foreground: "#dddddd"
              fontFamily: root.fontFamily
              onClicked: live.reload()
            }
          }

          // PTZ
          Column {
            visible: svc.ptzSupported && root.currentCamera !== null && !root.showManager
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.tr("ptz.header", "PAN / TILT")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(16)

              Grid {
                id: pad
                Layout.alignment: Qt.AlignTop
                columns: 3
                spacing: Style.space(6)
                readonly property real keySize: Style.space(40)
                PadKey { dir: "left-up"; glyph: "↖" }
                PadKey { dir: "up"; glyph: "↑" }
                PadKey { dir: "right-up"; glyph: "↗" }
                PadKey { dir: "left"; glyph: "←" }
                PadKey { dir: ""; glyph: "■" }
                PadKey { dir: "right"; glyph: "→" }
                PadKey { dir: "left-down"; glyph: "↙" }
                PadKey { dir: "down"; glyph: "↓" }
                PadKey { dir: "right-down"; glyph: "↘" }
              }

              Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Style.space(8)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    text: root.tr("ptz.speed", "Speed")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  PanelSlider {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(20)
                    bar: root.bar
                    minimum: 1
                    maximum: 64
                    step: 1
                    integer: true
                    value: root.speed
                    onMoved: function (v) { root.speed = Math.round(v) }
                    onReleased: function (v) { root.speed = Math.round(v) }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: String(root.speed)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    Layout.preferredWidth: Style.space(18)
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("ptz.presets", "Presets")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  textFormat: Text.PlainText
                  visible: svc.presets.length === 0
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.tr("ptz.noPresets", "No presets yet. Aim the camera and save the position.")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: svc.presets
                    Row {
                      required property var modelData
                      required property int index
                      spacing: 0
                      Button {
                        text: (index < 9 ? (index + 1) + "  " : "") + modelData.name
                        bordered: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        tooltipText: root.tr("ptz.goto", "Go to this position")
                        onClicked: svc.gotoPreset(modelData.id)
                      }
                      PanelActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconText: root.glyphClose
                        fontSize: Style.font.bodySmall
                        tooltipText: root.tr("ptz.delete", "Delete preset")
                        foreground: root.dim
                        hoverColor: root.urgent
                        fontFamily: root.fontFamily
                        onClicked: svc.deletePreset(modelData.id)
                      }
                    }
                  }
                }

                Button {
                  visible: !root.namingPreset
                  text: root.tr("ptz.save", "+ Save current position")
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    root.namingPreset = true
                    presetName.clear()
                    Qt.callLater(function () { presetName.forceActiveFocus() })
                  }
                }

                RowLayout {
                  visible: root.namingPreset
                  width: parent.width
                  spacing: Style.space(6)
                  TextField {
                    id: presetName
                    Layout.fillWidth: true
                    placeholderText: root.tr("ptz.namePlaceholder", "Name, e.g. Door")
                    maximumLength: 31
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    foreground: root.foreground
                    Keys.onReturnPressed: saveBtn.clicked()
                    Keys.onEnterPressed: saveBtn.clicked()
                    Keys.onEscapePressed: { root.namingPreset = false; keyCatcher.forceActiveFocus() }
                  }
                  Button {
                    id: saveBtn
                    text: root.tr("ptz.saveConfirm", "Save")
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: {
                      svc.savePreset(presetName.text)
                      root.namingPreset = false
                      keyCatcher.forceActiveFocus()
                    }
                  }
                }
              }
            }
          }

          // Recent events
          Column {
            visible: root.events !== null && root.events.enabled && !root.showManager
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                Layout.fillWidth: true
                text: root.tr("events.header", "EVENTS")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Button {
                visible: root.events !== null && root.events.events.length > 0
                text: root.tr("events.clear", "Clear")
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.events.clear()
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.events !== null && root.events.events.length === 0
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.events && !root.events.streaming && root.events.streamError !== ""
                ? root.events.streamError
                : root.tr("events.none", "No events yet. Motion and detections from every camera show up here.")
              color: root.events && !root.events.streaming && root.events.streamError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.events ? root.events.events.slice(0, root.maxListedEvents) : []
              Rectangle {
                id: eventRow
                required property var modelData
                width: parent.width
                height: Style.space(30)
                radius: Style.space(6)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                  eventMouse.containsMouse ? 0.12 : modelData.camera === svc.camera ? 0.06 : 0)

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)
                  Text {
                    textFormat: Text.PlainText
                    text: root.events.glyph(eventRow.modelData.type)
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    Layout.preferredWidth: Style.space(18)
                  }
                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.events.label(eventRow.modelData.type)
                      + (eventRow.modelData.count > 1 ? " ×" + eventRow.modelData.count : "")
                      + "  ·  " + eventRow.modelData.camera
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.eventTime(eventRow.modelData.time)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: eventMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCamera(eventRow.modelData.camera)
                }
              }
            }
          }

          // Errors and empty states
          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: svc.lastError !== "" ? root.message(svc.lastError)
              : svc.loaded && svc.cameras.length === 0 && svc.devices.length > 0 && svc.gatewayUp
                ? root.tr("empty", "No enabled cameras. Enable one under Manage cameras.")
                : ""
            color: svc.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.currentCamera !== null && !root.showManager
            text: svc.ptzSupported
              ? root.tr("hint.ptz", "Hold an arrow to move · arrow keys nudge · 1–9 presets · S snapshot · M stream · C camera")
              : root.tr("hint.basic", "S snapshot · M stream · C next camera · R refresh")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component PadKey: Rectangle {
    id: key
    property string dir: ""
    property string glyph: ""
    // Lit while pressed and for as long as the camera is still moving this way.
    readonly property bool held: dir !== "" && (mouse.pressed || (svc.moving && svc.direction_ === dir))
    property bool flash: false
    width: pad.keySize
    height: pad.keySize
    radius: Style.space(8)
    color: held || flash ? root.accentColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, mouse.containsMouse ? 0.16 : 0.08)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: key.glyph
      color: key.held || key.flash ? root.panelBackground : root.foreground
      font.family: root.fontFamily
      font.pixelSize: key.dir === "" ? Style.font.bodySmall : Style.font.iconLarge
    }

    Timer {
      id: flashTimer
      interval: 400
      onTriggered: key.flash = false
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      onPressed: {
        if (key.dir !== "") svc.move(key.dir, root.speed)
        else { svc.forceStop(); key.flash = true; flashTimer.restart() }
      }
      onReleased: if (key.dir !== "") svc.stop()
      onCanceled: if (key.dir !== "") svc.stop()
    }
  }
}
