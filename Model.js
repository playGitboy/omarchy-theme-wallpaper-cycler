// Theme Wallpaper Cycler — pure decision model.
//
// QML imports this module; Node tests require() it. There is no I/O, no QML
// object, no Hyprland and no process here: every function is a deterministic
// transform of its arguments so the cycling rules can be unit-tested with
// fictional inventories. All inventory data arrives from the Python helper and
// is treated as untrusted input (see parseInventory).

var PLUGIN_ID = "io.github.playgitboy.theme-wallpaper-cycler"

var THEME_MODES = ["sequential", "random"]
var WALLPAPER_SCOPES = ["current", "all"]

var DEFAULT_THEME_MODE = "sequential"
var DEFAULT_WALLPAPER_SCOPE = "current"
var DEFAULT_WALLPAPER_RANDOM = false

// The four global shortcuts the service registers and the bindings manager
// installs. `global` is the GlobalShortcut name; `action` is the binds action.
var SHORTCUTS = [
  { action: "theme-prev", global: "theme-prev", keys: "Super+Ctrl+Shift+Left", label: "Previous theme" },
  { action: "theme-next", global: "theme-next", keys: "Super+Ctrl+Shift+Right", label: "Next theme" },
  { action: "wallpaper-prev", global: "wallpaper-prev", keys: "Super+Ctrl+Left", label: "Previous wallpaper" },
  { action: "wallpaper-next", global: "wallpaper-next", keys: "Super+Ctrl+Right", label: "Next wallpaper" }
]

var BAR_SECTIONS = ["left", "center", "right"]

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function normalizeThemeMode(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return THEME_MODES.indexOf(text) >= 0 ? text : DEFAULT_THEME_MODE
}

function normalizeWallpaperScope(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return WALLPAPER_SCOPES.indexOf(text) >= 0 ? text : DEFAULT_WALLPAPER_SCOPE
}

function normalizeBool(value, fallback) {
  if (value === true || value === false) return value
  if (value === undefined || value === null) return fallback === true
  var text = String(value).trim().toLowerCase()
  if (text === "true" || text === "on" || text === "1" || text === "yes") return true
  if (text === "false" || text === "off" || text === "0" || text === "no") return false
  return fallback === true
}

// Read the three user settings out of a raw shell.json entry, clamping every
// field so a hand-edited value can never drive an unknown branch.
function normalizeSettings(entry) {
  var raw = isPlainObject(entry) ? entry : {}
  return {
    themeMode: normalizeThemeMode(raw.themeMode),
    wallpaperScope: normalizeWallpaperScope(raw.wallpaperScope),
    wallpaperRandom: normalizeBool(raw.wallpaperRandom, DEFAULT_WALLPAPER_RANDOM)
  }
}

// Build the entry that gets written back to shell.json: keep unknown keys the
// user or another tool may have added, overwrite only the three we own.
function settingsEntry(existing, settings) {
  var entry = { id: PLUGIN_ID }
  if (isPlainObject(existing)) {
    for (var key in existing) if (key !== "id") entry[key] = existing[key]
  }
  entry.themeMode = normalizeThemeMode(settings ? settings.themeMode : undefined)
  entry.wallpaperScope = normalizeWallpaperScope(settings ? settings.wallpaperScope : undefined)
  entry.wallpaperRandom = normalizeBool(settings ? settings.wallpaperRandom : undefined, DEFAULT_WALLPAPER_RANDOM)
  return entry
}

// "tokyo-night" -> "Tokyo Night", matching `omarchy theme list`.
function prettyName(slug) {
  var text = String(slug === undefined || slug === null ? "" : slug)
  return text.replace(/(^|-)([a-z])/g, function (match, lead, letter) {
    return lead + letter.toUpperCase()
  }).replace(/-/g, " ")
}

// ---- inventory -------------------------------------------------------------

function normalizeTheme(theme) {
  if (!isPlainObject(theme)) return null
  var slug = String(theme.slug === undefined || theme.slug === null ? "" : theme.slug).trim()
  if (!slug) return null
  var backgrounds = []
  var list = Array.isArray(theme.backgrounds) ? theme.backgrounds : []
  for (var i = 0; i < list.length; i++) {
    var path = String(list[i] === undefined || list[i] === null ? "" : list[i]).trim()
    if (path) backgrounds.push(path)
  }
  return {
    slug: slug,
    name: String(theme.name || prettyName(slug)),
    source: String(theme.source || ""),
    backgrounds: backgrounds
  }
}

