#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import datetime
import io
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mac_app
import mac_storage
import renew_report
import renew_state
import renew_targets
import renewal_policy
import renewal_schedule
import signing_reader
import signing_state

TEAM = "TEAMPLACEH"
BUNDLE = "com.mortis.gwenmobile"
IPHONE = signing_state.TargetSpec("iphone", "iPhone", signing_state.IOS, BUNDLE)
MAC = signing_state.TargetSpec("mac", "Mac (Catalyst)", signing_state.MAC, BUNDLE)
MOMENT = datetime.datetime(2026, 9, 26, 12, 0, tzinfo=datetime.timezone.utc)
IOS_NAME = "iOS Team Provisioning Profile: " + BUNDLE
MAC_NAME = "Mac Catalyst Team Provisioning Profile: maccatalyst." + BUNDLE
TESTS_NAME = "Mac Catalyst Team Provisioning Profile: com.mortis.GwenMobileTests"


@contextlib.contextmanager
def quiet():
    with contextlib.redirect_stdout(io.StringIO()) as captured:
        yield captured


def raw(name: str, identifier: str, days: float) -> dict:
    return {"Name": name, "TeamIdentifier": [TEAM], "TeamName": "Team Owner",
            "Entitlements": {"application-identifier": f"{TEAM}.{identifier}"},
            "CreationDate": MOMENT - datetime.timedelta(days=7 - days),
            "ExpirationDate": MOMENT + datetime.timedelta(days=days),
            "ProvisionedDevices": ["00000000-0000000000000000"]}


def profile(name: str = IOS_NAME, identifier: str = BUNDLE, days: float = 7.0,
            suffix: str = ".mobileprovision", folder: Path | None = None) -> signing_state.Profile:
    path = (folder or Path("/tmp")) / f"{identifier.replace('.', '-')}{suffix}"
    return signing_state.parse(raw(name, identifier, days), path)


def mac_profile(days: float = 7.0, folder: Path | None = None) -> signing_state.Profile:
    return profile(MAC_NAME, "maccatalyst." + BUNDLE, days, ".provisionprofile", folder)


def tests_profile(days: float = 2.0) -> signing_state.Profile:
    return profile(TESTS_NAME, "com.mortis.GwenMobileTests", days, ".provisionprofile")


def state_of(*profiles) -> signing_state.SigningState:
    return signing_state.SigningState(profiles, MOMENT)


class FakePlan:
    title = "iPhone"

    def __init__(self, renew: bool = True, days_left: float | None = 1.5, spec=IPHONE):
        self.renew = renew
        self.days_left = days_left
        self.spec = spec
        self.target_id = spec.id
        self.reason = "the profile runs out in 1.5 days (threshold 2.0)"

    def profile_text(self) -> str:
        return "profile text"


def outcome_of(ok: bool = True, expires=None, detail: str = "", manual: str = "",
               note: str = "") -> renew_targets.Outcome:
    return renew_targets.Outcome(plan=FakePlan(), ok=ok, detail=detail, manual=manual, note=note,
                                 expires=expires)


class FakeCache:
    def __init__(self, profiles=()):
        self.profiles = tuple(profiles)

    def all(self, spec):
        return self.profiles

    def newest(self, spec):
        return self.profiles[0] if self.profiles else None


class FakeMacActions:
    built_path = Path("/build/GwenMobile.app")

    def __init__(self, build_fails: bool = False, running: tuple = (), profile_value=None,
                 installed=None, built=None):
        self.calls = []
        self.build_fails = build_fails
        self.running_value = running
        self.profile_value = profile_value
        self.installed = installed
        self.built = built

    def store(self, bundle):
        self.calls.append("store")
        return self.built if Path(bundle) == self.built_path else self.installed

    def prepare(self, options):
        self.calls.append("prepare")

    def build(self, options):
        self.calls.append("build")
        self.chosen = options.configuration
        if self.build_fails:
            raise SystemExit("xcodebuild failed")
        return self.built_path

    def verify(self, app, configuration):
        self.calls.append("verify")
        self.configuration = configuration

    def install(self, app, target):
        self.calls.append("install")
        return target

    def register(self, target):
        self.calls.append("register")

    def profile(self, target):
        self.calls.append("profile")
        return self.profile_value

    def running(self, target):
        return self.running_value

    def relaunch(self, target):
        self.calls.append("relaunch")


class FakeDevice:
    def __init__(self, name="Phone", link="connected", udid="00000000-0000000000000000"):
        self.udid = udid
        self.name = name
        self.model = "iPhone 16"
        self.system = "27.0"
        self.link = link

    def label(self) -> str:
        return self.name


