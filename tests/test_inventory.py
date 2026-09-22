#!/usr/bin/env python3
"""End-to-end tests for `theme-cycler inventory` against a fictional HOME.

Nothing here touches the real desktop: every case builds a throwaway XDG tree
and asserts the JSON the QML service will consume.
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


def make_env(home: Path, omarchy: Path) -> dict:
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["XDG_STATE_HOME"] = str(home / ".local" / "state")
    env["OMARCHY_PATH"] = str(omarchy)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    return env


def write_media(directory: Path, names: list) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        (directory / name).write_bytes(b"x")


class InventoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.omarchy = Path(self.tmp.name) / "omarchy"
        self.home.mkdir(parents=True)
        self.omarchy.mkdir(parents=True)
        self.env = make_env(self.home, self.omarchy)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_helper(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(HELPER), *args],
            capture_output=True, text=True, env=self.env, timeout=30,
        )

    def inventory(self) -> dict:
        result = self.run_helper("inventory")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_empty_tree_is_valid(self) -> None:
        data = self.inventory()
        self.assertEqual(data["themes"], [])
        self.assertEqual(data["currentTheme"], "")
        self.assertEqual(data["currentBackground"], "")

    def test_merges_system_user_and_user_backgrounds(self) -> None:
        write_media(self.omarchy / "themes" / "sys-a" / "backgrounds", ["2-b.jpg", "1-a.png", "notes.txt"])
        write_media(self.home / ".config" / "omarchy" / "backgrounds" / "sys-a", ["0-user.webp"])
        write_media(self.home / ".config" / "omarchy" / "themes" / "user-b" / "backgrounds", ["only.mkv"])
        write_media(self.home / ".config" / "omarchy" / "themes" / "user-b", ["colors.toml"])

        data = self.inventory()
        self.assertEqual([theme["slug"] for theme in data["themes"]], ["sys-a", "user-b"])
        self.assertEqual(data["themes"][0]["source"], "system")
        self.assertEqual(data["themes"][1]["source"], "user")
        names = [Path(path).name for path in data["themes"][0]["backgrounds"]]
        self.assertEqual(sorted(names), ["0-user.webp", "1-a.png", "2-b.jpg"])
        self.assertEqual([Path(path).name for path in data["themes"][1]["backgrounds"]], ["only.mkv"])

    def test_user_theme_dir_wins_source_label(self) -> None:
        write_media(self.omarchy / "themes" / "shared" / "backgrounds", ["sys.jpg"])
        write_media(self.home / ".config" / "omarchy" / "themes" / "shared" / "backgrounds", ["user.jpg"])
        data = self.inventory()
        self.assertEqual(len(data["themes"]), 1)
        self.assertEqual(data["themes"][0]["source"], "user")
        self.assertEqual(
            sorted(Path(path).name for path in data["themes"][0]["backgrounds"]),
            ["sys.jpg", "user.jpg"],
        )

    def test_current_theme_and_background(self) -> None:
        write_media(self.omarchy / "themes" / "tokyo" / "backgrounds", ["wall.jpg"])
        state = self.home / ".local" / "state" / "omarchy" / "current"
        state.mkdir(parents=True)
        (state / "theme.name").write_text("tokyo\n")
        (state / "background").symlink_to(self.omarchy / "themes" / "tokyo" / "backgrounds" / "wall.jpg")

        data = self.inventory()
        self.assertEqual(data["currentTheme"], "tokyo")
        self.assertEqual(data["currentBackground"], str(self.omarchy / "themes" / "tokyo" / "backgrounds" / "wall.jpg"))

    def test_dangling_current_background_is_ignored(self) -> None:
        state = self.home / ".local" / "state" / "omarchy" / "current"
        state.mkdir(parents=True)
        (state / "background").symlink_to(self.home / "gone.jpg")
        data = self.inventory()
        self.assertEqual(data["currentBackground"], "")

    def test_symlinked_user_theme_is_followed(self) -> None:
        real = Path(self.tmp.name) / "real-theme"
        write_media(real / "backgrounds", ["linked.png"])
        themes = self.home / ".config" / "omarchy" / "themes"
        themes.mkdir(parents=True)
        (themes / "linked-theme").symlink_to(real, target_is_directory=True)
        data = self.inventory()
        self.assertEqual([theme["slug"] for theme in data["themes"]], ["linked-theme"])

    def test_pretty_names(self) -> None:
        write_media(self.omarchy / "themes" / "2-haxorz" / "backgrounds", ["a.png"])
        write_media(self.omarchy / "themes" / "tokyo-night" / "backgrounds", ["b.png"])
        names = {theme["slug"]: theme["name"] for theme in self.inventory()["themes"]}
        self.assertEqual(names["2-haxorz"], "2 Haxorz")
        self.assertEqual(names["tokyo-night"], "Tokyo Night")


if __name__ == "__main__":
    unittest.main(verbosity=2)
