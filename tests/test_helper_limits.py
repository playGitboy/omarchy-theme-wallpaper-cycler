#!/usr/bin/env python3
"""Producer-side output limits and deadlines for the Binds helper path."""
from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
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

    def spawn(self, code: str) -> subprocess.Popen:
        return subprocess.Popen(
            [sys.executable, "-c", code],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

    def reap(self, process: subprocess.Popen) -> None:
        if process.poll() is None:
            process.kill()
            process.wait()
        if process.stdout:
            process.stdout.close()

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

    def test_read_bounded_returns_data_until_eof(self) -> None:
        process = self.spawn("import sys; sys.stdout.write('ok')")
        try:
            result = self.module.read_bounded(process.stdout, 1024, time.monotonic() + 5)
            process.wait(timeout=5)
            self.assertEqual(result, b"ok")
        finally:
            self.reap(process)

    def test_read_bounded_rejects_oversized_output(self) -> None:
        process = self.spawn("import sys; sys.stdout.write('x' * 4096)")
        try:
            self.assertIsNone(self.module.read_bounded(process.stdout, 1024, time.monotonic() + 5))
        finally:
            self.reap(process)

    def test_read_bounded_enforces_deadline_on_silent_pipe(self) -> None:
        process = self.spawn("import time; time.sleep(30)")
        try:
            start = time.monotonic()
            result = self.module.read_bounded(process.stdout, 1024, time.monotonic() + 0.25)
            elapsed = time.monotonic() - start
            self.assertIsNone(result)
            self.assertLess(elapsed, 3.0)
        finally:
            self.reap(process)

    def test_read_bounded_rejects_stream_without_descriptor(self) -> None:
        self.assertIsNone(self.module.read_bounded(io.BytesIO(b"data"), 16, time.monotonic() + 1))

    def test_open_regular_readonly_rejects_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fifo = os.path.join(tmp, "state")
            os.mkfifo(fifo)
            self.assertIsNone(self.module.open_regular_readonly(fifo))

    def test_read_regular_bounded_rejects_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fifo = os.path.join(tmp, "state")
            os.mkfifo(fifo)
            self.assertIsNone(self.module.read_regular_bounded(fifo, 4096))

    def test_current_theme_ignores_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = os.path.join(tmp, ".local", "state", "omarchy", "current")
            os.makedirs(state)
            os.mkfifo(os.path.join(state, "theme.name"))
            with patch.dict(os.environ, {"HOME": tmp, "XDG_STATE_HOME": os.path.join(tmp, ".local", "state")}):
                self.assertEqual(self.module.current_theme(), "")

    def test_copy_regular_file_rejects_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fifo = os.path.join(tmp, "bindings.lua")
            os.mkfifo(fifo)
            self.assertIsNone(self.module.copy_regular_file(fifo, os.path.join(tmp, "backup")))

    def test_live_binds_rejects_oversized_hyprctl_output(self) -> None:
        oversized = self.module.MAX_LIVE_BINDS_BYTES + 1
        process = self.spawn(f"import sys; sys.stdout.write('x' * {oversized})")
        with patch.object(self.module, "hyprctl_available", return_value=True), \
                patch.object(self.module.subprocess, "Popen", return_value=process):
            self.assertIsNone(self.module.live_binds())

    def test_live_binds_times_out_on_silent_hyprctl(self) -> None:
        process = self.spawn("import time; time.sleep(30)")
        with patch.object(self.module, "hyprctl_available", return_value=True), \
                patch.object(self.module, "LIVE_BINDS_TIMEOUT", 0.3), \
                patch.object(self.module.subprocess, "Popen", return_value=process):
            start = time.monotonic()
            self.assertIsNone(self.module.live_binds())
            elapsed = time.monotonic() - start
        self.assertLess(elapsed, 5.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
