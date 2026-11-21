#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_markdown_links as links


class SlugTests(unittest.TestCase):
    def test_punctuation_is_dropped(self) -> None:
        self.assertEqual(links.slug("Texts: localization and prompts"), "texts-localization-and-prompts")

    def test_umlauts_stay(self) -> None:
        self.assertEqual(links.slug("Verlauf löschen"), "verlauf-löschen")

    def test_duplicate_headings_are_numbered(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "doc.md"
            path.write_text("# Titel\n\n## Titel\n\n## Titel\n", encoding="utf-8")
            self.assertEqual(links.anchors(path), {"titel", "titel-1", "titel-2"})


class CheckDocumentTests(unittest.TestCase):
    def document(self, folder: str, text: str):
        root = Path(folder)
        path = root / "doc.md"
        path.write_text(text, encoding="utf-8")
        return path, root

    def test_existing_relative_target_passes(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "other.md").write_text("# Ziel\n", encoding="utf-8")
            path, root = self.document(folder, "siehe [Ziel](other.md#ziel) und [Bild](other.md)\n")
            self.assertEqual(links.check_document(path, root), [])

    def test_missing_target_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path, root = self.document(folder, "siehe [fehlt](missing.md)\n")
            problems = links.check_document(path, root)
            self.assertEqual(len(problems), 1)
            self.assertIn("does not exist", problems[0][2])

    def test_missing_anchor_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "other.md").write_text("# Ziel\n", encoding="utf-8")
            path, root = self.document(folder, "siehe [Ziel](other.md#anderer)\n")
            problems = links.check_document(path, root)
            self.assertEqual(len(problems), 1)
            self.assertIn("anchor missing in the target", problems[0][2])

    def test_intra_document_anchor_is_checked(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path, root = self.document(folder, "# Titel\n\n[ok](#titel) [nein](#fehlt)\n")
            problems = links.check_document(path, root)
            self.assertEqual(len(problems), 1)
            self.assertIn("anchor missing in this file", problems[0][2])

    def test_external_targets_are_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path, root = self.document(folder, "[a](https://example.com/x) [b](mailto:x@y.z)\n")
            self.assertEqual(links.check_document(path, root), [])

    def test_code_blocks_and_inline_code_are_skipped(self) -> None:
        text = "```\n[fehlt](missing.md)\n```\n\n`[fehlt](missing.md)`\n"
        with tempfile.TemporaryDirectory() as folder:
            path, root = self.document(folder, text)
            self.assertEqual(links.check_document(path, root), [])

    def test_html_image_target_is_checked(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path, root = self.document(folder, '<img src="missing.png" alt="x">\n')
            self.assertEqual(len(links.check_document(path, root)), 1)

    def test_prompts_are_not_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            prompt = root / "GwenMobile" / "Resources" / "Prompts"
            prompt.mkdir(parents=True)
            (prompt / "router.md").write_text("[fehlt](missing.md)\n", encoding="utf-8")
            self.assertEqual(links.documents(root), [])


if __name__ == "__main__":
    unittest.main()
