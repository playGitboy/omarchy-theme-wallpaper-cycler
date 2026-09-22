# Theme Wallpaper Cycler

<p>
  <a href="https://github.com/playGitboy/omarchy-theme-wallpaper-cycler/actions/workflows/test.yml"><img alt="tests" height="20" src="https://github.com/playGitboy/omarchy-theme-wallpaper-cycler/actions/workflows/test.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: MIT" height="20" src="https://img.shields.io/badge/license-MIT-2f855a?labelColor=0b0f14"></a>
  <a href="https://github.com/tcballard/omarchy-badges"><img alt="Built for Omarchy: Plugin" height="20" src="https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg"></a>
  <a href="#compatibility"><img alt="Supported Omarchy versions: 4.0.0+" height="20" src="https://raw.githubusercontent.com/tcballard/omarchy-badges/dd84bb21f19caf617caa5b3c1af7ff3c6cb847c3/badges/v1/compatibility/omarchy-4.0.0-plus.svg"></a>
</p>

Cycle every installed Omarchy theme and wallpaper from one bar icon or with the
keyboard. Pick sequential or random theme switching, rotate only the current
theme's wallpapers or every theme's, and use a panel that follows the active
theme's colours.

## What it does

- **Theme cycling** — `Super+Ctrl+Shift+Left` / `Super+Ctrl+Shift+Right` walks
  every installed theme in order and wraps around, or jumps to a random theme
  that is not the current one.
- **Wallpaper cycling** — `Super+Ctrl+Left` / `Super+Ctrl+Right` cycles the
  current theme's wallpapers, or every wallpaper across every installed theme,
  in order or at random.
- **A bar panel** — choose the icon's bar position (left/center/right), the
  theme and wallpaper modes, and enable or remove the shortcuts. The panel uses
  Omarchy's theme tokens, so it recolours itself whenever the theme changes.
- **A managed keybinding block** — the shortcuts are written to
  `~/.config/hypr/bindings.lua` as one fenced block that only this plugin owns.
  Nothing outside the block is ever touched, and removal restores the file.

## Requirements

- Omarchy 4 with Quattro shell-plugin support.
- Python 3 (standard library only) for the inventory and keybinding helper.
- `hyprctl` (part of Hyprland) for installing and verifying the shortcuts.
- No network access, no background daemon, and no privileged operation.

## Installation

```bash
omarchy plugin add https://github.com/playGitboy/omarchy-theme-wallpaper-cycler.git --enable
```

Choose where the icon sits while enabling:

```bash
omarchy plugin enable io.github.playgitboy.theme-wallpaper-cycler --section right
```

`left`, `center`, and `right` are all valid; you can also change it any time
from the panel's **Bar position** section.

## Usage

Click the palette icon in the bar to open the panel.

| Control | What it changes |
| --- | --- |
| Bar position | Left / Center / Right placement of the icon |
| Theme switching | `Sequential (default)` or `Random` |
| Wallpaper source | `Current theme (default)` or `All themes` |
| Random | Independent switch: pick a random wallpaper from the chosen source |
| Shortcuts | Enable or remove the `bindings.lua` block |

Keyboard, once the panel is open: `j`/`k` or `↑`/`↓` move, `h`/`l` change the
focused control, `Enter` activates, `Esc` closes. `t`, `w`, `r`, and `e` are
shortcuts for theme mode, wallpaper source, random, and enable/remove.

### Default shortcuts

| Shortcut | Action |
| --- | --- |
| `Super+Ctrl+Shift+Left` | Previous theme |
| `Super+Ctrl+Shift+Right` | Next theme |
| `Super+Ctrl+Left` | Previous wallpaper |
| `Super+Ctrl+Right` | Next wallpaper |

### IPC

```bash
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler status
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler themeNext
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler wallpaperPrev
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler setSetting themeMode random
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler enableKeybindings
omarchy-shell io.github.playgitboy.theme-wallpaper-cycler disableKeybindings
```

## Settings

Settings live as flat keys on the plugin's own entry in
`~/.config/omarchy/shell.json`, exactly like stock widgets:

