#!/usr/bin/env python3
"""Regression checks for externally sourced text rendered by the panel."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Qt 6.12 ships a built-in `QtQuick.Color` singleton, which wins the unqualified
# name lookup against `qs.Commons.Color` no matter which module is imported.
# A bare `Color.` therefore resolves to the built-in type and every theme token
# reads back as `undefined`, which renders as opaque black instead of the
# themed color. Always reach the singleton through its namespace.
BARE_COLOR = re.compile(r"(?<!Commons\.)\bColor\.")


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
    def test_theme_colors_are_namespaced(self) -> None:
        source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn("import qs.Commons as Commons", source)
        offenders = [
            f"{number}: {line.strip()}"
            for number, line in enumerate(source.splitlines(), 1)
            if BARE_COLOR.search(line) and not line.lstrip().startswith("//")
        ]
        self.assertEqual(offenders, [], "use Commons.Color, not the shadowed bare Color")

    def test_panel_background_and_text_tokens_are_read(self) -> None:
        source = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn("Commons.Color.popups.background", source)
        self.assertIn("Commons.Color.popups.text", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
