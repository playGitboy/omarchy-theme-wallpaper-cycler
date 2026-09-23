#!/usr/bin/env python3
"""End-to-end tests for the bindings.lua manager.

Every case runs the helper against a throwaway --config file with no Hyprland
in the environment, so conflict detection falls back to reading the user's own
`o.bind(...)` lines. The real ~/.config/hypr/bindings.lua is never touched.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "bin" / "theme-cycler"

BEGIN = "-- BEGIN io.github.playgitboy.omacycle"
END = "-- END io.github.playgitboy.omacycle"


class BindsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.config = Path(self.tmp.name) / "bindings.lua"
        self.env = dict(os.environ)
        self.env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_helper(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(HELPER), "binds", *args, "--config", str(self.config)],
            capture_output=True, text=True, env=self.env, timeout=30,
        )

    def status(self) -> dict:
        result = self.run_helper("status", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def install(self, *extra: str) -> dict:
        result = self.run_helper("install", "--json", "--no-reload", *extra)
        self.assertIn(result.returncode, (0, 3), result.stderr)
        return json.loads(result.stdout)

    def remove(self) -> dict:
        result = self.run_helper("remove", "--json", "--no-reload")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_install_into_empty_file(self) -> None:
        payload = self.install()
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(payload["installed"])
        self.assertEqual(set(payload["keys"]), {"theme-prev", "theme-next", "wallpaper-prev", "wallpaper-next"})
        text = self.config.read_text()
        self.assertIn(BEGIN, text)
        self.assertIn(END, text)
        self.assertIn("theme-prev", text)
        self.assertIn("wallpaper-next", text)
        # No conflicting keys, so no unbind lines are needed.
        self.assertNotIn("hl.unbind", text)
        self.assertTrue(self.status()["installed"])

    def test_reinstall_is_idempotent(self) -> None:
        self.install()
        first = self.config.read_text()
        self.install()
        second = self.config.read_text()
        self.assertEqual(second.count(BEGIN), 1)
        self.assertEqual(first, second)

    def test_remove_restores_user_content(self) -> None:
        self.config.write_text('-- my config\no.bind("SUPER + T", "Terminal", "alacritty")\n')
        original = self.config.read_text()
        self.install()
        payload = self.remove()
        self.assertEqual(payload["removed"], 1)
        self.assertEqual(self.config.read_text(), original)
        self.assertFalse(self.status()["installed"])

    def test_conflicting_user_binding_is_skipped(self) -> None:
        self.config.write_text('o.bind("SUPER + CTRL + LEFT", "My wallpaper", "~/bin/wallpaper previous")\n')
        payload = self.install()
        self.assertEqual(payload["status"], "ok")
        self.assertIn("wallpaper-prev", payload["skipped"])
        self.assertNotIn("wallpaper-prev", payload["keys"])
        self.assertTrue(any(c["action"] == "wallpaper-prev" for c in payload["conflicts"]))
        text = self.config.read_text()
        self.assertNotIn('hl.dsp.global("io.github.playgitboy.omacycle:wallpaper-prev")', text)

    def test_replace_takes_over_conflicting_binding(self) -> None:
        self.config.write_text('o.bind("SUPER + CTRL + LEFT", "My wallpaper", "~/bin/wallpaper previous")\n')
        payload = self.install("--replace", "wallpaper-prev")
        self.assertIn("wallpaper-prev", payload["keys"])
        self.assertTrue(any(entry["action"] == "wallpaper-prev" for entry in payload["unbound"]))
        text = self.config.read_text()
        self.assertIn('hl.unbind("SUPER + CTRL + LEFT")', text)
        self.assertIn('hl.dsp.global("io.github.playgitboy.omacycle:wallpaper-prev")', text)

    def test_blocked_when_every_action_conflicts(self) -> None:
        self.config.write_text(
            'o.bind("SUPER + CTRL + SHIFT + LEFT", "a", "x")\n'
            'o.bind("SUPER + CTRL + SHIFT + RIGHT", "b", "x")\n'
            'o.bind("SUPER + CTRL + LEFT", "c", "x")\n'
            'o.bind("SUPER + CTRL + RIGHT", "d", "x")\n'
        )
        payload = self.install()
        self.assertEqual(payload["status"], "blocked")
        self.assertFalse(payload["installed"])
        self.assertNotIn(BEGIN, self.config.read_text())

    def test_backup_is_created(self) -> None:
        self.config.write_text("-- keep me\n")
        payload = self.install()
        self.assertIsNotNone(payload["backup"])
        self.assertTrue(Path(payload["backup"]).exists())
        self.assertEqual(Path(payload["backup"]).read_text(), "-- keep me\n")

    def test_dangling_marker_is_refused(self) -> None:
        self.config.write_text(BEGIN + "\n")
        result = self.run_helper("install", "--json", "--no-reload")
        self.assertEqual(result.returncode, 1)
        self.assertIn("unbalanced", result.stderr)
        self.assertEqual(self.config.read_text(), BEGIN + "\n")

    def test_symlinked_config_is_refused(self) -> None:
        real = Path(self.tmp.name) / "real.lua"
        real.write_text("-- real\n")
        self.config.symlink_to(real)
        result = self.run_helper("status", "--json")
        payload = json.loads(result.stdout)
        self.assertNotEqual(payload["file"], "ok")
        result = self.run_helper("install", "--json", "--no-reload")
        self.assertEqual(result.returncode, 1)

    def test_alternate_keys_are_reported(self) -> None:
        self.config.write_text('o.bind("SUPER + CTRL + RIGHT", "Other", "x")\n')
        payload = self.install()
        conflict = next(c for c in payload["conflicts"] if c["action"] == "wallpaper-next")
        self.assertEqual(conflict["alternate"], "SUPER + ALT + RIGHT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
