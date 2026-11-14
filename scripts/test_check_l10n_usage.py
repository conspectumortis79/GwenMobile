#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_l10n_usage as usage


class UnusedKeyTests(unittest.TestCase):
    def test_direct_literal_counts_as_used(self) -> None:
        keys = ["used_key", "dead_key"]
        self.assertEqual(usage.unused_keys(keys, 'L.t("used_key")'), ["dead_key"])

    def test_dynamic_prefix_counts_as_used(self) -> None:
        keys = ["memory_cat_work"]
        self.assertEqual(usage.unused_keys(keys, ""), [])

    def test_interpolated_key_counts_as_used(self) -> None:
        keys = ["message_ambiguous"]
        self.assertEqual(usage.unused_keys(keys, ""), [])

    def test_similar_prefix_does_not_hide_a_dead_key(self) -> None:
        keys = ["memory_cats_work"]
        self.assertEqual(usage.unused_keys(keys, ""), ["memory_cats_work"])


class CheckTests(unittest.TestCase):
    def build(self, folder: str, strings: str, source: str) -> Path:
        root = Path(folder)
        (root / "Localization").mkdir(parents=True)
        (root / "Localization" / "de.strings").write_text(strings, encoding="utf-8")
        (root / "GwenMobile").mkdir(parents=True)
        (root / "GwenMobile" / "Code.swift").write_text(source, encoding="utf-8")
        return root

    def test_an_unused_key_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder,
                              '"used" = "x";\n"dead" = "y";\n',
                              'let a = L.t("used")\n')
            self.assertEqual(usage.check(root), ["dead"])

    def test_the_generated_table_is_not_counted_as_usage(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, '"dead" = "y";\n', "")
            (root / "GwenMobile" / "L10nTable.swift").write_text('"dead"', encoding="utf-8")
            self.assertEqual(usage.check(root), ["dead"])

    def test_an_escaped_key_matches_the_swift_literal(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, '"line\\nbreak" = "y";\n', 'L.t("line\\nbreak")')
            self.assertEqual(usage.check(root), [])


if __name__ == "__main__":
    unittest.main()