class FakePhoneActions:
    def __init__(self, devices=(), reachable=(), reason="unlockedSinceBoot: true"):
        self.device_list = tuple(devices)
        self.reachable_names = tuple(reachable)
        self.reason = reason
        self.probes = []

    def devices(self):
        return self.device_list

    def reachable(self, device):
        self.probes.append(device.name)
        return device.name in self.reachable_names, self.reason


class ProfileModelTest(unittest.TestCase):
    def test_ios_profile_carries_the_device_kind(self):
        item = profile()
        self.assertEqual(item.kind, signing_state.IOS)
        self.assertTrue(item.matches(BUNDLE))
        self.assertAlmostEqual(item.days_left(MOMENT), 7.0, places=6)
        self.assertEqual(item.state(MOMENT), "active")
        self.assertIn("active until 2026-10-03 12:00  (7.0 days)", item.describe(MOMENT))

    def test_catalyst_profile_matches_the_same_bundle_id(self):
        item = mac_profile(days=4)
        self.assertEqual(item.kind, signing_state.MAC)
        self.assertTrue(item.matches(BUNDLE))

    def test_the_test_bundle_is_not_confused_with_the_app(self):
        self.assertFalse(tests_profile().matches(BUNDLE))

    def test_expiry_from_the_stored_date(self):
        item = profile(days=-1)
        self.assertEqual(item.state(MOMENT), "expired")
        self.assertLess(item.days_left(MOMENT), 0)

    def test_a_naive_moment_is_read_as_local_wall_clock(self):
        item = profile(days=7)
        naive_local = MOMENT.astimezone().replace(tzinfo=None)
        self.assertAlmostEqual(item.days_left(naive_local), 7.0, places=6)

    def test_a_profile_without_an_expiry_date_stays_visible(self):
        payload = raw(IOS_NAME, BUNDLE, 1)
        payload.pop("ExpirationDate")
        item = signing_state.parse(payload, Path("no-expiry.mobileprovision"))
        self.assertIsNone(item.expires)
        self.assertIsNone(item.days_left(MOMENT))
        self.assertEqual(item.state(MOMENT), "no expiry date")
        self.assertIn("unknown", item.describe(MOMENT))


class TargetSelectionTest(unittest.TestCase):
    def setUp(self):
        self.ios = profile(days=7)
        self.ios_old = profile(days=3)
        self.mac = mac_profile(days=9)
        self.tests = tests_profile()
        self.state = state_of(self.ios, self.ios_old, self.mac, self.tests)

    def test_a_target_only_sees_profiles_of_its_own_kind(self):
        self.assertEqual(self.state.for_target(IPHONE), (self.ios, self.ios_old))
        self.assertEqual(self.state.for_target(MAC), (self.mac,))

    def test_the_longest_running_profile_decides(self):
        self.assertEqual(self.state.newest(IPHONE), self.ios)
        self.assertAlmostEqual(self.state.days_left(IPHONE), 7.0, places=6)

    def test_the_explicit_profile_wins_over_a_wildcard(self):
        wildcard = profile("iOS Team Provisioning Profile: *", "*", 20)
        self.assertEqual(state_of(self.ios, wildcard).for_target(IPHONE), (self.ios,))

    def test_a_state_without_profiles_reports_nothing(self):
        empty = state_of()
        self.assertEqual(empty.for_target(IPHONE), ())
        self.assertIsNone(empty.newest(IPHONE))
        self.assertIsNone(empty.days_left(IPHONE))

    def test_an_unknown_target_id_is_rejected(self):
        with self.assertRaises(ValueError):
            renewal_policy.selected((IPHONE, MAC), ("iphone", "watch"))

    def test_selection_keeps_the_repository_order(self):
        self.assertEqual(renewal_policy.selected((IPHONE, MAC), ("mac",)), (MAC,))

    def test_all_wanted_targets_everything(self):
        self.assertEqual(len(renewal_policy.selected((IPHONE, MAC), ("all",))), 2)


