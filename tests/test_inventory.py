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

    def test_order_matches_omarchy_find_sort(self) -> None:
        # LC_ALL=C keeps the expected order deterministic on any CI host.
        self.env["LC_ALL"] = "C"
        self.env["LANG"] = "C"
        write_media(self.omarchy / "themes" / "ord" / "backgrounds", ["b.jpg", "A.jpg", "中.png", "notes.txt"])
        write_media(self.home / ".config" / "omarchy" / "backgrounds" / "ord", ["c.jpg"])
        state = self.home / ".local" / "state" / "omarchy" / "current"
        state.mkdir(parents=True)
        (state / "theme.name").write_text("ord\n")

        data = self.inventory()
        ours = [Path(path).name for path in data["themes"][0]["backgrounds"]]

        dirs = [
            str(self.home / ".config" / "omarchy" / "backgrounds" / "ord"),
            str(self.omarchy / "themes" / "ord" / "backgrounds"),
        ]
        extensions = []
        for extension in (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi"):
            extensions.extend(["-o", "-iname", f"*{extension}"])
        found = subprocess.run(
            ["find", "-L", dirs[0], dirs[1], "-maxdepth", "1", "-type", "f", "(", *extensions[1:], ")", "-print0"],
            capture_output=True, env=self.env, timeout=30,
        )
        sorted_out = subprocess.run(["sort", "-z"], input=found.stdout, capture_output=True, env=self.env, timeout=30)
        expected = [Path(part.decode()).name for part in sorted_out.stdout.split(b"\0") if part]

        self.assertEqual(ours, expected)
        self.assertNotIn("notes.txt", ours)

    def test_current_theme_prefers_the_staged_copy(self) -> None:
        write_media(self.omarchy / "themes" / "cur" / "backgrounds", ["sys1.jpg"])
        write_media(self.home / ".local" / "state" / "omarchy" / "current" / "theme" / "backgrounds", ["staged1.jpg"])
        write_media(self.home / ".config" / "omarchy" / "backgrounds" / "cur", ["user1.jpg"])
        state = self.home / ".local" / "state" / "omarchy" / "current"
        (state / "theme.name").write_text("cur\n")

        names = [Path(path).name for path in self.inventory()["themes"][0]["backgrounds"]]
        self.assertIn("staged1.jpg", names)
        self.assertIn("user1.jpg", names)
        self.assertNotIn("sys1.jpg", names)

    def test_theme_order_matches_theme_switcher(self) -> None:
        # The theme menu feeds omarchy-menu-images a preview dir named
        # <theme>.<ext>; our order must equal that dir's find|sort -z order,
        # including prefix collisions like catppuccin / catppuccin-latte.
        self.env["LC_ALL"] = "C"
        self.env["LANG"] = "C"
        slugs = ["catppuccin", "catppuccin-latte", "tokyo-night", "2-haxorz"]
        for slug in slugs:
            write_media(self.omarchy / "themes" / slug / "backgrounds", ["a.png"])

        ours = [theme["slug"] for theme in self.inventory()["themes"]]

        previews = Path(self.tmp.name) / "previews"
        previews.mkdir()
        for slug in slugs:
            (previews / f"{slug}.png").write_bytes(b"x")
        listing = subprocess.run(
            ["find", "-L", str(previews), "-maxdepth", "1", "-type", "f", "-printf", "%f\n"],
            capture_output=True, env=self.env, timeout=30,
        )
        sorted_out = subprocess.run(["sort"], input=listing.stdout, capture_output=True, env=self.env, timeout=30)
        expected = [line.decode().rsplit(".", 1)[0] for line in sorted_out.stdout.splitlines() if line]

        self.assertEqual(ours, expected)
        self.assertEqual(ours[0], "2-haxorz")
        self.assertLess(ours.index("catppuccin-latte"), ours.index("catppuccin"))

    def test_pretty_names(self) -> None:
        write_media(self.omarchy / "themes" / "2-haxorz" / "backgrounds", ["a.png"])
        write_media(self.omarchy / "themes" / "tokyo-night" / "backgrounds", ["b.png"])
        names = {theme["slug"]: theme["name"] for theme in self.inventory()["themes"]}
        self.assertEqual(names["2-haxorz"], "2 Haxorz")
        self.assertEqual(names["tokyo-night"], "Tokyo Night")


if __name__ == "__main__":
    unittest.main(verbosity=2)