// Parse the helper's JSON defensively. Anything malformed degrades to an empty
// inventory rather than throwing inside a QML binding.
function parseInventory(raw) {
  var data = raw
  if (typeof raw === "string") {
    try { data = JSON.parse(raw) } catch (error) { data = null }
  }
  var out = { themes: [], currentTheme: "", currentBackground: "", backgroundCount: 0 }
  if (!isPlainObject(data)) return out
  var themes = Array.isArray(data.themes) ? data.themes : []
  for (var i = 0; i < themes.length; i++) {
    var theme = normalizeTheme(themes[i])
    if (theme) out.themes.push(theme)
  }
  out.themes = sortThemes(out.themes)
  out.currentTheme = String(data.currentTheme === undefined || data.currentTheme === null ? "" : data.currentTheme).trim()
  out.currentBackground = String(data.currentBackground === undefined || data.currentBackground === null ? "" : data.currentBackground).trim()
  var count = 0
  for (var t = 0; t < out.themes.length; t++) count += out.themes[t].backgrounds.length
  out.backgroundCount = count
  return out
}

function sortThemes(themes) {
  var copy = Array.isArray(themes) ? themes.slice() : []
  copy.sort(function (a, b) {
    var left = a && a.slug ? String(a.slug) : ""
    var right = b && b.slug ? String(b.slug) : ""
    return left < right ? -1 : (left > right ? 1 : 0)
  })
  return copy
}

function themeIndex(themes, slug) {
  var want = String(slug === undefined || slug === null ? "" : slug)
  if (!want || !Array.isArray(themes)) return -1
  for (var i = 0; i < themes.length; i++) {
    if (themes[i] && String(themes[i].slug) === want) return i
  }
  return -1
}

function themeBySlug(themes, slug) {
  var index = themeIndex(themes, slug)
  return index >= 0 ? themes[index] : null
}

// Sequential theme step with wrap-around. An unknown current theme lands on the
// first entry going forward and the last going backward.
function nextTheme(themes, currentSlug, direction) {
  var list = sortThemes(themes)
  if (list.length === 0) return ""
  var step = Number(direction) < 0 ? -1 : 1
  var index = themeIndex(list, currentSlug)
  if (index < 0) return step > 0 ? list[0].slug : list[list.length - 1].slug
  return list[(index + step + list.length) % list.length].slug
}

// Random theme that is never the current one while another choice exists.
function randomTheme(themes, currentSlug, rng) {
  var list = sortThemes(themes)
  if (list.length === 0) return ""
  var current = String(currentSlug === undefined || currentSlug === null ? "" : currentSlug)
  var candidates = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].slug !== current) candidates.push(list[i].slug)
  }
  if (candidates.length === 0) candidates.push(list[0].slug)
  return candidates[pickIndex(candidates.length, rng)]
}

function pickIndex(length, rng) {
  var size = Math.floor(Number(length) || 0)
  if (size <= 0) return 0
  var value = typeof rng === "function" ? Number(rng()) : Math.random()
  if (!isFinite(value) || value < 0) value = 0
  if (value >= 1) value = 0.9999999999
  return Math.floor(value * size)
}

// ---- backgrounds -----------------------------------------------------------

// Flatten the inventory into the ordered wallpaper list a scope addresses.
// "current" is the active theme's backgrounds; "all" walks every installed
// theme in slug order and each theme's backgrounds in path order.
function flattenBackgrounds(themes, scope, currentThemeSlug) {
  var list = sortThemes(themes)
  var rows = []
  if (normalizeWallpaperScope(scope) === "current") {
    var theme = themeBySlug(list, currentThemeSlug)
    if (theme) {
      for (var i = 0; i < theme.backgrounds.length; i++) {
        rows.push({ theme: theme.slug, path: theme.backgrounds[i] })
      }
    }
    return rows
  }
  for (var t = 0; t < list.length; t++) {
    for (var b = 0; b < list[t].backgrounds.length; b++) {
      rows.push({ theme: list[t].slug, path: list[t].backgrounds[b] })
    }
  }
  return rows
}

function baseName(path) {
  var text = String(path === undefined || path === null ? "" : path)
  var slash = text.lastIndexOf("/")
  return slash >= 0 ? text.slice(slash + 1) : text
}