class PolicyTest(unittest.TestCase):
    def test_a_valid_profile_is_left_alone(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=5)), threshold=2.0)
        self.assertEqual(plans[0].renew, False)
        self.assertIn("nothing to do", plans[0].reason)

    def test_below_the_threshold_the_profile_is_renewed(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=1.5)), threshold=2.0)
        self.assertEqual(plans[0].renew, True)
        self.assertIn("threshold", plans[0].reason)

    def test_an_expired_profile_is_reported_as_expired(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=-0.5)), threshold=2.0)
        self.assertIn("expired", plans[0].reason)

    def test_a_profile_without_expiry_is_renewed(self):
        payload = raw(IOS_NAME, BUNDLE, 1)
        payload.pop("ExpirationDate")
        item = signing_state.parse(payload, Path("odd.mobileprovision"))
        plans = renewal_policy.decide((IPHONE,), state_of(item), threshold=2.0)
        self.assertIn("no expiry date", plans[0].reason)

    def test_a_missing_profile_is_a_renewal_for_that_target_only(self):
        plans = renewal_policy.decide((IPHONE, MAC), state_of(mac_profile(days=6)), threshold=2.0)
        self.assertEqual([(item.target_id, item.renew) for item in plans],
                         [("iphone", True), ("mac", False)])
        self.assertIn("no provisioning profile", plans[0].reason)

    def test_force_renews_even_a_long_valid_profile(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0,
                                      force=True)
        self.assertIn("--force", plans[0].reason)

    def test_due_and_kept_split_the_plans(self):
        plans = renewal_policy.decide((IPHONE, MAC), state_of(profile(days=7), mac_profile(1)),
                                      threshold=2.0)
        self.assertEqual([item.target_id for item in renewal_policy.due(plans)], ["mac"])
        self.assertEqual([item.target_id for item in renewal_policy.kept(plans)], ["iphone"])

    def test_targets_limit_the_plans(self):
        plans = renewal_policy.decide((IPHONE, MAC), state_of(), wanted=("mac",))
        self.assertEqual([item.target_id for item in plans], ["mac"])

    def test_a_plan_describes_itself(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0)
        self.assertIn("keep", plans[0].describe())


class DeviceChoiceTest(unittest.TestCase):
    def test_a_wanted_device_is_found_by_name_or_udid(self):
        device = FakeDevice()
        self.assertEqual(renew_targets.choose((device,), "Phone"), device)
        self.assertEqual(renew_targets.choose((device,), device.udid.lower()), device)

    def test_an_unknown_device_stops_the_run(self):
        self.assertIsNone(renew_targets.choose((FakeDevice(),), "Other"))

    def test_a_single_paired_device_is_taken_without_a_wish(self):
        device = FakeDevice()
        self.assertEqual(renew_targets.choose((device,), ""), device)

    def test_several_devices_without_a_decision_stay_untouched(self):
        devices = (FakeDevice("One"), FakeDevice("Two"))
        self.assertIsNone(renew_targets.choose(devices, ""))

    def test_an_empty_device_list_yields_nothing(self):
        self.assertIsNone(renew_targets.choose((), ""))

    def test_a_paired_device_is_taken_although_the_list_says_disconnected(self):
        device = FakeDevice(link="disconnected")
        actions = FakePhoneActions((device,), reachable=("Phone",))
        with quiet():
            picked = renew_targets.wait_for_device(actions, "", 0, sleep=lambda _s: None,
                                                   clock=lambda: 0)
        self.assertEqual(picked, device)
        self.assertEqual(actions.probes, ["Phone"])

    def test_the_link_field_never_decides_alone(self):
        device = FakeDevice(link="connected")
        actions = FakePhoneActions((device,), reachable=())
        with quiet():
            picked = renew_targets.wait_for_device(actions, "", 0, sleep=lambda _s: None,
                                                   clock=lambda: 0)
        self.assertIsNone(picked)

    def test_waiting_gives_up_after_the_deadline(self):
        clock = iter((0, 10, 20, 30))
        sleeps = []
        actions = FakePhoneActions((FakeDevice(),), reachable=())
        with quiet():
            picked = renew_targets.wait_for_device(actions, "", 0.25, sleep=sleeps.append,
                                                   clock=lambda: next(clock, 100))
        self.assertIsNone(picked)
        self.assertEqual(sleeps, [5])

    def test_waiting_returns_a_device_that_becomes_reachable_later(self):
        actions = FakePhoneActions((FakeDevice(),), reachable=())
        rounds = iter((False, False, True))

        def probe(device):
            answer = next(rounds)
            return answer, "unlockedSinceBoot: true"

        actions.reachable = probe
        clock = iter((0, 10, 20, 30, 40))
        with quiet():
            picked = renew_targets.wait_for_device(actions, "", 5, sleep=lambda _s: None,
                                                   clock=lambda: next(clock, 100))
        self.assertEqual(picked.name, "Phone")

    def test_the_hint_names_the_real_reason(self):
        actions = FakePhoneActions((FakeDevice(link="disconnected"),), reachable=(),
                                   reason="device is locked")
        text = renew_targets.device_hint(actions, "")
        self.assertIn("paired but devicectl cannot reach it", text)
        self.assertIn("device is locked", text)
        self.assertIn("disconnected", text)

    def test_the_hint_asks_for_a_decision_between_several_devices(self):
        actions = FakePhoneActions((FakeDevice("One"), FakeDevice("Two")), reachable=())
        self.assertIn("--device", renew_targets.device_hint(actions, "Three"))


class MacRenewalTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        self.cached = mac_profile(days=6, folder=root)
        self.stored = self.cached.path
        self.stored.write_text("profile")
        self.cache = FakeCache((self.cached,))
        self.options = renew_targets.Options(backup_root=root / "backup",
                                             mac_target=root / "GwenMobile.app")

    def renew_with(self, actions, options=None, spec=MAC) -> renew_targets.Outcome:
        with quiet():
            return renew_targets.MacRenewal(options or self.options, actions,
                                            self.cache).renew(FakePlan(spec=spec))

    def test_a_failed_build_returns_the_profile_to_the_cache(self):
        outcome = self.renew_with(FakeMacActions(build_fails=True))
        self.assertEqual(outcome.ok, False)
        self.assertIn("xcodebuild failed", outcome.detail)
        self.assertTrue(self.stored.is_file())
        self.assertIn("nothing was lost", outcome.note)

    def test_a_successful_run_walks_the_whole_chain(self):
        actions = FakeMacActions(profile_value=mac_profile(days=7))
        outcome = self.renew_with(actions)
        self.assertEqual(actions.calls, ["prepare", "store", "build", "verify", "store", "install",
                                         "register", "profile"])
        self.assertEqual(outcome.ok, True)
        self.assertFalse(self.stored.exists())
        self.assertIn(str(self.options.mac_target), outcome.detail)
        self.assertIsNotNone(outcome.expires)

    def test_the_target_configuration_reaches_build_and_verification(self):
        actions = FakeMacActions(profile_value=mac_profile(days=7))
        spec = signing_state.TargetSpec("mac", "Mac (Catalyst)", signing_state.MAC, BUNDLE, "Release")
        with quiet():
            self.renew_with(actions, spec=spec)
        self.assertEqual(actions.chosen, "Release")
        self.assertEqual(actions.configuration, "Release")

    def test_an_explicit_option_wins_over_the_target_default(self):
        actions = FakeMacActions(profile_value=mac_profile(days=7))
        options = renew_targets.Options(backup_root=self.options.backup_root,
                                        mac_target=self.options.mac_target, configuration="Debug")
        with quiet():
            self.renew_with(actions, options=options)
        self.assertEqual(actions.chosen, "Debug")

    def test_a_running_mac_app_is_reported_but_not_touched(self):
        actions = FakeMacActions(running=("123",), profile_value=mac_profile(days=7))
        outcome = self.renew_with(actions)
        self.assertIn("running instance", outcome.note)
        self.assertNotIn("relaunch", actions.calls)

    def test_restart_mac_relaunches_the_app(self):
        actions = FakeMacActions(running=(), profile_value=mac_profile(days=7))
        options = renew_targets.Options(backup_root=self.options.backup_root,
                                        mac_target=self.options.mac_target, restart_mac=True)
        outcome = self.renew_with(actions, options)
        self.assertIn("relaunch", actions.calls)
        self.assertIn("restarted", outcome.note)

    def test_the_install_reports_nothing_when_both_builds_share_one_store(self):
        home = Path("/home/dev")
        store = mac_storage.SettingsStore("maccatalyst." + BUNDLE, True, home)
        actions = FakeMacActions(profile_value=mac_profile(days=7), installed=store, built=store)
        outcome = self.renew_with(actions)
        self.assertEqual(outcome.manual, "")

    def test_an_install_that_moves_the_settings_store_is_reported(self):
        home = Path("/home/dev")
        identity = "maccatalyst." + BUNDLE
        actions = FakeMacActions(profile_value=mac_profile(days=7),
                                 installed=mac_storage.SettingsStore(identity, False, home),
                                 built=mac_storage.SettingsStore(identity, True, home))
        outcome = self.renew_with(actions)
        self.assertTrue(outcome.ok)
        self.assertIn("settings store changes", outcome.manual)
        self.assertIn(str(home / "Library/Preferences" / f"{identity}.plist"), outcome.manual)
        self.assertIn(str(home / "Library/Containers" / identity / "Data"), outcome.manual)


class FakeEntitlements:
    def __init__(self, values: dict):
        self.values = values
        self.asks = []

    def entitlements(self, bundle):
        self.asks.append(Path(bundle))
        return self.values


class FakeIdentity:
    def __init__(self, value: str):
        self.value = value

    def bundle_id(self, bundle):
        return self.value


