#!/usr/bin/env python3
"""Regression checks for externally sourced text rendered by the panel."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
