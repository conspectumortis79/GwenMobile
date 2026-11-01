#!/usr/bin/env python3
from __future__ import annotations

import importlib
import io
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
runner = importlib.import_module("device-test")


class FakeDevice:
    udid = "FAKE"
    name = "Fake"


class FakeProc:
    def __init__(self, text: str = ""):
        self.stdout = io.StringIO(text)


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def time(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


class TraceFallbackTests(unittest.TestCase):
    def test_a_closed_console_falls_back_to_the_trace(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            original = runner.wait_for_trace
            runner.wait_for_trace = lambda *args, **kwargs: (True, "FLOWTEST finished cmd=demo\n")
            try:
                ok, trace, reason = runner.wait_for_finish(FakeDevice(), FakeProc(), "demo",
                                                           0.01, 30, 1, Path(folder), False)
            finally:
                runner.wait_for_trace = original
            self.assertTrue(ok)
            self.assertEqual(reason, "")
            self.assertIn("FLOWTEST finished cmd=demo", trace)

    def test_a_dead_trace_still_fails_the_run(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            original = runner.wait_for_trace
            runner.wait_for_trace = lambda *args, **kwargs: (False, "keine zeile")
            try:
                ok, trace, reason = runner.wait_for_finish(FakeDevice(), FakeProc(), "demo",
                                                           0.01, 30, 1, Path(folder), False)
            finally:
                runner.wait_for_trace = original
            self.assertFalse(ok)
            self.assertEqual(reason, "console_closed")

    def test_the_trace_file_reports_the_finish_signal(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            original = runner.pull_document

            def pull(device, relative, destination) -> bool:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text("STATS x\nFLOWTEST finished cmd=demo\n", encoding="utf-8")
                return True

            runner.pull_document = pull
            try:
                ok, text = runner.wait_for_trace(FakeDevice(), "demo", time.time() + 5,
                                                 Path(folder), 1, 45)
            finally:
                runner.pull_document = original
            self.assertTrue(ok)
            self.assertIn("FLOWTEST finished cmd=demo", text)

    def test_a_trace_that_stops_growing_gives_up(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            original_pull = runner.pull_document
            original_time = runner.time

            def pull(device, relative, destination) -> bool:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text("STATS x\n", encoding="utf-8")
                return True

            runner.pull_document = pull
            runner.time = FakeClock()
            try:
                ok, text = runner.wait_for_trace(FakeDevice(), "demo", 200, Path(folder), 10, 45)
            finally:
                runner.pull_document = original_pull
                runner.time = original_time
            self.assertFalse(ok)
            self.assertIn("STATS", text)


class ScenarioDiscoveryTests(unittest.TestCase):
    SOURCE = (
        "enum DebugFileProbe {\n"
        "    static func run(_ name: String) async -> Bool {\n"
        "        switch name {\n"
        '        case "droptest": await drop(files: ["brief.docx"])\n'
        "        default: return false\n"
        "        }\n"
        "    }\n"
        "\n"
        "    static func flowTest(named name: String) -> Probe? {\n"
        "        switch name {\n"
        '        case "shotchat": return { view in await shot(view) }\n'
        "        default: return nil\n"
        "        }\n"
        "    }\n"
        "\n"
        "    static func write(_ name: String) -> Bool {\n"
        "        switch name {\n"
        '        case "brief.docx": return writeDocx()\n'
        "        default: return false\n"
        "        }\n"
        "    }\n"
        "}\n"
    )

    def test_only_dispatched_names_become_scenarios(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "DebugFileProbes.swift").write_text(self.SOURCE, encoding="utf-8")
            original = runner.PROBE_DIR
            runner.PROBE_DIR = Path(folder)
            try:
                names = sorted(item.name for item in runner.discover_scenarios())
            finally:
                runner.PROBE_DIR = original
        self.assertEqual(names, ["droptest", "shotchat"])

    def test_a_report_named_by_a_constant_is_expected(self) -> None:
        source = (
            "enum DebugFeatureProbe {\n"
            "    static func run(_ name: String) async -> Bool {\n"
            "        switch name {\n"
            '        case "localprobe": await DebugLocalProbe.run(view)\n'
            "        default: return false\n"
            "        }\n"
            "    }\n"
            "}\n"
            "\n"
            "enum DebugLocalProbe {\n"
            '    static let reportFile = "local_probe.txt"\n'
            '    static let spareFile = "spare_probe.txt"\n'
            "\n"
            "    static func run(_ view: ChatView) async {\n"
            "        let report = SweepReport(file: reportFile)\n"
            "    }\n"
            "}\n"
        )
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "DebugFeatureProbes.swift").write_text(source, encoding="utf-8")
            original = runner.PROBE_DIR
            runner.PROBE_DIR = Path(folder)
            try:
                found = {item.name: item.reports for item in runner.discover_scenarios()}
            finally:
                runner.PROBE_DIR = original
        self.assertEqual(found, {"localprobe": ("local_probe.txt",)})


if __name__ == "__main__":
    unittest.main()