class MacStorageTest(unittest.TestCase):
    HOME = Path("/home/dev")
    IDENTITY = "maccatalyst.com.mortis.gwenmobile"

    def store(self, sandboxed: bool) -> mac_storage.SettingsStore:
        return mac_storage.SettingsStore(self.IDENTITY, sandboxed, self.HOME)

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.bundle = Path(folder.name) / "GwenMobile.app"
        self.bundle.mkdir()

    def stores(self, entitlements: dict, identity: str = "x") -> mac_storage.SettingsStores:
        return mac_storage.SettingsStores(FakeEntitlements(entitlements), FakeIdentity(identity),
                                          self.HOME)

    def test_a_plain_build_reads_its_settings_from_the_user_library(self):
        self.assertEqual(self.store(False).preferences,
                         self.HOME / "Library/Preferences" / f"{self.IDENTITY}.plist")
        self.assertEqual(self.store(False).support, self.HOME / "Library/Application Support")

    def test_a_sandboxed_build_reads_its_settings_from_its_container(self):
        expected = self.HOME / "Library/Containers" / self.IDENTITY / "Data"
        self.assertEqual(self.store(True).preferences,
                         expected / "Library/Preferences" / f"{self.IDENTITY}.plist")
        self.assertEqual(self.store(True).support, expected / "Library/Application Support")

    def test_the_container_name_follows_the_bundle_id_of_the_build(self):
        plain = mac_storage.SettingsStore("com.mortis.gwenmobile", True, self.HOME)
        self.assertIn("com.mortis.gwenmobile", str(plain.preferences))
        self.assertNotIn("maccatalyst", str(plain.preferences))

    def test_a_missing_bundle_has_no_store_at_all(self):
        stores = self.stores({mac_storage.SANDBOX: True}, self.IDENTITY)
        self.assertIsNone(stores.of(self.HOME / "Absent.app"))

    def test_a_bundle_without_an_identifier_has_no_store(self):
        stores = self.stores({mac_storage.SANDBOX: True}, "")
        self.assertIsNone(stores.of(self.bundle))

    def test_the_store_follows_the_sandbox_entitlement(self):
        sandboxed = self.stores({mac_storage.SANDBOX: True}, self.IDENTITY).of(self.bundle)
        plain = self.stores({}, self.IDENTITY).of(self.bundle)
        self.assertEqual(sandboxed.sandboxed, True)
        self.assertEqual(plain.sandboxed, False)
        self.assertEqual(plain.bundle_id, self.IDENTITY)

    def test_the_warning_stays_quiet_for_the_same_store(self):
        self.assertEqual(mac_storage.shift_warning(self.store(True), self.store(True)), "")
        self.assertEqual(mac_storage.shift_warning(None, self.store(True)), "")
        self.assertEqual(mac_storage.shift_warning(self.store(True), None), "")

    def test_the_warning_names_both_stores_and_the_bundle_id(self):
        text = mac_storage.shift_warning(self.store(False), self.store(True))
        self.assertIn("settings store changes", text)
        self.assertIn(self.IDENTITY, text)
        self.assertIn("MacOS/GwenMobile.entitlements", text)

    def test_entitlements_are_read_out_of_the_codesign_output(self):
        body = plistlib.dumps({mac_storage.SANDBOX: True}, fmt=plistlib.FMT_XML).decode("utf-8")
        for text in (body,
                     "Executable=/somewhere/GwenMobile\n" + body,
                     body + "\nExecutable=/somewhere/GwenMobile\n"):
            with self.subTest(text=text[:24]):
                self.assertEqual(mac_app.CodesignEntitlements(lambda bundle: text)
                                 .entitlements(self.bundle), {mac_storage.SANDBOX: True})

    def test_unreadable_entitlements_answer_with_an_empty_dict(self):
        for text in ("", "Code Signing Error: not signed", "<?xml not a plist",
                     "<?xml version=" "?><plist><dict></plist>"):
            with self.subTest(text=text):
                self.assertEqual(mac_app.CodesignEntitlements(lambda bundle: text)
                                 .entitlements(self.bundle), {})

    def test_a_missing_bundle_identifier_is_not_reported_as_a_store(self):
        for value in ("", "?"):
            with self.subTest(value=value):
                self.assertEqual(mac_app.InfoPlistBundleId(lambda bundle, key: value)
                                 .bundle_id(self.bundle), "")
        self.assertEqual(mac_app.InfoPlistBundleId(lambda bundle, key: self.IDENTITY)
                         .bundle_id(self.bundle), self.IDENTITY)


class MacBuildAgreementTest(unittest.TestCase):
    def test_the_project_signs_every_catalyst_build_with_the_mac_entitlements(self):
        project = (mac_app.REPO / "project.yml").read_text(encoding="utf-8")
        self.assertIn("CODE_SIGN_ENTITLEMENTS[sdk=macosx*]: MacOS/GwenMobile.entitlements", project)

    def test_the_mac_entitlements_put_the_build_into_the_app_sandbox(self):
        decoded = plistlib.loads(mac_app.ENTITLEMENTS.read_bytes())
        self.assertTrue(decoded[mac_storage.SANDBOX])
        self.assertIn("keychain-access-groups", decoded)


class InstallLogTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "installs.json"

    def test_a_missing_file_knows_nothing(self):
        installs = renew_state.Installs.load(self.path, MOMENT)
        self.assertIsNone(installs.days_left("iphone"))
        self.assertEqual(installs.age_text("iphone"), "never")
        self.assertEqual(installs.is_pending("iphone"), False)

    def test_a_fresh_install_leaves_seven_days(self):
        installs = renew_state.Installs.empty(MOMENT).recorded("iphone", MOMENT)
        self.assertAlmostEqual(installs.days_left("iphone"), 7.0, places=6)
        self.assertEqual(installs.age_text("iphone"), "0 days ago")

    def test_an_old_install_is_past_the_window(self):
        older = MOMENT - datetime.timedelta(days=8)
        installs = renew_state.Installs.empty(MOMENT).recorded("iphone", older)
        self.assertLess(installs.days_left("iphone"), 0)

    def test_pending_survives_a_store_round_trip_and_a_record_clears_it(self):
        installs = renew_state.Installs.empty(MOMENT).marked("iphone")
        renew_state.store(self.path, installs)
        again = renew_state.Installs.load(self.path, MOMENT)
        self.assertEqual(again.is_pending("iphone"), True)
        self.assertEqual(again.recorded("iphone", MOMENT).is_pending("iphone"), False)

    def test_marking_the_same_target_twice_keeps_one_entry(self):
        installs = renew_state.Installs.empty(MOMENT).marked("mac").marked("mac")
        self.assertEqual(installs.pending, ("mac",))

    def test_a_broken_file_is_read_as_empty(self):
        self.path.write_text("not json{")
        self.assertEqual(renew_state.Installs.load(self.path, MOMENT).stamps, {})

    def test_a_naive_moment_is_the_local_wall_clock(self):
        local = MOMENT.astimezone()
        self.assertEqual(renew_state.to_utc(local.replace(tzinfo=None)), MOMENT)
        self.assertEqual(renew_state.to_utc(local), MOMENT)

    def test_a_stamp_is_stored_in_utc(self):
        local_now = datetime.datetime.now().astimezone()
        stored = renew_state.Installs.empty(local_now).recorded("mac", local_now)
        self.assertTrue(stored.stamps["mac"].endswith("+00:00"))
        self.assertEqual(renew_state.to_utc("nonsense"), None)
        self.assertIsNone(renew_state.from_iso("nonsense"))


class DeviceDeadlinePolicyTest(unittest.TestCase):
    class Installs:
        def __init__(self, days_left, pending=False, age="6 days ago"):
            self.value = days_left
            self.pending = pending
            self.age = age

        def days_left(self, target_id):
            return self.value

        def is_pending(self, target_id):
            return self.pending

        def age_text(self, target_id):
            return self.age

    def test_the_earlier_deadline_wins(self):
        self.assertEqual(renewal_policy.merged_days_left(6.0, 2.0), 2.0)
        self.assertEqual(renewal_policy.merged_days_left(6.0, None), 6.0)
        self.assertIsNone(renewal_policy.merged_days_left(None, None))

    def test_an_older_install_on_the_device_drives_the_decision(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0,
                                      installs=self.Installs(1.0))
        self.assertEqual(plans[0].renew, True)
        self.assertIn("6 days ago", plans[0].reason)

    def test_a_device_past_the_window_is_reported_as_expired(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0,
                                      installs=self.Installs(-0.5))
        self.assertIn("past the 7 days", plans[0].reason)

    def test_the_cache_still_drives_when_the_device_is_fresher(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=1.0)), threshold=2.0,
                                      installs=self.Installs(6.0))
        self.assertIn("threshold", plans[0].reason)

    def test_a_failed_previous_attempt_is_retried(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0,
                                      installs=self.Installs(7.0, pending=True))
        self.assertIn("retrying", plans[0].reason)

    def test_without_an_install_log_only_the_cache_counts(self):
        plans = renewal_policy.decide((IPHONE,), state_of(profile(days=7)), threshold=2.0)
        self.assertEqual(plans[0].renew, False)
        self.assertIsNone(plans[0].device_days)
        self.assertIn("unknown", plans[0].deadline_text())


