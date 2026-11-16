import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Register, edit, disable and remove cameras, and find new ones on the LAN.
// Passwords go from the field straight to reolink-cli's stdin and are cleared after use.
Column {
  id: root

  required property var service
  required property var translations
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color urgent: Color.urgent
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  // Moves keyboard focus back to the panel when a field gives it up.
  signal doneEditing()

  property string formMode: ""      // "", "add" or "edit"
  property string confirmRemove: ""

  spacing: Style.space(8)

  function tr(key, fallback) { return translations.t(key, fallback) }

  function message(text) {
    var s = String(text || "")
    return /^[a-z]+\.[a-zA-Z]+$/.test(s) ? tr(s, s) : s
  }

  // "Front Door" -> "front-door"
  function slug(text) {
    return String(text || "").toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)
  }

  function openForm(mode, values) {
    formMode = mode
    confirmRemove = ""
    service.setStatus("", false)
    nameField.text = values.name || ""
    addressField.text = values.address || ""
    userField.text = values.user || "admin"
    passwordField.text = ""
    descriptionField.text = values.description || ""
    Qt.callLater(function () { (mode === "edit" ? passwordField : nameField).forceActiveFocus() })
  }

  function closeForm() {
    formMode = ""
    passwordField.text = ""
    doneEditing()
  }

  function save() {
    service.saveCamera({
      mode: formMode,
      name: nameField.text,
      address: addressField.text,
      user: userField.text,
      password: passwordField.text,
      description: descriptionField.text
    })
    passwordField.text = ""
  }

  Connections {
    target: root.service
    function onRegistryChanged() {
      if (root.formMode !== "") root.closeForm()
      if (root.service.discovered.length > 0) root.service.discover()
    }
  }

  // Registered cameras
  PanelSectionHeader {
    text: root.tr("manage.header", "CAMERAS")
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    textFormat: Text.PlainText
    visible: root.service.devices.length === 0
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.tr("manage.empty", "No cameras registered yet. Search your network or add one by its IP address.")
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.service.devices
    RowLayout {
      id: deviceRow
      required property var modelData
      width: root.width
      spacing: Style.space(6)

      Column {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: deviceRow.modelData.name
          color: deviceRow.modelData.disabled ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: [
            deviceRow.modelData.disabled ? root.tr("manage.disabled", "Disabled") : "",
            deviceRow.modelData.description,
            deviceRow.modelData.host !== "" ? deviceRow.modelData.host : deviceRow.modelData.uid !== "" ? "UID " + deviceRow.modelData.uid : ""
          ].filter(function (x) { return x !== "" }).join("  ·  ")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Button {
        visible: deviceRow.modelData.usable
        text: root.tr("manage.edit", "Edit")
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openForm("edit", {
          name: deviceRow.modelData.name,
          address: deviceRow.modelData.host !== "" ? deviceRow.modelData.host : deviceRow.modelData.uid,
          user: deviceRow.modelData.user,
          description: deviceRow.modelData.description
        })
      }
      Button {
        visible: deviceRow.modelData.usable
        text: deviceRow.modelData.disabled ? root.tr("manage.enable", "Enable") : root.tr("manage.disable", "Disable")
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.service.setDisabled(deviceRow.modelData.name, !deviceRow.modelData.disabled)
      }
      Button {
        visible: deviceRow.modelData.usable
        readonly property bool confirming: root.confirmRemove === deviceRow.modelData.name
        text: confirming ? root.tr("manage.confirmRemove", "Remove?") : root.tr("manage.remove", "Remove")
        bordered: true
        foreground: confirming ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          if (!confirming) { root.confirmRemove = deviceRow.modelData.name; confirmReset.restart(); return }
          root.confirmRemove = ""
          root.service.removeCamera(deviceRow.modelData.name)
        }
      }
    }
  }

  Timer {
    id: confirmReset
    interval: 4000
    onTriggered: root.confirmRemove = ""
  }

  RowLayout {
    width: parent.width
    spacing: Style.space(6)
    Button {
      text: root.tr("manage.add", "+ Add camera")
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.openForm("add", {})
    }
    Button {
      text: root.service.discovering ? root.tr("manage.searching", "Searching…") : root.tr("manage.search", "Search network")
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.service.discover()
    }
    Item { Layout.fillWidth: true }
  }

  // Found on the network
  Column {
    visible: root.service.discoverDone && root.formMode === ""
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      text: root.tr("manage.found", "FOUND ON YOUR NETWORK")
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      textFormat: Text.PlainText
      visible: root.service.discovered.length === 0
      width: parent.width
      wrapMode: Text.WordWrap
      text: root.tr("manage.noneFound", "No camera answered. Battery cameras only answer while awake, cameras behind a Home Hub or NVR do not answer at all, and a firewall can block the replies. You can still add a camera by its IP address.")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: root.service.discovered
      RowLayout {
        id: foundRow
        required property var modelData
        width: root.width
        spacing: Style.space(6)
        Column {
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: foundRow.modelData.name !== "" ? foundRow.modelData.name : foundRow.modelData.host
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: [foundRow.modelData.model, foundRow.modelData.host, foundRow.modelData.uid !== "" ? "UID " + foundRow.modelData.uid : ""]
              .filter(function (x) { return x !== "" }).join("  ·  ")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Button {
          text: foundRow.modelData.registered ? root.tr("manage.registered", "Added") : root.tr("manage.addFound", "Add")
          bordered: !foundRow.modelData.registered
          foreground: foundRow.modelData.registered ? root.dim : root.foreground
          fontFamily: root.fontFamily
          onClicked: if (!foundRow.modelData.registered) root.openForm("add", {
            name: root.slug(foundRow.modelData.name) || root.slug(foundRow.modelData.model) || "camera",
            address: foundRow.modelData.host !== "" ? foundRow.modelData.host : foundRow.modelData.uid,
            description: foundRow.modelData.model
          })
        }
      }
    }
  }

  // Add / edit form
  Column {
    visible: root.formMode !== ""
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      text: root.formMode === "edit" ? root.tr("manage.editHeader", "EDIT CAMERA") : root.tr("manage.addHeader", "ADD CAMERA")
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    GridLayout {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(10)
      rowSpacing: Style.space(6)

      FieldLabel { text: root.tr("manage.name", "Name") }
      TextField {
        id: nameField
        Layout.fillWidth: true
        readOnly: root.formMode === "edit"
        placeholderText: root.tr("manage.namePlaceholder", "e.g. front-door")
        maximumLength: 64
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.formMode === "edit" ? root.dim : root.foreground
        KeyNavigation.tab: addressField
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.closeForm()
      }

      FieldLabel { text: root.tr("manage.address", "Address") }
      TextField {
        id: addressField
        Layout.fillWidth: true
        placeholderText: root.tr("manage.addressPlaceholder", "IP address, IP:port or UID")
        maximumLength: 260
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        KeyNavigation.tab: userField
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.closeForm()
      }

      FieldLabel { text: root.tr("manage.user", "User") }
      TextField {
        id: userField
        Layout.fillWidth: true
        maximumLength: 64
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        KeyNavigation.tab: passwordField
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.closeForm()
      }

      FieldLabel { text: root.tr("manage.password", "Password") }
      TextField {
        id: passwordField
        Layout.fillWidth: true
        password: true
        placeholderText: root.formMode === "edit" ? root.tr("manage.passwordKeep", "Leave empty to keep the current one") : ""
        maximumLength: 128
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        KeyNavigation.tab: descriptionField
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.closeForm()
      }

      FieldLabel { text: root.tr("manage.description", "Description") }
      TextField {
        id: descriptionField
        Layout.fillWidth: true
        placeholderText: root.tr("manage.descriptionPlaceholder", "Optional")
        maximumLength: 120
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        KeyNavigation.tab: nameField
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.closeForm()
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      Button {
        text: root.service.saving ? root.tr("manage.checking", "Checking…") : root.tr("manage.save", "Check and save")
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (!root.service.saving) root.save()
      }
      Button {
        text: root.tr("manage.cancel", "Cancel")
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.closeForm()
      }
      Item { Layout.fillWidth: true }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: root.tr("manage.passwordNote", "The password is checked with a login, then stored encrypted by reolink-cli. Reolink Live never keeps it.")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: text !== ""
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.message(root.service.manageStatus)
    color: root.service.manageOk ? root.dim : root.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.alignment: Qt.AlignVCenter
  }
}
