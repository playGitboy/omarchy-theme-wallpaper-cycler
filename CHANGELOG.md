# Changelog

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
