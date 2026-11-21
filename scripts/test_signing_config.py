#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import signing_config


class WriteTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "Signing.xcconfig"

    def tearDown(self) -> None:
        self.folder.cleanup()

    def test_keeps_every_other_setting_when_the_team_line_is_missing(self) -> None:
        self.path.write_text("GWEN_DIALER = YES\nGWEN_MESSAGING = NO\n", encoding="utf-8")
        signing_config.write_team("ABCDE12345", self.path)
        self.assertEqual(self.path.read_text(encoding="utf-8"),
                         "GWEN_DIALER = YES\nGWEN_MESSAGING = NO\nDEVELOPMENT_TEAM = ABCDE12345\n")
        self.assertEqual(signing_config.current_team(self.path), "ABCDE12345")

    def test_replaces_the_team_line_in_place(self) -> None:
        self.path.write_text("DEVELOPMENT_TEAM = OLDTEAM123\nGWEN_DIALER = NO\nGWEN_MESSAGING = YES",
                             encoding="utf-8")
        signing_config.write_team("ABCDE12345", self.path)
        self.assertEqual(self.path.read_text(encoding="utf-8"),
                         "DEVELOPMENT_TEAM = ABCDE12345\nGWEN_DIALER = NO\nGWEN_MESSAGING = YES\n")

    def test_the_written_team_wins_over_an_unreadable_team_line(self) -> None:
        self.path.write_text("DEVELOPMENT_TEAM = OLDTEAM123 // mine\nGWEN_DIALER = NO", encoding="utf-8")
        signing_config.write_team("ABCDE12345", self.path)
        lines = self.path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[-1], "DEVELOPMENT_TEAM = ABCDE12345")
        self.assertIn("GWEN_DIALER = NO", lines)
        self.assertEqual(signing_config.current_team(self.path), "ABCDE12345")

    def test_a_new_file_starts_from_the_example(self) -> None:
        signing_config.write_team("ABCDE12345", self.path)
        written = self.path.read_text(encoding="utf-8")
        example = signing_config.EXAMPLE.read_text(encoding="utf-8")
        self.assertEqual(written, signing_config.TEAM_LINE.sub("DEVELOPMENT_TEAM = ABCDE12345", example))
        self.assertIn("GWEN_DIALER = NO", written)
        self.assertIn("GWEN_MESSAGING = NO", written)

    def test_an_empty_file_gets_only_the_team_line(self) -> None:
        self.path.write_text("\n\n", encoding="utf-8")
        signing_config.write_team("ABCDE12345", self.path)
        self.assertEqual(self.path.read_text(encoding="utf-8"), "DEVELOPMENT_TEAM = ABCDE12345\n")


if __name__ == "__main__":
    unittest.main()