// Locate the current wallpaper in the flattened list. Real paths are compared
// first; a basename match is the fallback for the current theme's own
// backgrounds, whose symlinked state path can differ from the inventory path.
function backgroundIndex(rows, currentPath) {
  var want = String(currentPath === undefined || currentPath === null ? "" : currentPath)
  if (!want || !Array.isArray(rows)) return -1
  var i
  for (i = 0; i < rows.length; i++) if (rows[i] && rows[i].path === want) return i
  var wantBase = baseName(want)
  for (i = 0; i < rows.length; i++) {
    if (rows[i] && baseName(rows[i].path) === wantBase) return i
  }
  return -1
}

function nextBackground(rows, currentPath, direction) {
  if (!Array.isArray(rows) || rows.length === 0) return ""
  var step = Number(direction) < 0 ? -1 : 1
  var index = backgroundIndex(rows, currentPath)
  if (index < 0) return step > 0 ? rows[0].path : rows[rows.length - 1].path
  return rows[(index + step + rows.length) % rows.length].path
}

function randomBackground(rows, currentPath, rng) {
  if (!Array.isArray(rows) || rows.length === 0) return ""
  var current = String(currentPath === undefined || currentPath === null ? "" : currentPath)
  var candidates = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && rows[i].path !== current) candidates.push(rows[i].path)
  }
  if (candidates.length === 0) candidates.push(rows[0].path)
  return candidates[pickIndex(candidates.length, rng)]
}

// ---- one-shot decisions ----------------------------------------------------

function decideTheme(inventory, settings, direction, rng) {
  var inv = inventory && Array.isArray(inventory.themes) ? inventory : { themes: [], currentTheme: "" }
  var mode = normalizeThemeMode(settings ? settings.themeMode : undefined)
  if (mode === "random") return randomTheme(inv.themes, inv.currentTheme, rng)
  return nextTheme(inv.themes, inv.currentTheme, direction)
}

function decideBackground(inventory, settings, direction, rng) {
  var inv = inventory && Array.isArray(inventory.themes) ? inventory : { themes: [], currentTheme: "", currentBackground: "" }
  var rows = flattenBackgrounds(inv.themes, settings ? settings.wallpaperScope : undefined, inv.currentTheme)
  if (rows.length === 0) return ""
  if (normalizeBool(settings ? settings.wallpaperRandom : undefined, DEFAULT_WALLPAPER_RANDOM)) {
    return randomBackground(rows, inv.currentBackground, rng)
  }
  return nextBackground(rows, inv.currentBackground, direction)
}

function scopeCounts(inventory, settings) {
  var inv = inventory && Array.isArray(inventory.themes) ? inventory : { themes: [], currentTheme: "" }
  return {
    themes: inv.themes.length,
    current: flattenBackgrounds(inv.themes, "current", inv.currentTheme).length,
    all: flattenBackgrounds(inv.themes, "all", inv.currentTheme).length
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    THEME_MODES: THEME_MODES,
    WALLPAPER_SCOPES: WALLPAPER_SCOPES,
    DEFAULT_THEME_MODE: DEFAULT_THEME_MODE,
    DEFAULT_WALLPAPER_SCOPE: DEFAULT_WALLPAPER_SCOPE,
    DEFAULT_WALLPAPER_RANDOM: DEFAULT_WALLPAPER_RANDOM,
    SHORTCUTS: SHORTCUTS,
    BAR_SECTIONS: BAR_SECTIONS,
    isPlainObject: isPlainObject,
    normalizeThemeMode: normalizeThemeMode,
    normalizeWallpaperScope: normalizeWallpaperScope,
    normalizeBool: normalizeBool,
    normalizeSettings: normalizeSettings,
    settingsEntry: settingsEntry,
    prettyName: prettyName,
    parseInventory: parseInventory,
    sortThemes: sortThemes,
    themeIndex: themeIndex,
    themeBySlug: themeBySlug,
    nextTheme: nextTheme,
    randomTheme: randomTheme,
    flattenBackgrounds: flattenBackgrounds,
    baseName: baseName,
    backgroundIndex: backgroundIndex,
    nextBackground: nextBackground,
    randomBackground: randomBackground,
    decideTheme: decideTheme,
    decideBackground: decideBackground,
    scopeCounts: scopeCounts,
    pickIndex: pickIndex
  }
}
