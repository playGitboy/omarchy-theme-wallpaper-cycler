import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// Omacycle service.
//
// One process-wide instance owns everything that must exist exactly once:
// the four GlobalShortcuts, the theme/background inventory, the cycling
// decision, the bindings.lua manager, and the IPC surface. The bar widget
// (BarWidget.qml) is a thin per-monitor view over this service, so a four-key
// shortcut set is never registered once per screen.
//
// All inventory data comes from bin/theme-cycler and is parsed defensively by
// Model.parseInventory. Decisions live in Model.js; this file only wires
// inputs, processes, persistence and lifecycle.
Item {
  id: root
  visible: false

  // Injected by the shell for third-party service entry points.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : Model.PLUGIN_ID
  // Omarchy strips __sourceDir from third-party manifests; fall back to the
  // directory this file was loaded from.
  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return url.replace(/\/+$/, "")
  }
  readonly property string helperPath: pluginDir + "/bin/theme-cycler"
  // Resolve through PATH so the plugin also works on non-Arch Omarchy hosts.
  readonly property string pythonPath: "python3"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string shellConfigPath: configHome + "/omarchy/shell.json"

  // ---- settings -----------------------------------------------------------
  // Single source of truth for the three user options. Persisted on the
  // plugin's own shell.json entry (bar layout entry when the widget is on the
  // bar, plugins[] entry otherwise) through the scoped shell API.
  property var settings: Model.normalizeSettings({})
  property var settingsEntry: ({})
  readonly property string themeMode: settings.themeMode
  readonly property string wallpaperScope: settings.wallpaperScope
  readonly property bool wallpaperRandom: settings.wallpaperRandom
  property string barSection: ""

  // ---- inventory ----------------------------------------------------------
  property var inventory: Model.parseInventory("")
  readonly property var themes: inventory.themes
  readonly property string currentThemeSlug: inventory.currentTheme
  readonly property string currentBackgroundPath: inventory.currentBackground
  readonly property var inventoryCounts: Model.scopeCounts(inventory, settings)
  readonly property int themeCount: themes.length
  readonly property int allBackgroundCount: inventoryCounts.all
  readonly property int currentBackgroundCount: inventoryCounts.current
  property double inventoryAt: 0
  property bool inventoryBusy: false
  property string pendingKind: ""
  property int pendingDirection: 0

  // ---- bindings -----------------------------------------------------------
  property var bindsStatus: ({})
  readonly property bool bindsInstalled: bindsStatus.installed === true
  readonly property var bindsConflicts: Array.isArray(bindsStatus.conflicts) ? bindsStatus.conflicts : []
  readonly property var bindsLive: (bindsStatus.live && typeof bindsStatus.live === "object") ? bindsStatus.live : ({})
  readonly property bool bindsLiveAny: {
    for (var action in bindsLive) if (bindsLive[action] === true) return true
    return false
  }
  readonly property bool bindsMalformed: Array.isArray(bindsStatus.malformed) && bindsStatus.malformed.length > 0
  property string lastMessage: ""

  signal bindsChanged()
  signal message(string text)

  function notify(text) {
    root.lastMessage = String(text || "")
    root.message(root.lastMessage)
  }

  Component.onCompleted: {
    root.refreshInventory()
    root.refreshBindStatus()
  }

  // ---- shell.json read (settings + bar placement) -------------------------
  FileView {
    id: shellConfigView
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellConfig(text())
    onLoadFailed: root.applyShellConfig("")
    onFileChanged: reload()
  }

  function findEntry(config) {
    var found = { entry: null, section: "" }
    if (!config || typeof config !== "object") return found
    var sections = Model.BAR_SECTIONS
    var layout = config.bar && config.bar.layout ? config.bar.layout : {}
    for (var s = 0; s < sections.length; s++) {
      var rows = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] && String(rows[i].id) === root.pluginId) {
          found.entry = rows[i]
          found.section = sections[s]
          return found
        }
      }
    }
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var p = 0; p < plugins.length; p++) {
      if (plugins[p] && String(plugins[p].id) === root.pluginId) {
        found.entry = plugins[p]
        return found
      }
    }
    return found
  }

  function applyShellConfig(raw) {
    var config = null
    try { config = JSON.parse(String(raw || "")) } catch (error) { config = null }
    var found = root.findEntry(config)
    root.settingsEntry = found.entry || ({})
    root.settings = Model.normalizeSettings(found.entry)
    root.barSection = found.section
  }

  // ---- settings writes ----------------------------------------------------
  function setSetting(name, value) {
    if (name !== "themeMode" && name !== "wallpaperScope" && name !== "wallpaperRandom") return false
    var current = {
      themeMode: root.settings.themeMode,
      wallpaperScope: root.settings.wallpaperScope,
      wallpaperRandom: root.settings.wallpaperRandom
    }
    current[name] = value
    var entry = Model.settingsEntry(root.settingsEntry, current)
    root.settingsEntry = entry
    root.settings = Model.normalizeSettings(entry)
    if (root.shell && typeof root.shell.updateEntryInline === "function") {
      root.shell.updateEntryInline(root.pluginId, entry)
      return true
    }
    return false
  }

  // ---- bar placement ------------------------------------------------------
  function moveBar(section) {
    if (Model.BAR_SECTIONS.indexOf(section) < 0) return
    Quickshell.execDetached(["omarchy", "bar", "move", root.pluginId, "--section", section])
    root.notify("Bar icon moved to " + section)
    placementRefresh.restart()
  }

  // ---- inventory process --------------------------------------------------
  function refreshInventory() {
    if (inventoryProcess.running) {
      root.pendingRefresh = true
      return
    }
    root.inventoryBusy = true
    inventoryProcess.command = [root.pythonPath, root.helperPath, "inventory"]
    inventoryProcess.running = true
  }
  property bool pendingRefresh: false

  Process {
    id: inventoryProcess
    running: false
    stdout: StdioCollector { id: inventoryOut; waitForEnd: true }
    onExited: function(code) {
      root.inventoryBusy = false
      if (code === 0) {
        var next = Model.parseInventory(String(inventoryOut.text || "").slice(0, 4 * 1024 * 1024))
        root.inventory = next
        root.inventoryAt = Date.now()
      } else if (root.themes.length === 0) {
        root.notify("Could not read the theme inventory")
      }
      if (root.pendingRefresh) { root.pendingRefresh = false; root.refreshInventory() }
      if (root.pendingKind !== "") {
        var kind = root.pendingKind
        var direction = root.pendingDirection
        root.pendingKind = ""
        root.pendingDirection = 0
        root.performCycle(kind, direction)
      }
    }
  }

  // ---- cycling ------------------------------------------------------------
  function ensureInventoryThen(kind, direction) {
    var stale = root.themes.length === 0 || (Date.now() - root.inventoryAt) > 2000
    if (stale) {
      root.pendingKind = kind
      root.pendingDirection = direction
      root.refreshInventory()
    } else {
      root.performCycle(kind, direction)
    }
  }

  function cycleTheme(direction) { root.ensureInventoryThen("theme", direction) }
  function cycleWallpaper(direction) { root.ensureInventoryThen("wallpaper", direction) }

  function performCycle(kind, direction) {
    var step = Number(direction) < 0 ? -1 : 1
    if (kind === "theme") {
      var slug = Model.decideTheme(root.inventory, root.settings, step)
      if (!slug) { root.notify("No themes available"); return }
      if (slug === root.currentThemeSlug) { root.notify("That is the only theme"); return }
      var label = slug
      for (var t = 0; t < root.themes.length; t++) if (root.themes[t].slug === slug) label = root.themes[t].name
      root.notify("Theme: " + label)
      Quickshell.execDetached(["omarchy", "theme", "set", slug])
      var optimistic = {}
      for (var key in root.inventory) optimistic[key] = root.inventory[key]
      optimistic.currentTheme = slug
      root.inventory = optimistic
    } else {
      var path = Model.decideBackground(root.inventory, root.settings, step)
      if (!path) { root.notify("No wallpapers available in this scope"); return }
      if (path === root.currentBackgroundPath) { root.notify("That is the only wallpaper"); return }
      root.notify("Wallpaper: " + Model.baseName(path))
      Quickshell.execDetached(["omarchy", "theme", "bg", "set", path])
      var optimisticBackground = {}
      for (var bgKey in root.inventory) optimisticBackground[bgKey] = root.inventory[bgKey]
      optimisticBackground.currentBackground = path
      root.inventory = optimisticBackground
    }
    inventoryRefreshDelay.restart()
  }

  Timer {
    id: inventoryRefreshDelay
    interval: 1800
    repeat: false
    onTriggered: root.refreshInventory()
  }

  Timer {
    id: placementRefresh
    interval: 1200
    repeat: false
    onTriggered: shellConfigView.reload()
  }

  Timer {
    interval: 300000
    repeat: true
    running: true
    onTriggered: root.refreshInventory()
  }

  // ---- bindings manager ---------------------------------------------------
  // Serialize binds operations: the panel can request an install while a
  // status refresh is still in flight, so every job goes through one queue.
  property var bindsQueue: []
  readonly property bool bindsBusy: bindsProcess.running || bindsQueue.length > 0

  function enqueueBinds(mode, command) {
    root.bindsQueue = root.bindsQueue.concat([{ mode: mode, command: command }])
    root.pumpBinds()
  }

  function pumpBinds() {
    if (bindsProcess.running || root.bindsQueue.length === 0) return
    var job = root.bindsQueue[0]
    root.bindsQueue = root.bindsQueue.slice(1)
    bindsProcess.mode = job.mode
    bindsProcess.command = job.command
    bindsProcess.running = true
  }

  function refreshBindStatus() {
    root.enqueueBinds("status", [root.pythonPath, root.helperPath, "binds", "status", "--json"])
  }

  function installBinds(actions) {
    var argv = [root.pythonPath, root.helperPath, "binds", "install", "--json"]
    var list = Array.isArray(actions) ? actions : []
    for (var i = 0; i < list.length; i++) argv.push("--replace", String(list[i]))
    root.enqueueBinds("install", argv)
  }

  function removeBinds() {
    root.enqueueBinds("remove", [root.pythonPath, root.helperPath, "binds", "remove", "--json"])
  }

  function conflictActions() {
    var out = []
    for (var i = 0; i < root.bindsConflicts.length; i++) out.push(String(root.bindsConflicts[i].action))
    return out
  }

  Process {
    id: bindsProcess
    property string mode: "status"
    running: false
    stdout: StdioCollector { id: bindsOut; waitForEnd: true }
    onExited: function(code) {
      var data = null
      try { data = JSON.parse(String(bindsOut.text || "").slice(0, 65536)) } catch (error) { data = null }
      var mode = bindsProcess.mode
      if (mode === "status" && data && typeof data === "object") root.bindsStatus = data
      if (mode === "install") {
        if (data && data.status === "ok") root.notify("Shortcuts enabled")
        else if (data && Array.isArray(data.conflicts) && data.conflicts.length > 0) root.notify("Some shortcuts are still in use")
        else root.notify("Could not enable shortcuts")
      } else if (mode === "remove") {
        root.notify("Shortcuts removed")
      }
      root.bindsChanged()
      if (mode !== "status") root.refreshBindStatus()
      Qt.callLater(root.pumpBinds)
    }
  }

  // ---- global shortcuts ---------------------------------------------------
  GlobalShortcut { appid: root.pluginId; name: "theme-prev"; description: Model.SHORTCUTS[0].label; onPressed: root.cycleTheme(-1) }
  GlobalShortcut { appid: root.pluginId; name: "theme-next"; description: Model.SHORTCUTS[1].label; onPressed: root.cycleTheme(1) }
  GlobalShortcut { appid: root.pluginId; name: "wallpaper-prev"; description: Model.SHORTCUTS[2].label; onPressed: root.cycleWallpaper(-1) }
  GlobalShortcut { appid: root.pluginId; name: "wallpaper-next"; description: Model.SHORTCUTS[3].label; onPressed: root.cycleWallpaper(1) }

  // ---- IPC ----------------------------------------------------------------
  IpcHandler {
    target: root.pluginId

    function themeNext(): string { root.cycleTheme(1); return "ok" }
    function themePrev(): string { root.cycleTheme(-1); return "ok" }
    function wallpaperNext(): string { root.cycleWallpaper(1); return "ok" }
    function wallpaperPrev(): string { root.cycleWallpaper(-1); return "ok" }
    function refresh(): string { root.refreshInventory(); root.refreshBindStatus(); return "ok" }
    function enableKeybindings(): string { root.installBinds(root.conflictActions()); return "ok" }
    function disableKeybindings(): string { root.removeBinds(); return "ok" }
    function setSetting(name: string, value: string): string {
      return root.setSetting(String(name), String(value)) ? "ok" : "rejected"
    }
    function status(): string {
      return JSON.stringify({
        pluginId: root.pluginId,
        themeMode: root.themeMode,
        wallpaperScope: root.wallpaperScope,
        wallpaperRandom: root.wallpaperRandom,
        themeCount: root.themeCount,
        currentTheme: root.currentThemeSlug,
        currentBackground: root.currentBackgroundPath,
        bindsInstalled: root.bindsInstalled,
        lastMessage: root.lastMessage
      })
    }
  }
}