class ReportTest(unittest.TestCase):
    def test_summary_names_the_renewed_and_the_kept_target(self):
        expires = MOMENT + datetime.timedelta(days=7)
        text = renew_report.summary((FakePlan(renew=False), FakePlan()),
                                    (outcome_of(True, expires),))
        self.assertIn("renewed: iPhone", text)
        self.assertIn("unchanged", text)

    def test_summary_marks_failures(self):
        text = renew_report.summary((FakePlan(),), (outcome_of(False, detail="build broken"),))
        self.assertIn("FAILED: iPhone", text)

    def test_summary_without_any_work_says_nothing_to_do(self):
        self.assertEqual(renew_report.summary((), ()), "nothing to do")

    def test_history_line_starts_with_the_timestamp(self):
        line = renew_report.history_line((FakePlan(),), (), MOMENT)
        self.assertTrue(line.startswith("2026-09-26 12:00:00"))
        self.assertTrue(line.endswith("\n"))

    def test_report_lists_every_plan_and_outcome(self):
        text = renew_report.report((FakePlan(renew=False),), (outcome_of(True, MOMENT),), MOMENT)
        self.assertIn("kept", text)
        self.assertIn("✓ iPhone", text)

    def test_manual_step_reaches_the_report(self):
        text = renew_report.report((FakePlan(),), (outcome_of(True, MOMENT, manual="tap trust"),),
                                   MOMENT)
        self.assertIn("manual step: tap trust", text)

    def test_plan_lines_name_the_steps_of_a_target(self):
        lines = renew_report.plan_lines((FakePlan(spec=IPHONE),), renew_targets.Options())
        self.assertIn("  xcodebuild build (ios, Debug)", lines)
        self.assertIn("  devicectl device process launch", lines)

    def test_plan_lines_skip_a_kept_target(self):
        self.assertEqual(renew_report.plan_lines((FakePlan(renew=False),),
                                                 renew_targets.Options()), ())

    def test_apple_script_escapes_quotes_and_newlines(self):
        script = renew_report.apple_script('says "hi"\nsecond line', "title", False)
        self.assertIn('\\"hi\\"', script)
        self.assertIn("\\nsecond line", script)
        self.assertNotIn("sound name", script)

    def test_a_run_without_a_terminal_notifies_on_its_own(self):
        class Stream:
            def isatty(self):
                return False

        self.assertEqual(renew_report.want_notify(False, False, Stream()), True)
        self.assertEqual(renew_report.want_notify(False, True, Stream()), False)
        self.assertEqual(renew_report.want_notify(True, False, Stream()), True)

    def test_notify_uses_osascript_and_reports_its_exit(self):
        calls = []
        self.assertEqual(renew_report.notify("text", run=lambda args, **_kwargs:
                                             calls.append(args) or FakeDone(0)), 0)
        self.assertEqual(calls[0][:2], ["/usr/bin/osascript", "-e"])

    def test_exit_code_reports_a_failure(self):
        self.assertEqual(renew_report.exit_code((outcome_of(True),)), 0)
        self.assertEqual(renew_report.exit_code((outcome_of(False),)), 1)

    def test_history_is_appended(self):
        with tempfile.TemporaryDirectory() as folder:
            path = renew_report.append_history(Path(folder) / "sub" / "history.log", "one\n")
            self.assertEqual(path.read_text(), "one\n")
            renew_report.append_history(path, "two\n")
            self.assertEqual(path.read_text().splitlines(), ["one", "two"])


class FakeDone:
    def __init__(self, code, out="", err=""):
        self.returncode = code
        self.stdout = out
        self.stderr = err


