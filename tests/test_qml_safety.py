#!/usr/bin/env python3
"""Regression checks for externally sourced text rendered by the panel."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Qt 6.12 added a built-in `QtQuick.Color` singleton. It is visible in every
# scope, so it wins the unqualified name lookup against `qs.Commons.Color`
# whatever the file imports: a bare `Color` binds to the built-in type, every
# theme token reads back as `undefined`, and the panel paints opaque black
# with unreadable text instead of the theme's colors.
#
# `import qs.Commons as Commons` sidesteps that for good. A qualified import
# binds each type explicitly, so the resolution never consults the unqualified
# namespace and stays correct whether or not QtQuick happens to export a
# same-named type -- the same source therefore runs on Qt 6.11 and 6.12 alike.
# Only a bare `Color` reference is version-dependent, and there must be none.
BARE_COLOR = re.compile(r"(?<!Commons\.)\bColor\b")

# The other singletons this plugin uses are not shadowed by QtQuick, so they
# stay unqualified: Color, Style, Border, Util and IpcRegistry come from the
# same `qs.Commons` import line.
COLOR_TOKENS = (
    "Commons.Color.popups.background",
    "Commons.Color.popups.text",
    "Commons.Color.foreground",
    "Commons.Color.accent",
    "Commons.Color.urgent",
)


def qml_files() -> list[Path]:
    return sorted(p for p in ROOT.rglob("*.qml") if ".git" not in p.parts)


def code_lines(source: str) -> list[tuple[int, str]]:
    """Yield (line number, text) for lines that are not comments."""
    out = []
    for number, line in enumerate(source.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("*"):
            continue
        out.append((number, line))
    return out


class QmlTextSafetyTest(unittest.TestCase):
    def test_inventory_and_binds_have_deadlines(self) -> None:
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("id: inventoryTimeout", service)
        self.assertIn("inventoryProcess.running = false", service)
        self.assertIn("id: bindsTimeout", service)
        self.assertIn("bindsProcess.running = false", service)

    def test_filesystem_names_and_status_are_plain_text(self) -> None:
        source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn(
            'textFormat: Text.PlainText\n                text: root.serviceReady\n'
            '                  ? (root.currentThemeLabel + " · " + root.currentWallpaperLabel)',
            source,
        )
        self.assertIn(
            'textFormat: Text.PlainText\n                  text: root.formatConflict(modelData)',
            source,
        )
        self.assertIn(
            'textFormat: Text.PlainText\n              text: root.serviceReady ? String(root.service.lastMessage) : ""',
            source,
        )


class QmlColorTokenTest(unittest.TestCase):
    def test_no_qml_file_binds_the_shadowed_color(self) -> None:
        offenders = []
        for path in qml_files():
            source = path.read_text(encoding="utf-8")
            for number, line in code_lines(source):
                if BARE_COLOR.search(line):
                    offenders.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
        self.assertEqual(offenders, [], "read theme colors through Commons.Color")

    def test_files_using_colors_import_the_namespace(self) -> None:
        for path in qml_files():
            source = path.read_text(encoding="utf-8")
            if "Commons.Color." not in source:
                continue
            self.assertIn(
                "import qs.Commons as Commons",
                source,
                f"{path.relative_to(ROOT)} uses Commons.Color without importing the namespace",
            )

    def test_panel_reads_background_and_text_tokens(self) -> None:
        source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        for token in COLOR_TOKENS:
            self.assertIn(token, source)

    def test_qml_files_are_actually_covered(self) -> None:
        """Guard the sweep above against silently matching nothing."""
        self.assertGreaterEqual(len(qml_files()), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)