```json
{
  "id": "io.github.playgitboy.theme-wallpaper-cycler",
  "themeMode": "sequential",
  "wallpaperScope": "current",
  "wallpaperRandom": false
}
```

They can also be set with `omarchy bar set`:

```bash
omarchy bar set io.github.playgitboy.theme-wallpaper-cycler themeMode random
omarchy bar set io.github.playgitboy.theme-wallpaper-cycler wallpaperScope all
omarchy bar set io.github.playgitboy.theme-wallpaper-cycler wallpaperRandom true
```

## Keybindings, conflicts, and removal

Enabling shortcuts appends one fenced block to `~/.config/hypr/bindings.lua`:

```lua
-- BEGIN io.github.playgitboy.theme-wallpaper-cycler
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")
o.bind("SUPER + SHIFT + CTRL + LEFT", "Previous theme (Theme Wallpaper Cycler)", hl.dsp.global("io.github.playgitboy.theme-wallpaper-cycler:theme-prev"))
-- ...
-- END io.github.playgitboy.theme-wallpaper-cycler
```

The helper backs the file up first (`bindings.lua.bak.<timestamp>`), writes
through a same-directory temporary file, and refuses symlinks or non-regular
files. Before writing, it inspects the live `hyprctl binds` list and the user's
own `o.bind(...)` lines. A shortcut that is already taken by something else is
**never overwritten silently**: the panel names the current owner and offers to
take it over, and only then does the helper emit the `hl.unbind(...)` line.

Stock Omarchy binds `Super+Ctrl+Left/Right` to *Move grouped window focus*, so
the first time you enable shortcuts the panel reports that conflict and takes
the two keys over when you press **Enable & take over**. `Super+Ctrl+Shift+Left/Right`
is normally free. Removing the block does not restore a key that was taken
over; re-add your own binding if you want it back.

## Compatibility

- Built and tested on Omarchy `4.0.0.r2186.gee8ebf6-1` (Quattro shell), Arch
  Linux, Hyprland with the Lua configuration API, Wayland.
- Targets the installed Omarchy version reported by `omarchy-version`, not the
  ISO image version.
- Uses only documented surfaces: `qs.Commons` (`Color`, `Style`, `Border`),
  `qs.Ui` (`Panel`, `KeyboardPanel`, `BarIconButton`, `ButtonGroup`, `Toggle`),
  `Quickshell.Hyprland.GlobalShortcut`, `Quickshell.Io.Process`, and the
  `omarchy theme`, `omarchy theme bg`, and `omarchy bar` commands.
- Popup content chooses the active popup text token first and verifies its
  contrast against the popup background, falling back to a readable black or
  white color for themes with inconsistent bar and popup tokens.
- Wallpaper ordering uses theme slug plus filename rather than absolute paths,
  so the same inventory has the same order on different computers.
- One service instance owns the shortcuts and the inventory; the bar widget is
  a per-monitor view, so the four shortcuts are registered once regardless of
  how many screens or bar copies exist.
- Themes and wallpapers are discovered from both the stock theme directory and
  the user's own `~/.config/omarchy/themes` and
  `~/.config/omarchy/backgrounds`, including user theme directories that are
  symlinks. Image and video extensions match Omarchy's own list.

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
```

`./tests/run` runs the pure `Model.js` decision tests under Node, the inventory
and bindings manager tests under Python, a `py_compile` check on the helper,
the portable manifest validator, and `omarchy plugin validate` when available.
`./demo/run` is a deterministic, reversible offline walkthrough that never
touches the real desktop.

## Update

```bash
omarchy plugin update io.github.playgitboy.theme-wallpaper-cycler
```

## Removal

Remove the keybinding block from the panel first (or run
`bin/theme-cycler binds remove`), then:

```bash
omarchy plugin remove io.github.playgitboy.theme-wallpaper-cycler
```

The plugin stores nothing outside its `shell.json` entry and the fenced
`bindings.lua` block.

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository before enabling it. This plugin reads theme and wallpaper
directories, writes only its own `shell.json` entry and its own fenced
`bindings.lua` block, and runs `omarchy`/`hyprctl` commands with argument
arrays. It does not use the network and does not request elevated privileges.

## License

MIT © 2026 playGitboy