class ScheduleTest(unittest.TestCase):
    def test_parse_spec_accepts_only_real_times(self):
        self.assertEqual(renewal_schedule.parse_spec("09:20"), (9, 20))
        self.assertEqual(renewal_schedule.parse_spec("0"), (0, 0))
        for broken in ("24:00", "9:60", "ab:cd", ""):
            with self.assertRaises(ValueError):
                renewal_schedule.parse_spec(broken)

    def test_render_carries_the_device_and_the_wait(self):
        payload = renewal_schedule.render(Path("/repo/scripts/renew-gwenmobile.py"), 9, 20,
                                          python="/bin/python3", working=Path("/repo"),
                                          wait_minutes=20, device="Phone")
        arguments = payload["ProgramArguments"]
        self.assertEqual(arguments[:2], ["/bin/python3", "/repo/scripts/renew-gwenmobile.py"])
        self.assertIn("--renew", arguments)
        self.assertIn("Phone", arguments)
        self.assertEqual(payload["StartCalendarInterval"], {"Hour": 9, "Minute": 20})
        self.assertIn("/opt/homebrew/bin", payload["EnvironmentVariables"]["PATH"])

    def test_the_agent_path_never_inherits_the_session(self):
        parts = renewal_schedule.default_path().split(":")
        self.assertEqual(parts[:2], ["/usr/bin", "/bin"])
        self.assertEqual(len(parts), len(set(parts)))
        self.assertIn(str(Path(sys.executable).parent), parts)

    def test_render_without_a_device_leaves_it_out(self):
        arguments = renewal_schedule.render(Path("renew-gwenmobile.py"), 8, 0)["ProgramArguments"]
        self.assertNotIn("--device", arguments)

    def test_a_written_agent_reads_back_with_the_same_time(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "agent.plist"
            payload = renewal_schedule.render(Path("renew-gwenmobile.py"), 7, 5,
                                              log_dir=Path(folder))
            with path.open("wb") as handle:
                plistlib.dump(payload, handle)
            self.assertEqual(renewal_schedule.schedule_of(renewal_schedule.load(path)), (7, 5))

    def test_load_of_a_missing_file_is_empty(self):
        self.assertEqual(renewal_schedule.load(Path("/nonexistent/agent.plist")), {})

    def test_schedule_of_an_agent_without_a_calendar_is_unknown(self):
        self.assertEqual(renewal_schedule.schedule_of({"Label": "x"}), (None, None))

    def test_next_fire_stays_today_while_the_time_is_ahead(self):
        moment = datetime.datetime(2026, 10, 19, 8, 0)
        self.assertEqual(renewal_schedule.next_fire(9, 20, moment),
                         datetime.datetime(2026, 10, 19, 9, 20))

    def test_next_fire_rolls_over_to_tomorrow_after_the_time(self):
        moment = datetime.datetime(2026, 10, 19, 20, 44, 30)
        self.assertEqual(renewal_schedule.next_fire(9, 20, moment),
                         datetime.datetime(2026, 10, 20, 9, 20))

    def test_status_reports_the_next_fire(self):
        original = renewal_schedule.AGENT_PATH
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "agent.plist"
            with path.open("wb") as handle:
                plistlib.dump(renewal_schedule.render(Path("renew-gwenmobile.py"), 9, 20,
                                                      log_dir=Path(folder)), handle)
            renewal_schedule.AGENT_PATH = path
            try:
                found = renewal_schedule.status(run=lambda _args: FakeDone(0))
            finally:
                renewal_schedule.AGENT_PATH = original
        self.assertEqual(found["time"], "09:20")
        self.assertTrue(found["loaded"])
        self.assertEqual((found["next"].hour, found["next"].minute), (9, 20))
        self.assertGreater(found["next"], datetime.datetime.now())

    def test_the_launch_target_names_the_gui_domain(self):
        self.assertTrue(renewal_schedule.shorthand().startswith("gui/"))

    def test_unload_removes_a_written_agent(self):
        original = renewal_schedule.AGENT_PATH
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "agent.plist"
            path.write_text("<plist/>")
            renewal_schedule.AGENT_PATH = path
            try:
                with quiet():
                    code = renewal_schedule.unload(run=lambda _args: FakeDone(0))
                self.assertEqual(code, 0)
            finally:
                renewal_schedule.AGENT_PATH = original
        self.assertFalse(path.exists())


class ReaderTest(unittest.TestCase):
    def test_paths_of_only_lists_provisioning_profiles(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "one.mobileprovision").write_text("x")
            (root / "two.provisionprofile").write_text("x")
            (root / "notes.txt").write_text("x")
            self.assertEqual([item.name for item in signing_reader.paths_of(root)],
                             ["one.mobileprovision", "two.provisionprofile"])

    def test_paths_of_survives_a_missing_directory(self):
        self.assertEqual(signing_reader.paths_of(Path("/nonexistent/profiles")), ())

    def test_retire_moves_the_profile_into_the_backup_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "profile.mobileprovision"
            source.write_text("x")
            moved = signing_reader.retire(source, root / "backup")
            self.assertFalse(source.exists())
            self.assertEqual(moved.name, "profile.mobileprovision")
            self.assertTrue(moved.is_file())

    def test_retire_keeps_a_second_profile_with_the_same_name(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            backup = root / "backup"
            first = root / "a.mobileprovision"
            first.write_text("1")
            signing_reader.retire(first, backup)
            second = root / "a.mobileprovision"
            second.write_text("2")
            kept = signing_reader.retire(second, backup)
            self.assertEqual(len(list(backup.iterdir())), 2)
            self.assertNotEqual(kept.name, "a.mobileprovision")

    def test_restore_puts_the_backup_back(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "profile.mobileprovision"
            source.write_text("x")
            signing_reader.retire(source, root / "backup")
            restored = signing_reader.restore(root / "backup", root / "profiles")
            self.assertEqual([item.name for item in restored], ["profile.mobileprovision"])
            self.assertTrue((root / "profiles" / "profile.mobileprovision").is_file())

    def test_decode_of_a_foreign_file_yields_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            broken = Path(folder) / "broken.mobileprovision"
            broken.write_text("not a cms blob")
            self.assertEqual(signing_reader.decode(broken), {})


if __name__ == "__main__":
    unittest.main()
