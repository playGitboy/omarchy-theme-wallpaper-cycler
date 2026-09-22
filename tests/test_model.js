#!/usr/bin/env node
"use strict"

// Offline unit tests for the pure decision model. No QML, no shell, no files:
// every case uses a fictional inventory and a deterministic rng so the
// sequential/random rules are pinned exactly.

const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "Model.js"))

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (error) {
    console.error("FAIL:", name)
    throw error
  }
}

function inventory(themes, currentTheme, currentBackground) {
  return M.parseInventory({
    themes: themes,
    currentTheme: currentTheme || "",
    currentBackground: currentBackground || ""
  })
}

function seq(values) {
  let index = 0
  return function () {
    const value = values[index % values.length]
    index++
    return value
  }
}

// ---- settings --------------------------------------------------------------

test("contrast helpers choose a readable popup foreground", () => {
  const dark = { r: 5 / 255, g: 24 / 255, b: 46 / 255 }
  const cream = { r: 246 / 255, g: 220 / 255, b: 172 / 255 }
  const muted = { r: 42 / 255, g: 107 / 255, b: 120 / 255 }
  assert(M.contrastRatio(cream, dark) > 10)
  assert(M.contrastRatio(muted, dark) < 4.5)
  assert.strictEqual(M.readableTextColor(dark, [muted, cream], 4.5), "#f6dcac")
  assert.strictEqual(M.readableTextColor({ r: 0.95, g: 0.95, b: 0.95 }, [{ r: 0.9, g: 0.9, b: 0.9 }], 4.5), "#000000")
})

test("normalizeSettings defaults and clamps", () => {
  assert.deepStrictEqual(M.normalizeSettings({}), {
    themeMode: "sequential",
    wallpaperScope: "current",
    wallpaperRandom: false
  })
  assert.strictEqual(M.normalizeSettings({ themeMode: "RANDOM" }).themeMode, "random")
  assert.strictEqual(M.normalizeSettings({ themeMode: "bogus" }).themeMode, "sequential")
  assert.strictEqual(M.normalizeSettings({ wallpaperScope: "ALL" }).wallpaperScope, "all")
  assert.strictEqual(M.normalizeSettings({ wallpaperScope: "nope" }).wallpaperScope, "current")
  assert.strictEqual(M.normalizeSettings({ wallpaperRandom: "on" }).wallpaperRandom, true)
  assert.strictEqual(M.normalizeSettings({ wallpaperRandom: "off" }).wallpaperRandom, false)
  assert.strictEqual(M.normalizeSettings({ wallpaperRandom: 1 }).wallpaperRandom, true)
})

test("settingsEntry preserves unknown keys and overwrites owned ones", () => {
  const entry = M.settingsEntry({ id: "x", keepMe: 7, themeMode: "random" }, {
    themeMode: "sequential",
    wallpaperScope: "all",
    wallpaperRandom: true
  })
  assert.strictEqual(entry.id, M.PLUGIN_ID)
  assert.strictEqual(entry.keepMe, 7)
  assert.strictEqual(entry.themeMode, "sequential")
  assert.strictEqual(entry.wallpaperScope, "all")
  assert.strictEqual(entry.wallpaperRandom, true)
})

test("prettyName matches omarchy theme list", () => {
  assert.strictEqual(M.prettyName("tokyo-night"), "Tokyo Night")
  assert.strictEqual(M.prettyName("2-haxorz"), "2 Haxorz")
  assert.strictEqual(M.prettyName("catppuccin"), "Catppuccin")
})

// ---- inventory parsing -----------------------------------------------------

test("parseInventory rejects malformed input without throwing", () => {
  assert.deepStrictEqual(M.parseInventory("not json").themes, [])
  assert.deepStrictEqual(M.parseInventory(null).themes, [])
  assert.deepStrictEqual(M.parseInventory({ themes: "nope" }).themes, [])
  const mixed = M.parseInventory({ themes: [null, { slug: "" }, { slug: "ok" }] })
  assert.strictEqual(mixed.themes.length, 1)
  assert.strictEqual(mixed.themes[0].slug, "ok")
})

test("parseInventory sorts themes and counts backgrounds", () => {
  const inv = inventory([
    { slug: "zulu", backgrounds: ["/b/2", "/b/1"] },
    { slug: "alpha", backgrounds: ["/a/1"] }
  ])
  assert.deepStrictEqual(inv.themes.map((t) => t.slug), ["alpha", "zulu"])
  assert.strictEqual(inv.backgroundCount, 3)
  assert.strictEqual(inv.themes[0].name, "Alpha")
})

// ---- theme decisions -------------------------------------------------------

test("nextTheme wraps both directions", () => {
  const themes = [{ slug: "a" }, { slug: "b" }, { slug: "c" }]
  assert.strictEqual(M.nextTheme(themes, "a", 1), "b")
  assert.strictEqual(M.nextTheme(themes, "c", 1), "a")
  assert.strictEqual(M.nextTheme(themes, "a", -1), "c")
  assert.strictEqual(M.nextTheme(themes, "b", -1), "a")
})

