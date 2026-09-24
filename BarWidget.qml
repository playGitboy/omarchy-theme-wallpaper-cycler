import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omacycle bar widget: one icon in the bar, one settings panel.
//
// Everything stateful lives in Service.qml (inventory, cycling, GlobalShortcuts,
// bindings.lua manager). This file is a per-monitor view: it reads the service
// through `bar.shell.serviceFor()` and writes user choices back with
// `service.setSetting()`, so no decision is duplicated per screen.
//
// Colours come from the active bar and qs.Commons tokens (`Color.popups`,
// `Style`, `Border`), so the panel follows the current theme automatically.
Panel {
  id: root
  moduleName: Model.PLUGIN_ID
  // The service owns the single IpcHandler for this target.
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool serviceReady: service !== null
  // A bar facade's foreground is optimized for the bar surface, not the
  // popup card. Prefer the popup text token and fall back to a mathematically
  // contrast-safe black/white color when a theme's tokens disagree.
  readonly property color popupBackground: Color.popups.background
  readonly property color foreground: Model.readableTextColor(
    root.popupBackground,
    [Color.popups.text, Color.foreground, bar ? bar.barForeground : Color.foreground],
    4.5)
  readonly property color accent: Color.accent
  readonly property color dim: Model.readableTextColor(
    root.popupBackground,
    [Qt.darker(root.foreground, 1.55), root.foreground],
    3.0)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Read through the service when present, otherwise fall back to the injected
  // shell.json entry so the panel still renders a coherent default.
  readonly property string themeMode: root.serviceReady ? service.themeMode : setting("themeMode", Model.DEFAULT_THEME_MODE)
  readonly property string wallpaperScope: root.serviceReady ? service.wallpaperScope : setting("wallpaperScope", Model.DEFAULT_WALLPAPER_SCOPE)
  readonly property bool wallpaperRandom: root.serviceReady ? root.service.wallpaperRandom === true : setting("wallpaperRandom", Model.DEFAULT_WALLPAPER_RANDOM) === true
  readonly property bool autoWallpaper: root.serviceReady ? root.service.autoWallpaper === true : setting("autoWallpaper", Model.DEFAULT_AUTO_WALLPAPER) === true
  readonly property int autoWallpaperMinutes: root.serviceReady ? root.service.autoWallpaperMinutes : Number(setting("autoWallpaperMinutes", Model.DEFAULT_AUTO_WALLPAPER_MINUTES))
  readonly property string barSection: root.serviceReady ? String(root.service.barSection || "") : ""
  // Mirrors the switcher track width ToggleSwitch derives from the theme, so
  // the overlaid minute input clears the switch on every spacing scale.
  readonly property real switchTrackWidth: Math.round(Math.max(22, Math.round(Style.spacing.controlHeight * 0.55)) * 1.9)
  readonly property real autoSwitchReserve: Style.spacing.rowPaddingX + switchTrackWidth + Style.space(6)

  readonly property string currentThemeLabel: {
    var themes = root.serviceReady ? service.themes : []
    for (var i = 0; i < themes.length; i++) {
      if (themes[i].slug === root.service.currentThemeSlug) return themes[i].name
    }
    return root.serviceReady && root.service.currentThemeSlug !== "" ? Model.prettyName(root.service.currentThemeSlug) : "Unknown"
  }
  readonly property string currentWallpaperLabel: {
    var path = root.serviceReady ? root.service.currentBackgroundPath : ""
    return path === "" ? "Unknown" : Model.baseName(path)
  }
  readonly property int themeCount: root.serviceReady ? service.themeCount : 0
  readonly property int currentCount: root.serviceReady ? service.currentBackgroundCount : 0
  readonly property int allCount: root.serviceReady ? service.allBackgroundCount : 0

  readonly property var conflicts: root.serviceReady ? service.bindsConflicts : []
  readonly property bool bindsInstalled: root.serviceReady && service.bindsInstalled
  readonly property bool bindsLive: root.serviceReady && service.bindsLiveAny
  readonly property bool bindsMalformed: root.serviceReady && service.bindsMalformed
  readonly property bool bindsBusy: root.serviceReady && service.bindsBusy

  // Flat keyboard cursor: 0 placement, 1 theme mode, 2 wallpaper scope,
  // 3 random, 4 automatic wallpaper, 5 shortcut setup. h/l changes the
  // focused control; Enter activates it.
  property int cursor: 0
  readonly property int cursorMax: 5

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function clampCursor() {
    if (cursor < 0) cursor = 0
    if (cursor > cursorMax) cursor = cursorMax
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(cursorMax, cursor + (delta < 0 ? -1 : 1)))
  }

  // Keep the focused control inside the scroll viewport on shorter screens.
  function controlForCursor(index) {
    if (index === 0) return bgBarPosition
    if (index === 1) return bgThemeMode
    if (index === 2) return bgWallpaperScope
    if (index === 3) return toggleRandom
    if (index === 4) return autoToggle
    return bindsButton
  }

  function ensureCursorVisible() {
    var item = controlForCursor(root.cursor)
    if (!item || !scroller) return
    var pad = Style.space(10)
    var y = item.mapToItem(column, 0, 0).y
    if (y - pad < scroller.contentY) {
      scroller.contentY = Math.max(0, y - pad)
    } else if (y + item.height + pad > scroller.contentY + scroller.height) {
      scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, y + item.height + pad - scroller.height))
    }
  }

  onCursorChanged: Qt.callLater(ensureCursorVisible)

  function moveCursorH(delta) {
    var step = delta < 0 ? -1 : 1
    if (cursor === 0) {
      var sections = Model.BAR_SECTIONS
      var index = sections.indexOf(root.barSection)
      if (index < 0) index = 0
      root.moveBar(sections[(index + step + sections.length) % sections.length])
    } else if (cursor === 1) {
      root.setThemeMode(root.themeMode === "sequential" ? "random" : "sequential")
    } else if (cursor === 2) {
      root.setWallpaperScope(root.wallpaperScope === "current" ? "all" : "current")
    } else if (cursor === 3) {
      root.toggleWallpaperRandom()
    } else if (cursor === 4) {
      root.toggleAutoWallpaper()
    }
  }

  function activateCursor() {
    if (cursor === 3) root.toggleWallpaperRandom()
    else if (cursor === 4) root.toggleAutoWallpaper()
    else if (cursor === 5) root.primaryBindsAction()
  }

  function moveBar(section) {
    if (root.serviceReady) root.service.moveBar(section)
  }

  function setThemeMode(value) {
    if (root.serviceReady) root.service.setSetting("themeMode", value)
  }

  function setWallpaperScope(value) {
    if (root.serviceReady) root.service.setSetting("wallpaperScope", value)
  }

  function toggleWallpaperRandom() {
    if (root.serviceReady) root.service.setSetting("wallpaperRandom", !root.wallpaperRandom)
  }

  function toggleAutoWallpaper() {
    if (root.serviceReady) root.service.setSetting("autoWallpaper", !root.autoWallpaper)
  }

  function setAutoWallpaperMinutes(value) {
    if (root.serviceReady) root.service.setSetting("autoWallpaperMinutes", value)
  }

  function conflictActions() {
    var out = []
    for (var i = 0; i < root.conflicts.length; i++) out.push(String(root.conflicts[i].action))
    return out
  }

  // One button that matches the current setup state.
  function bindsButtonLabel() {
    if (root.bindsBusy) return "Working…"
    if (root.bindsInstalled) return "Remove shortcuts"
    if (root.conflicts.length > 0) return "Enable & take over"
    return "Enable shortcuts"
  }

  function primaryBindsAction() {
    if (!root.serviceReady || root.bindsBusy) return
    if (root.bindsInstalled) root.service.removeBinds()
    else root.service.installBinds(root.conflictActions())
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    tooltipText: root.serviceReady
      ? ("Theme: " + root.currentThemeLabel + " · Wallpaper: " + root.currentWallpaperLabel + "\nClick for theme & wallpaper cycling")
      : "Omacycle — enabling…"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && root.serviceReady) root.service.cycleWallpaper(1)
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "t") root.setThemeMode(root.themeMode === "sequential" ? "random" : "sequential")
        else if (key === "w") root.setWallpaperScope(root.wallpaperScope === "current" ? "all" : "current")
        else if (key === "r") root.toggleWallpaperRandom()
        else if (key === "a") root.toggleAutoWallpaper()
        else if (key === "e") root.primaryBindsAction()
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(9)

          // ---------- hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰏘"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Omacycle"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.serviceReady
                  ? (root.currentThemeLabel + " · " + root.currentWallpaperLabel)
                  : "Starting up…"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- bar placement ----------
          Column {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "BAR POSITION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: bgBarPosition
              x: Style.space(2)
              width: parent.width - Style.space(4)
              focusable: false
              cursorIndex: root.cursor === 0 && root.barSection !== "" ? Model.BAR_SECTIONS.indexOf(root.barSection) : -1
              foreground: root.foreground
              accent: root.accent
              options: [
                { value: "left", label: "Left" },
                { value: "center", label: "Center" },
                { value: "right", label: "Right" }
              ]
              value: root.barSection
              onChanged: function(value) { root.moveBar(value) }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- theme switching ----------
          Column {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "THEME SWITCHING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: bgThemeMode
              x: Style.space(2)
              width: parent.width - Style.space(4)
              focusable: false
              cursorIndex: root.cursor === 1 ? (root.themeMode === "sequential" ? 0 : 1) : -1
              foreground: root.foreground
              accent: root.accent
              options: [
                { value: "sequential", label: "Sequential" },
                { value: "random", label: "Random" }
              ]
              value: root.themeMode
              onChanged: function(value) { root.setThemeMode(value) }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- wallpaper switching ----------
          Column {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "WALLPAPER SWITCHING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: bgWallpaperScope
              x: Style.space(2)
              width: parent.width - Style.space(4)
              focusable: false
              cursorIndex: root.cursor === 2 ? (root.wallpaperScope === "current" ? 0 : 1) : -1
              foreground: root.foreground
              accent: root.accent
              options: [
                { value: "current", label: "Current theme" },
                { value: "all", label: "All themes" }
              ]
              value: root.wallpaperScope
              onChanged: function(value) { root.setWallpaperScope(value) }
            }

            Toggle {
              id: toggleRandom
              x: Style.space(2)
              width: parent.width - Style.space(4)
              height: Style.space(36)
              hasCursor: root.cursor === 3
              checked: root.wallpaperRandom
              label: "Random"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.toggleWallpaperRandom()
            }

            // Same full-width bordered row as Random, with the minute input
            // overlaid just left of the switch so both rows share identical
            // left and right edges.
            Toggle {
              id: autoToggle
              x: Style.space(2)
              width: parent.width - Style.space(4)
              height: Style.space(36)
              hasCursor: root.cursor === 4
              checked: root.autoWallpaper
              label: "Auto switch"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.toggleAutoWallpaper()

              Row {
                id: autoMinutesRow
                z: 2
                visible: root.autoWallpaper
                anchors.right: parent.right
                anchors.rightMargin: root.autoSwitchReserve
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.controlHeight
                spacing: Style.space(4)

                NumberField {
                  id: autoMinutes
                  label: ""
                  value: root.autoWallpaperMinutes
                  from: Model.MIN_AUTO_WALLPAPER_MINUTES
                  to: Model.MAX_AUTO_WALLPAPER_MINUTES
                  stepSize: 1
                  fieldWidth: Style.space(60)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  z: 1
                  onModified: root.setAutoWallpaperMinutes(value)
                }

                Text {
                  text: "min"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  height: parent.height
                  z: 1
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // Only the empty gap is a shield. Keep the actual NumberField
              // above it so keyboard editing and mouse interaction work.
              MouseArea {
                z: 1
                anchors.left: parent.left
                anchors.right: autoMinutesRow.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                acceptedButtons: Qt.AllButtons
                propagateComposedEvents: false
                onPressed: mouse => mouse.accepted = true
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- shortcuts ----------
          Column {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "SHORTCUTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Conflicts the user must consciously resolve.
            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.conflicts.length > 0

              Repeater {
                model: root.conflicts
                delegate: Text {
                  required property var modelData
                  text: "· " + modelData.pretty + " is taken by “" + modelData.owner + "”. Enabling takes it over" + (modelData.alternate ? " (fallback " + modelData.alternate + ")." : ".")
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            Text {
              visible: root.bindsMalformed
              text: "bindings.lua has an unbalanced marker block. Repair it by hand, then reopen this panel."
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Button {
              id: bindsButton
              x: Style.space(2)
              width: parent.width - Style.space(4)
              focusable: false
              hasCursor: root.cursor === 5
              bordered: true
              text: root.bindsButtonLabel()
              enabled: root.serviceReady && !root.bindsBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.cursor = 5
                root.primaryBindsAction()
              }
            }

            Text {
              visible: root.bindsInstalled && !root.bindsLive
              text: "Written to bindings.lua. If Hyprland has not picked them up, run `hyprctl reload`."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Text {
              visible: root.serviceReady && !!root.service.lastMessage
              text: root.serviceReady ? String(root.service.lastMessage) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          PanelSeparator { foreground: root.foreground }

          Text {
            text: "Super+Ctrl+←/→ wallpaper · Super+Ctrl+Shift+←/→ theme"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }
        }
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      root.cursor = 0
      clampCursor()
      if (root.serviceReady) root.service.refreshInventory()
    }
  }
}
