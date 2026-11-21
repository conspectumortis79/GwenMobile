#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import importlib

sync = importlib.import_module("sync-infoplist-strings")


class InfoPlistStringsTests(unittest.TestCase):
    def build(self, folder: str, values: dict, files: dict) -> Path:
        root = Path(folder)
        (root / "GwenMobile").mkdir(parents=True)
        with sync.info_plist(root).open("wb") as handle:
            plistlib.dump(values, handle)
        for language, text in files.items():
            folder_path = root / "GwenMobile" / f"{language}.lproj"
            folder_path.mkdir(parents=True)
            (folder_path / "InfoPlist.strings").write_text(text, encoding="utf-8")
        return root

    def full_files(self, keys: list, extra: dict = None) -> dict:
        files = {}
        for language in sync.LOCALIZATIONS:
            lines = [f'{key} = "{key}";' for key in keys]
            if extra and language in extra:
                lines.append(extra[language])
            files[language] = "\n".join(lines) + "\n"
        return files

    def test_only_usage_descriptions_and_the_display_name_are_expected(self) -> None:
        values = {
            "CFBundleDisplayName": "GwenMobile",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "NSMicrophoneUsageDescription": "micro",
            "UIBackgroundModes": ["audio"],
        }
        self.assertEqual(sync.localizable_keys(values),
                         ["CFBundleDisplayName", "NSMicrophoneUsageDescription"])

    def test_a_missing_translation_is_reported(self) -> None:
        keys = ["CFBundleDisplayName", "NSMicrophoneUsageDescription"]
        with tempfile.TemporaryDirectory() as folder:
            files = self.full_files(keys)
            files["es"] = files["es"].replace('NSMicrophoneUsageDescription = "NSMicrophoneUsageDescription";\n', "")
            root = self.build(folder, {"CFBundleDisplayName": "GwenMobile",
                                       "NSMicrophoneUsageDescription": "micro"}, files)
            problems = sync.audit(root)
            self.assertEqual(len(problems), 1)
            self.assertIn("NSMicrophoneUsageDescription", problems[0])
            self.assertIn("es.lproj", problems[0])

    def test_a_file_key_that_is_not_in_the_plist_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            files = self.full_files(["CFBundleDisplayName"],
                                    extra={"en": 'NSOldUsageDescription = "old";'})
            root = self.build(folder, {"CFBundleDisplayName": "GwenMobile"}, files)
            problems = sync.audit(root)
            self.assertEqual(len(problems), 1)
            self.assertIn("NSOldUsageDescription", problems[0])

    def test_syncing_fills_new_english_keys_and_refreshes_values(self) -> None:
        keys = ["CFBundleDisplayName", "NSMicrophoneUsageDescription", "NSCameraUsageDescription"]
        with tempfile.TemporaryDirectory() as folder:
            files = self.full_files(keys)
            files["en"] = ('CFBundleDisplayName = "Alt";\n'
                           'NSMicrophoneUsageDescription = "micro";\n')
            root = self.build(folder, {"CFBundleDisplayName": "GwenMobile",
                                       "NSMicrophoneUsageDescription": "micro",
                                       "NSCameraUsageDescription": "camera"}, files)
            changed = sync.sync_english(root)
            self.assertEqual([(key, after) for key, _, after in changed],
                             [("CFBundleDisplayName", "GwenMobile")])
            text = (root / "GwenMobile" / "en.lproj" / "InfoPlist.strings").read_text(encoding="utf-8")
            self.assertIn('CFBundleDisplayName = "GwenMobile";', text)
            self.assertIn('NSCameraUsageDescription = "camera";', text)
            self.assertEqual(sync.audit(root), [])

    def test_auditing_does_not_change_any_file(self) -> None:
        keys = ["CFBundleDisplayName", "NSMicrophoneUsageDescription"]
        with tempfile.TemporaryDirectory() as folder:
            root = self.build(folder, {"CFBundleDisplayName": "GwenMobile"},
                              self.full_files(keys))
            path = root / "GwenMobile" / "en.lproj" / "InfoPlist.strings"
            before = path.read_text(encoding="utf-8")
            self.assertTrue(sync.audit(root))
            self.assertEqual(path.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
