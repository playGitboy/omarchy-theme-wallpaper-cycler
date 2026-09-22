# Changelog

## 0.1.2 — 2026-09-22

Naming and compact-panel update.

- Renamed the marketplace-facing plugin to `OmaCycle — Theme & Wallpaper Cycler` and the bar label to `OmaCycle`.
- Reduced the Random wallpaper control to the same compact height as the other panel controls.

## 0.1.1 — 2026-09-22

Compatibility and readability update.

- Panel text now uses the popup surface's text token and a WCAG-style contrast
  fallback, so dark popup backgrounds never receive dark unreadable labels.
- The inventory helper orders wallpapers by filename rather than absolute
  machine-specific paths, making cycling deterministic across installations.
- Python is resolved through `PATH`, backup names cannot collide within one
  second, and MOD3 key parsing is supported.
- Inventory refresh state and cached scope counts are now explicit in the
  service, and short-screen cursor scrolling clamps safely.

## 0.1.0 — 2026-09-22

Initial release.

- Bar icon plus a compact themed panel: bar position (left/center/right), theme
  switching (sequential/random), wallpaper source (current theme/all themes),
  and an independent random-wallpaper switch.
- Global shortcuts `Super+Ctrl+Shift+Left/Right` (themes) and
  `Super+Ctrl+Left/Right` (wallpapers), registered once in a `service` entry
  point so multiple monitors do not duplicate them.
- A managed `bindings.lua` block with timestamped backups, atomic writes,
  live-bind and textual conflict detection, and consent-based takeover of
  already-occupied keys.
- Pure `Model.js` decision logic (Node-tested) and a standard-library Python
  helper for inventory and keybinding management (end-to-end tested).
- Discovery of stock and user themes, including symlinked user theme
  directories and user-supplied per-theme background folders.