test("nextTheme handles an unknown current theme and empty list", () => {
  const themes = [{ slug: "a" }, { slug: "b" }]
  assert.strictEqual(M.nextTheme(themes, "ghost", 1), "a")
  assert.strictEqual(M.nextTheme(themes, "ghost", -1), "b")
  assert.strictEqual(M.nextTheme([], "a", 1), "")
})

test("randomTheme never returns the current theme when another exists", () => {
  const themes = [{ slug: "a" }, { slug: "b" }, { slug: "c" }]
  assert.strictEqual(M.randomTheme(themes, "b", seq([0])), "a")
  assert.strictEqual(M.randomTheme(themes, "b", seq([0.99])), "c")
  assert.strictEqual(M.randomTheme(themes, "b", seq([0.5])), "c")
  // Single theme: only the current one is available.
  assert.strictEqual(M.randomTheme([{ slug: "solo" }], "solo", seq([0.5])), "solo")
})

// ---- background decisions --------------------------------------------------

test("flattenBackgrounds honours current and all scopes", () => {
  const inv = inventory([
    { slug: "alpha", backgrounds: ["/a/1", "/a/2"] },
    { slug: "beta", backgrounds: ["/b/1"] }
  ], "beta", "/b/1")
  assert.deepStrictEqual(M.flattenBackgrounds(inv.themes, "current", "beta").map((r) => r.path), ["/b/1"])
  assert.deepStrictEqual(M.flattenBackgrounds(inv.themes, "all", "beta").map((r) => r.path), ["/a/1", "/a/2", "/b/1"])
  // Unknown current theme yields an empty current scope but a full all scope.
  assert.deepStrictEqual(M.flattenBackgrounds(inv.themes, "current", "ghost"), [])
  assert.strictEqual(M.flattenBackgrounds(inv.themes, "all", "ghost").length, 3)
})

test("backgroundIndex matches exact path then basename", () => {
  const rows = [{ theme: "a", path: "/a/1.jpg" }, { theme: "a", path: "/a/2.jpg" }]
  assert.strictEqual(M.backgroundIndex(rows, "/a/2.jpg"), 1)
  assert.strictEqual(M.backgroundIndex(rows, "/somewhere/else/1.jpg"), 0)
  assert.strictEqual(M.backgroundIndex(rows, "/nope/zzz.jpg"), -1)
})

test("nextBackground wraps both directions", () => {
  const rows = [{ path: "/a" }, { path: "/b" }, { path: "/c" }]
  assert.strictEqual(M.nextBackground(rows, "/a", 1), "/b")
  assert.strictEqual(M.nextBackground(rows, "/c", 1), "/a")
  assert.strictEqual(M.nextBackground(rows, "/a", -1), "/c")
  assert.strictEqual(M.nextBackground(rows, "/ghost", 1), "/a")
  assert.strictEqual(M.nextBackground(rows, "/ghost", -1), "/c")
  assert.strictEqual(M.nextBackground([], "/a", 1), "")
})

test("randomBackground never returns the current wallpaper when another exists", () => {
  const rows = [{ path: "/a" }, { path: "/b" }, { path: "/c" }]
  assert.strictEqual(M.randomBackground(rows, "/a", seq([0])), "/b")
  assert.strictEqual(M.randomBackground(rows, "/a", seq([0.99])), "/c")
  assert.strictEqual(M.randomBackground([{ path: "/only" }], "/only", seq([0.5])), "/only")
})

// ---- one-shot decisions ----------------------------------------------------

test("decideTheme follows the mode", () => {
  const inv = inventory([{ slug: "a" }, { slug: "b" }, { slug: "c" }], "a")
  assert.strictEqual(M.decideTheme(inv, { themeMode: "sequential" }, 1), "b")
  assert.strictEqual(M.decideTheme(inv, { themeMode: "random" }, 1, seq([0.99])), "c")
})

test("decideBackground follows scope and random flag", () => {
  const inv = inventory([
    { slug: "alpha", backgrounds: ["/a/1", "/a/2"] },
    { slug: "beta", backgrounds: ["/b/1"] }
  ], "alpha", "/a/1")
  assert.strictEqual(M.decideBackground(inv, { wallpaperScope: "current", wallpaperRandom: false }, 1), "/a/2")
  assert.strictEqual(M.decideBackground(inv, { wallpaperScope: "all", wallpaperRandom: false }, 1), "/a/2")
  assert.strictEqual(M.decideBackground(inv, { wallpaperScope: "current", wallpaperRandom: true }, 1, seq([0])), "/a/2")
  assert.strictEqual(M.decideBackground(inv, { wallpaperScope: "all", wallpaperRandom: true }, 1, seq([0.99])), "/b/1")
})

test("scopeCounts reports both scopes", () => {
  const inv = inventory([
    { slug: "alpha", backgrounds: ["/a/1", "/a/2"] },
    { slug: "beta", backgrounds: ["/b/1"] }
  ], "alpha")
  assert.deepStrictEqual(M.scopeCounts(inv, {}), { themes: 2, current: 2, all: 3 })
})

console.log(`ok ${passed} model tests`)
