// Omacycle — pure decision model.
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
var DEFAULT_AUTO_WALLPAPER = false
var DEFAULT_AUTO_WALLPAPER_MINUTES = 30
var MIN_AUTO_WALLPAPER_MINUTES = 1
var MAX_AUTO_WALLPAPER_MINUTES = 10080

// Global shortcuts shared by the service and bindings manager. `global` is
// the GlobalShortcut name; `action` is the binds action.
var SHORTCUTS = [
  { action: "theme-prev", global: "theme-prev", keys: "Super+Ctrl+Shift+Left", label: "Previous theme" },
  { action: "theme-next", global: "theme-next", keys: "Super+Ctrl+Shift+Right", label: "Next theme" },
  { action: "wallpaper-prev", global: "wallpaper-prev", keys: "Super+Ctrl+Left", label: "Previous wallpaper" },
  { action: "wallpaper-next", global: "wallpaper-next", keys: "Super+Ctrl+Right", label: "Next wallpaper" },
  { action: "open-wallpaper-dir", global: "open-wallpaper-dir", keys: "Super+Ctrl+Up", label: "Open current wallpaper directory" }
]

var BAR_SECTIONS = ["left", "center", "right"]

var SIMPLIFIED_CHINESE = {
  "Unknown": "未知",
  "Working…": "处理中…",
  "Remove shortcuts": "移除快捷键",
  "Enable & take over": "启用并接管冲突键",
  "Enable shortcuts": "启用快捷键",
  "Theme: ": "主题：",
  " · Wallpaper: ": " · 壁纸：",
  "Click for theme & wallpaper cycling": "点击切换主题和壁纸",
  "Omacycle — enabling…": "Omacycle — 正在启动…",
  "Starting up…": "正在启动…",
  "BAR POSITION": "栏位置",
  "Left": "左侧",
  "Center": "居中",
  "Right": "右侧",
  "left": "左侧",
  "center": "居中",
  "right": "右侧",
  "THEME SWITCHING": "主题切换",
  "Sequential": "顺序",
  "Random": "随机",
  "WALLPAPER SWITCHING": "壁纸切换",
  "Current theme": "当前主题",
  "All themes": "所有主题",
  "Auto switch": "自动切换",
  "min": "分钟",
  "No current wallpaper directory is available": "当前壁纸目录不可用",
  "Could not read the theme inventory": "无法读取主题列表",
  "Theme inventory was too large or invalid; keeping the previous list": "主题列表过大或无效，已保留先前列表",
  "Bar icon moved to ": "栏图标已移动到",
  "Opened wallpaper directory: ": "已打开壁纸目录：",
  "No themes available": "没有可用主题",
  "That is the only theme": "当前只有一个主题",
  "No wallpapers available in this scope": "当前范围内没有可用壁纸",
  "That is the only wallpaper": "当前只有一张壁纸",
  "Wallpaper: ": "壁纸：",
  "Shortcuts enabled": "快捷键已启用",
  "Some shortcuts are still in use": "部分快捷键仍被占用",
  "Could not enable shortcuts": "无法启用快捷键",
  "Shortcuts removed": "快捷键已移除",
  "The shortcuts helper timed out; keeping the previous state": "快捷键助手超时，已保留先前状态",
  "Shortcut status was too large; keeping the previous state": "快捷键状态过大，已保留先前状态",
  "SHORTCUTS": "快捷键",
  "bindings.lua has an unbalanced marker block. Repair it by hand, then reopen this panel.": "bindings.lua 中 Omacycle 标记不完整。请手动修复后重新打开面板。",
  "Written to bindings.lua. If Hyprland has not picked them up, run `hyprctl reload`.": "快捷键已写入 bindings.lua。如 Hyprland 尚未加载，请运行 `hyprctl reload`。",
  "Super+Ctrl+←/→ wallpaper · Super+Ctrl+Shift+←/→ theme": "Super+Ctrl+←/→ 壁纸 · Super+Ctrl+Shift+←/→ 主题",
  "Super+Ctrl+↑ open wallpaper folder": "Super+Ctrl+↑ 打开壁纸目录"
}

