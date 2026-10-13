#!/usr/bin/env python3
"""Tests for check_doc_references.py. Run: python3 -m unittest discover -s scripts -p 'test_*.py'"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_doc_references as checker  # noqa: E402

SOURCE = "Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift"


def repo(files):
    return checker.Repository("/nonexistent", files.keys(), read=lambda path: files[path])


def findings(files, external=None, removed=None):
    return [str(f) for f in checker.check(repo(files), external or {}, removed or set())]


def with_doc(doc, extra=None):
    files = {
        SOURCE: "final class HistoryToDoseMapper {\n    func mapToEvents() {}\n}\n",
        "Sources/TandemCore/Messages/Authentication/Jpake3SessionKey.swift": "class Jpake3SessionKeyRequest {}\n",
        "docs/guide.md": "# Guide\n\n## The `HistoryToDoseMapper` & friends\n\n## Twice\n\n## Twice\n",
        "docs/doc.md": doc,
    }
    files.update(extra or {})
    return files


class CodeNameTests(unittest.TestCase):
    def test_a_name_the_code_declares_passes(self):
        self.assertEqual(findings(with_doc("`HistoryToDoseMapper.mapToEvents()` runs.\n")), [])

    def test_a_name_nothing_declares_is_reported_at_its_line(self):
        result = findings(with_doc("Intro.\n\n`HistoryReconciler` matches doses.\n"))
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0].startswith("docs/doc.md:3: `HistoryReconciler` names nothing"), result)

    def test_a_member_after_a_dot_is_checked(self):
        result = findings(with_doc("`HistoryToDoseMapper.reconcileDoses()`\n"))
        self.assertEqual(len(result), 1)
        self.assertIn("`reconcileDoses`", result[0])

    def test_a_file_name_vouches_for_the_message_it_holds(self):
        self.assertEqual(findings(with_doc("`Jpake3SessionKey` then `Jpake4KeyConfirmation`\n")), [
            "docs/doc.md:1: `Jpake4KeyConfirmation` names nothing in the code. Use the name the code has "
            "now, or drop it; if it lives in another codebase, add it to EXTERNAL, and if the doc says "
            "it is gone, to REMOVED, in scripts/check_doc_references.py."
        ])

    def test_plain_words_snake_case_and_endpoints_are_not_code_names(self):
        self.assertEqual(findings(with_doc("`raw`, `true`, `basal_cycle_enabled`, `POST /api/state/bolus/start`\n")), [])

    def test_a_fenced_block_is_not_checked(self):
        self.assertEqual(findings(with_doc("```swift\nlet x = `HistoryReconciler`\n```\n")), [])

    def test_bundle_identifiers_and_shell_are_not_code(self):
        self.assertEqual(findings(with_doc("`group.com.$TEAM.loopkit.LoopGroup`\n")), [])

    def test_the_project_file_does_not_vouch_for_a_name(self):
        files = with_doc("`HistoryReconciler`\n", {
            "TandemKit.xcodeproj/project.pbxproj": "HistoryReconciler.swift in Sources",
        })
        self.assertEqual(len(findings(files)), 1)

    def test_the_checkers_own_lists_do_not_vouch_for_a_name(self):
        files = with_doc("`HistoryReconciler`\n", {
            "scripts/check_doc_references.py": 'REMOVED = {"HistoryReconciler"}\n',
        })
        self.assertEqual(len(findings(files)), 1)


class PathTests(unittest.TestCase):
    def test_a_path_under_a_top_level_directory_must_exist(self):
        result = findings(with_doc(f"`{SOURCE}` and `Sources/TandemKit/PumpManager/History/HistoryReconciler.swift`\n"))
        self.assertEqual(len(result), 1)
        self.assertIn("`Sources/TandemKit/PumpManager/History/HistoryReconciler.swift` is not in the repository", result[0])

    def test_a_directory_with_a_trailing_slash_exists(self):
        self.assertEqual(findings(with_doc("`Sources/TandemKit/PumpManager/History/`\n")), [])

    def test_placeholders_and_globs_match_any_name(self):
        self.assertEqual(findings(with_doc("`Sources/<Module>/PumpManager/History/*Mapper.swift`\n")), [])
        self.assertEqual(len(findings(with_doc("`Sources/<Module>/PumpManager/History/*Reconciler.swift`\n"))), 1)

    def test_a_swift_file_named_anywhere_must_exist_somewhere(self):
        self.assertEqual(findings(with_doc("`HistoryToDoseMapper.swift`, `History/HistoryToDoseMapper.swift:12`\n")), [])
        self.assertEqual(len(findings(with_doc("`HistoryReconciler.swift`\n"))), 1)

    def test_a_hidden_top_level_path_is_checked_and_a_bare_extension_is_not(self):
        workflow = {".github/workflows/linux.yml": "jobs:\n"}
        self.assertEqual(findings(with_doc("`.github/workflows/linux.yml` checks every `.swift` file\n", workflow)), [])
        self.assertEqual(len(findings(with_doc("`.github/workflows/gone.yml`\n", workflow))), 1)

    def test_another_codebases_relative_path_is_not_checked(self):
        self.assertEqual(findings(with_doc("`settings/settings.json`, `pkg/state/delivery.go`, `loopandlearn/LoopKit`\n")), [])


class LinkTests(unittest.TestCase):
    def test_a_link_to_a_missing_file_is_reported(self):
        result = findings(with_doc("See [the plan](plan.md) and [the guide](guide.md).\n"))
        self.assertEqual(result, ["docs/doc.md:1: the link to `plan.md` leads to no file in the repository."])

    def test_an_anchor_must_name_a_heading(self):
        doc = "[a](guide.md#the-historytodosemapper--friends) [b](guide.md#twice-1) [c](guide.md#gone) [d](#nowhere)\n"
        self.assertEqual(findings(with_doc(doc)), [
            "docs/doc.md:1: the link to `guide.md#gone` names no heading in `docs/guide.md`.",
            "docs/doc.md:1: the link to `#nowhere` names no heading in `docs/doc.md`.",
        ])

    def test_a_link_up_and_out_of_docs_resolves_from_the_doc(self):
        self.assertEqual(findings(with_doc(f"[mapper](../{SOURCE})\n")), [])

    def test_web_links_are_not_checked(self):
        self.assertEqual(findings(with_doc("[LoopKit](https://github.com/LoopKit/LoopKit/blob/dev/x.md#y)\n")), [])


class ListTests(unittest.TestCase):
    def test_an_external_name_passes(self):
        self.assertEqual(findings(with_doc("Trio's `PumpConfig`\n"), external={"PumpConfig": "Trio"}), [])

    def test_an_external_name_no_doc_cites_is_reported(self):
        self.assertEqual(findings(with_doc("Nothing.\n"), external={"PumpConfig": "Trio"}), [
            "scripts/check_doc_references.py: EXTERNAL lists `PumpConfig`, which no doc cites any more; remove it."
        ])

    def test_an_external_name_the_code_has_is_reported(self):
        result = findings(with_doc("`HistoryToDoseMapper`\n"), external={"HistoryToDoseMapper": "Trio"})
        self.assertEqual(result, [
            "scripts/check_doc_references.py: EXTERNAL lists `HistoryToDoseMapper`, which the code now names; remove it."
        ])

    def test_a_removed_name_passes_while_the_code_lacks_it(self):
        self.assertEqual(findings(with_doc("`HistoryReconciler` is gone.\n"), removed={"HistoryReconciler"}), [])

    def test_a_removed_name_back_in_the_code_fails_the_docs_that_call_it_gone(self):
        result = findings(with_doc("`HistoryToDoseMapper` is gone.\n"), removed={"HistoryToDoseMapper"})
        self.assertEqual(len(result), 1)
        self.assertIn("REMOVED lists `HistoryToDoseMapper`, but the code has it again", result[0])
        self.assertIn(SOURCE, result[0])

    def test_a_comment_naming_a_removed_type_does_not_bring_it_back(self):
        files = with_doc("`HistoryReconciler` is gone.\n", {
            "Sources/TandemKit/Notes.swift": "// Replaces HistoryReconciler.\n/* HistoryReconciler */\nlet x = 1\n",
        })
        self.assertEqual(findings(files, removed={"HistoryReconciler"}), [])

    def test_a_removed_name_no_doc_cites_is_reported(self):
        self.assertEqual(findings(with_doc("Nothing.\n"), removed={"HistoryReconciler"}), [
            "scripts/check_doc_references.py: REMOVED lists `HistoryReconciler`, which no doc cites any more; remove it."
        ])


class SlugTests(unittest.TestCase):
    def test_slugs_match_githubs(self):
        self.assertEqual(checker.slug("Trio in the simulator"), "trio-in-the-simulator")
        self.assertEqual(checker.slug("A. Interrupt everything (§10, P12; #326)"), "a-interrupt-everything-10-p12-326")
        self.assertEqual(checker.slug("Pump manager — `Sources/TandemKit/PumpManager/`"), "pump-manager--sourcestandemkitpumpmanager")


if __name__ == "__main__":
    unittest.main()
