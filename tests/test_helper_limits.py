#!/usr/bin/env python3
"""Producer-side output limits for the Binds helper path."""
from __future__ import annotations

import importlib.util
import io
import json
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "bin" / "theme-cycler"


def load_helper():
    loader = SourceFileLoader("theme_cycler_limits", str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class HelperLimitsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_helper()

    def test_bounded_json_refuses_oversized_response(self) -> None:
        with self.assertRaises(self.module.HelperError):
            self.module.bounded_json({"text": "a" * 100}, 32)
        self.assertEqual(
            json.loads(self.module.bounded_json({"ok": True}, 128)),
            {"ok": True},
        )

    def test_owner_descriptions_are_clipped(self) -> None:
        clipped = self.module.bounded_owner("a" * 500)
        self.assertEqual(len(clipped), self.module.MAX_OWNER_CHARS + 1)
        self.assertTrue(clipped.endswith("…"))
        self.assertEqual(self.module.bounded_owner("short"), "short")

    def test_live_binds_rejects_oversized_hyprctl_output(self) -> None:
        class FakeProcess:
            returncode = 0

            def __init__(self):
                self.stdout = io.BytesIO(b"x" * (self_module.MAX_LIVE_BINDS_BYTES + 1))
                self.killed = False

            def kill(self):
                self.killed = True

            def wait(self, *args, **kwargs):
                return 0

        self_module = self.module
        process = FakeProcess()
        with patch.object(self_module, "hyprctl_available", return_value=True), \
                patch.object(self_module.subprocess, "Popen", return_value=process):
            self.assertIsNone(self_module.live_binds())
        self.assertTrue(process.killed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