function isSimplifiedChinese(locale) {
  // Localize only for the mainland China region as requested. Other regions,
  // including Singapore and Taiwan, keep the English UI regardless of script.
  var value = String(locale || "").split(".")[0].split("@")[0]
    .replace(/-/g, "_").toUpperCase().split("_")
  return value[0] === "ZH" && value.indexOf("CN") >= 0
}

function text(value, locale) {
  var source = String(value)
  return isSimplifiedChinese(locale) && SIMPLIFIED_CHINESE[source] !== undefined
    ? SIMPLIFIED_CHINESE[source] : source
}

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

function normalizeAutoWallpaperMinutes(value) {
  var number = Math.floor(Number(value))
  if (!isFinite(number)) number = DEFAULT_AUTO_WALLPAPER_MINUTES
  return Math.max(MIN_AUTO_WALLPAPER_MINUTES, Math.min(MAX_AUTO_WALLPAPER_MINUTES, number))
}

// ---- contrast-safe popup colors -------------------------------------------
// QML color values expose r/g/b as 0..1 numbers. The string path keeps these
// helpers usable from Node tests too. Alpha is intentionally ignored here:
// the popup surface may be translucent, but its declared surface color is the
// only stable value available before the compositor backdrop is known.
function colorParts(value) {
  if (value && typeof value === "object"
      && isFinite(Number(value.r)) && isFinite(Number(value.g)) && isFinite(Number(value.b))) {
    return {
      r: clampUnit(value.r),
      g: clampUnit(value.g),
      b: clampUnit(value.b)
    }
  }
  var text = String(value === undefined || value === null ? "" : value).trim()
  var match = text.match(/^#(?:([0-9a-fA-F]{2})?)([0-9a-fA-F]{6})$/)
  if (!match) return null
  var hex = match[2]
  return {
    r: parseInt(hex.slice(0, 2), 16) / 255,
    g: parseInt(hex.slice(2, 4), 16) / 255,
    b: parseInt(hex.slice(4, 6), 16) / 255
  }
}

function clampUnit(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  if (number > 1) number /= 255
  return Math.max(0, Math.min(1, number))
}

function luminanceChannel(value) {
  var channel = clampUnit(value)
  return channel <= 0.03928
    ? channel / 12.92
    : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function relativeLuminance(value) {
  var color = colorParts(value)
  if (!color) return 0
  return 0.2126 * luminanceChannel(color.r)
    + 0.7152 * luminanceChannel(color.g)
    + 0.0722 * luminanceChannel(color.b)
}

function contrastRatio(first, second) {
  var left = relativeLuminance(first)
  var right = relativeLuminance(second)
  var lighter = Math.max(left, right)
  var darker = Math.min(left, right)
  return (lighter + 0.05) / (darker + 0.05)
}

function colorHex(value) {
  var color = colorParts(value)
  if (!color) return "#ffffff"
  function byte(channel) {
    var hex = Math.round(clampUnit(channel) * 255).toString(16)
    return hex.length < 2 ? "0" + hex : hex
  }
  return "#" + byte(color.r) + byte(color.g) + byte(color.b)
}

// Choose a popup text color that actually contrasts with the popup surface.
// Theme-provided popup text wins; foreground candidates and black/white are
// safe fallbacks for themes whose bar and popup tokens disagree.
function readableTextColor(background, candidates, minimumRatio) {
  var minimum = Number(minimumRatio)
  if (!isFinite(minimum) || minimum <= 0) minimum = 4.5
  var list = Array.isArray(candidates) ? candidates : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && contrastRatio(list[i], background) >= minimum) return colorHex(list[i])
  }
  return relativeLuminance(background) > 0.5 ? "#000000" : "#ffffff"
}

// Read the five user settings out of a raw shell.json entry, clamping every
// field so a hand-edited value can never drive an unknown branch.
function normalizeSettings(entry) {
  var raw = isPlainObject(entry) ? entry : {}
  return {
    themeMode: normalizeThemeMode(raw.themeMode),
    wallpaperScope: normalizeWallpaperScope(raw.wallpaperScope),
    wallpaperRandom: normalizeBool(raw.wallpaperRandom, DEFAULT_WALLPAPER_RANDOM),
    autoWallpaper: normalizeBool(raw.autoWallpaper, DEFAULT_AUTO_WALLPAPER),
    autoWallpaperMinutes: normalizeAutoWallpaperMinutes(raw.autoWallpaperMinutes)
  }
}

