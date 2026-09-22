import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Theme Wallpaper Cycler bar widget: one icon in the bar, one settings panel.
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
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Read through the service when present, otherwise fall back to the injected
  // shell.json entry so the panel still renders a coherent default.
  readonly property string themeMode: root.serviceReady ? service.themeMode : setting("themeMode", Model.DEFAULT_THEME_MODE)
  readonly property string wallpaperScope: root.serviceReady ? service.wallpaperScope : setting("wallpaperScope", Model.DEFAULT_WALLPAPER_SCOPE)
  readonly property bool wallpaperRandom: root.serviceReady ? service.wallpaperRandom === true : setting("wallpaperRandom", Model.DEFAULT_WALLPAPER_RANDOM) === true
  readonly property string barSection: root.serviceReady ? String(service.barSection || "") : ""

  readonly property string currentThemeLabel: {
    var themes = root.serviceReady ? service.themes : []
    for (var i = 0; i < themes.length; i++) {
      if (themes[i].slug === service.currentThemeSlug) return themes[i].name
    }
    return root.serviceReady && service.currentThemeSlug !== "" ? Model.prettyName(service.currentThemeSlug) : "Unknown"
  }
  readonly property string currentWallpaperLabel: {
    var path = root.serviceReady ? service.currentBackgroundPath : ""
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
  // 3 random, 4 shortcut setup. h/l changes the focused control; Enter
  // activates it.
  property int cursor: 0
  readonly property int cursorMax: 4

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
      scroller.contentY = Math.min(scroller.contentHeight - scroller.height, y + item.height + pad - scroller.height)
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
    }
  }

  function activateCursor() {
    if (cursor === 3) root.toggleWallpaperRandom()
    else if (cursor === 4) root.primaryBindsAction()
  }

  function moveBar(section) {
    if (root.serviceReady) service.moveBar(section)
  }

  function setThemeMode(value) {
    if (root.serviceReady) service.setSetting("themeMode", value)
  }

  function setWallpaperScope(value) {
    if (root.serviceReady) service.setSetting("wallpaperScope", value)
  }

  function toggleWallpaperRandom() {
    if (root.serviceReady) service.setSetting("wallpaperRandom", !root.wallpaperRandom)
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
      : "Theme Wallpaper Cycler — enabling…"
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
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
                text: "Theme & Wallpaper Cycler"
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
              width: parent.width
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
              width: parent.width
              focusable: false
              cursorIndex: root.cursor === 1 ? (root.themeMode === "sequential" ? 0 : 1) : -1
              foreground: root.foreground
              accent: root.accent
              options: [
                { value: "sequential", label: "Sequential (default)" },
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
              width: parent.width
              focusable: false
              cursorIndex: root.cursor === 2 ? (root.wallpaperScope === "current" ? 0 : 1) : -1
              foreground: root.foreground
              accent: root.accent
              options: [
                { value: "current", label: "Current theme (default)" },
                { value: "all", label: "All themes" }
              ]
              value: root.wallpaperScope
              onChanged: function(value) { root.setWallpaperScope(value) }
            }

            Toggle {
              id: toggleRandom
              width: parent.width
              hasCursor: root.cursor === 3
              checked: root.wallpaperRandom
              label: "Random"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.toggleWallpaperRandom()
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
                  width: column.width
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
              width: parent.width
              focusable: false
              hasCursor: root.cursor === 4
              bordered: true
              text: root.bindsButtonLabel()
              enabled: root.serviceReady && !root.bindsBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.cursor = 4
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
              visible: root.serviceReady && !!service.lastMessage
              text: root.serviceReady ? String(service.lastMessage) : ""
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
      if (root.serviceReady) service.refreshInventory()
    }
  }
}
