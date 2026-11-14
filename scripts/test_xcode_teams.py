#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcode_teams as teams


class XcodeAccountTeamsTests(unittest.TestCase):
    def test_reads_every_team_of_the_signed_in_apple_id(self) -> None:
        preferences = {"IDEProvisioningTeamByIdentifier": {
            "2679826A-6085-4B21-A9AE-227ECF5EEFFF": [{
                "isFreeProvisioningTeam": 1,
                "teamID": "HDR2ZP983J",
                "teamName": "Panagiotis Michailidis (Personal Team)",
            }],
        }}
        self.assertEqual(teams.teams_in_xcode_accounts(preferences), ["HDR2ZP983J"])

    def test_accepts_a_record_without_the_list_wrapper(self) -> None:
        preferences = {"IDEProvisioningTeamByIdentifier": {
            "KEY": {"teamID": "ABCDE12345", "teamName": "Paid Team"},
        }}
        self.assertEqual(teams.teams_in_xcode_accounts(preferences), ["ABCDE12345"])

    def test_ignores_invalid_team_ids_and_other_keys(self) -> None:
        preferences = {
            "IDEProvisioningTeamByIdentifier": {
                "A": [{"teamID": "zu-kurz"}, {"teamID": "lowercase1"}],
                "B": "kein dict",
            },
            "Andere": [{"teamID": "ABCDE12345"}],
        }
        self.assertEqual(teams.teams_in_xcode_accounts(preferences), [])

    def test_deduplicates_and_keeps_order(self) -> None:
        preferences = {"IDEProvisioningTeamByIdentifier": {
            "A": [{"teamID": "ABCDE12345"}],
            "B": [{"teamID": "ABCDE12345"}, {"teamID": "FGHIJ67890"}],
        }}
        self.assertEqual(teams.teams_in_xcode_accounts(preferences), ["ABCDE12345", "FGHIJ67890"])

    def test_a_missing_key_yields_nothing(self) -> None:
        self.assertEqual(teams.teams_in_xcode_accounts({}), [])


if __name__ == "__main__":
    unittest.main()