// Build the entry that gets written back to shell.json: keep unknown keys the
// user or another tool may have added, overwrite only the five we own.
function settingsEntry(existing, settings) {
  var entry = { id: PLUGIN_ID }
  if (isPlainObject(existing)) {
    for (var key in existing) if (key !== "id") entry[key] = existing[key]
  }
  entry.themeMode = normalizeThemeMode(settings ? settings.themeMode : undefined)
  entry.wallpaperScope = normalizeWallpaperScope(settings ? settings.wallpaperScope : undefined)
  entry.wallpaperRandom = normalizeBool(settings ? settings.wallpaperRandom : undefined, DEFAULT_WALLPAPER_RANDOM)
  entry.autoWallpaper = normalizeBool(settings ? settings.autoWallpaper : undefined, DEFAULT_AUTO_WALLPAPER)
  entry.autoWallpaperMinutes = normalizeAutoWallpaperMinutes(settings ? settings.autoWallpaperMinutes : undefined)
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
function isInventoryPayload(raw) {
  var data = raw
  if (typeof raw === "string") {
    try { data = JSON.parse(raw) } catch (error) { return false }
  }
  return isPlainObject(data) && data.schema === 1 && Array.isArray(data.themes)
}

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
  out.currentTheme = String(data.currentTheme === undefined || data.currentTheme === null ? "" : data.currentTheme).trim()
  out.currentBackground = String(data.currentBackground === undefined || data.currentBackground === null ? "" : data.currentBackground).trim()
  var count = 0
  for (var t = 0; t < out.themes.length; t++) count += out.themes[t].backgrounds.length
  out.backgroundCount = count
  return out
}

// Theme order is decided by the Python helper, which reproduces Omarchy's own
// theme-switcher ordering. The model only copies the list so no re-sort can
// silently diverge from what the system picker shows.
function themeList(themes) {
  return Array.isArray(themes) ? themes.slice() : []
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
  var list = themeList(themes)
  if (list.length === 0) return ""
  var step = Number(direction) < 0 ? -1 : 1
  var index = themeIndex(list, currentSlug)
  if (index < 0) return step > 0 ? list[0].slug : list[list.length - 1].slug
  return list[(index + step + list.length) % list.length].slug
}

// Random theme that is never the current one while another choice exists.
function randomTheme(themes, currentSlug, rng) {
  var list = themeList(themes)
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
  var list = themeList(themes)
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
    DEFAULT_AUTO_WALLPAPER: DEFAULT_AUTO_WALLPAPER,
    DEFAULT_AUTO_WALLPAPER_MINUTES: DEFAULT_AUTO_WALLPAPER_MINUTES,
    MIN_AUTO_WALLPAPER_MINUTES: MIN_AUTO_WALLPAPER_MINUTES,
    MAX_AUTO_WALLPAPER_MINUTES: MAX_AUTO_WALLPAPER_MINUTES,
    SHORTCUTS: SHORTCUTS,
    BAR_SECTIONS: BAR_SECTIONS,
    isSimplifiedChinese: isSimplifiedChinese,
    text: text,
    isPlainObject: isPlainObject,
    normalizeThemeMode: normalizeThemeMode,
    normalizeWallpaperScope: normalizeWallpaperScope,
    normalizeBool: normalizeBool,
    normalizeAutoWallpaperMinutes: normalizeAutoWallpaperMinutes,
    colorParts: colorParts,
    relativeLuminance: relativeLuminance,
    contrastRatio: contrastRatio,
    readableTextColor: readableTextColor,
    normalizeSettings: normalizeSettings,
    settingsEntry: settingsEntry,
    prettyName: prettyName,
    parseInventory: parseInventory,
    isInventoryPayload: isInventoryPayload,
    themeList: themeList,
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
