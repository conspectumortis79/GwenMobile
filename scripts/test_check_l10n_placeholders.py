#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_l10n_placeholders as placeholders


class PlaceholderTests(unittest.TestCase):
    def build(self, folder: str, strings: dict, source: str) -> Path:
        root = Path(folder)
        (root / "Localization").mkdir(parents=True)
        for language, table in strings.items():
            (root / "Localization" / f"{language}.strings").write_text(table, encoding="utf-8")
        (root / "GwenMobile").mkdir(parents=True)
        (root / "GwenMobile" / "Code.swift").write_text(source, encoding="utf-8")
        return root

    def table(self, de: str, en: str = "", es: str = "", fr: str = "") -> dict:
        return {"de": de, "en": en or de, "es": es or de, "fr": fr or de}

    def test_a_matching_call_is_quiet(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"cal_created" = "Termin: %@";\n'),
                              'L.fmt("cal_created", "Zahnarzt")\n')
            self.assertEqual(placeholders.check(root), [])

    def test_a_two_slot_key_behind_fmt_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"place_route" = "Von %@ nach %@";\n'),
                              'L.fmt("place_route", "A")\n')
            problems = placeholders.check(root)
            self.assertEqual(len(problems), 4)
            self.assertIn("expected 1 %@, found 2", problems[0])

    def test_a_one_slot_key_behind_fmt2_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"file_too_big" = "Bis %@";\n'),
                              'L.fmt2("file_too_big", "A", "B")\n')
            self.assertIn("expected 2 %@, found 1", placeholders.check(root)[0])

    def test_a_count_key_without_a_d_placeholder_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"pictures_selected" = "Ausgewählt";\n'),
                              'L.n("pictures_selected", 2)\n')
            self.assertIn("no %d placeholder", placeholders.check(root)[0])

    def test_a_counted_call_checks_both_keys(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"lines_one" = "1 Zeile";\n"lines" = "%d Zeilen";\n'),
                              'L.counted(block.lines.count - 1, one: "lines_one",\n          many: "lines")\n')
            self.assertEqual(placeholders.check(root), [])
            self.assertEqual([call[2:] for call in placeholders.source_calls(root)],
                             [("counted_one", "lines_one"), ("counted_many", "lines")])

    def test_a_counted_call_with_a_placeholder_for_one_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"lines_one" = "%d Zeile";\n"lines" = "Zeilen";\n'),
                              'L.counted(count, one: "lines_one", many: "lines")\n')
            problems = placeholders.check(root)
            self.assertEqual(len(problems), 8)
            self.assertIn('L.counted(one: "lines_one") in de: the text for a count of one keeps a placeholder',
                          problems[0])
            self.assertIn('L.counted(many: "lines") in de: no %d placeholder', problems[4])

    def test_an_interpolated_key_is_left_alone(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"call_ambiguous" = "Mehrere: %@";\n'),
                              'L.fmt("\\(keyPrefix)_ambiguous", names)\n')
            self.assertEqual(placeholders.check(root), [])

    def test_an_unknown_key_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, self.table('"known" = "x";\n'), 'L.fmt("unknown", "x")\n')
            self.assertIn("is not defined", placeholders.check(root)[0])

    def test_a_language_without_the_key_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            strings = self.table('"known" = "%@";\n')
            strings["en"] = ""
            root = self.build(folder, strings, 'L.fmt("known", "x")\n')
            self.assertIn("is missing in Localization/en.strings", placeholders.check(root)[0])


if __name__ == "__main__":
    unittest.main()
