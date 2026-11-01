#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import mac_storage
import signing_reader
import signing_state
from common import APP_NAME, BUILD_TIMEOUT, PROJECT, REPO, SCHEME, explain, fail, run, tail

ENTITLEMENTS = REPO / "MacOS" / "GwenMobile.entitlements"
LAUNCHSERVICES = ("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
                  "LaunchServices.framework/Support/lsregister")
REQUIRED_ENTITLEMENTS = ("com.apple.security.app-sandbox", "com.apple.security.network.client",
                         "keychain-access-groups", "com.apple.security.personal-information.location")
CODESIGN_TIMEOUT = 300
PLIST_END = "</plist>"


def product_path(derived: Path, configuration: str) -> Path:
    return derived / "Build" / "Products" / f"{configuration}-maccatalyst" / APP_NAME


def build(configuration: str, derived: Path) -> Path:
    derived.mkdir(parents=True, exist_ok=True)
    log = derived / "xcodebuild.log"
    if not ENTITLEMENTS.is_file():
        fail(f"{ENTITLEMENTS} is missing — without the sandbox and keychain entitlements the Mac build "
             "cannot store an API key")
    common.ensure_metal_toolchain()
    print(f"Building {configuration} for Mac Catalyst …")
    done = run([common.xcodebuild_path(), "-project", PROJECT, "-scheme", SCHEME,
                "-configuration", configuration,
                "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", derived,
                "-allowProvisioningUpdates", "-skipMacroValidation",
                f"CODE_SIGN_ENTITLEMENTS={ENTITLEMENTS}", "CODE_SIGN_STYLE=Automatic",
                "MTL_COMPILER_FLAGS=-Wno-c++17-extensions", "ARCHS=arm64", "build"],
               echo=True, timeout=BUILD_TIMEOUT)
    log.write_text(done.stdout + done.stderr, encoding="utf-8")
    app = product_path(derived, configuration)
    if done.returncode != 0 or not app.is_dir():
        text = done.stdout + done.stderr
        fail(f"xcodebuild failed (exit {done.returncode}). Last lines:\n{tail(text)}\nFull log: {log}"
             + explain(text))
    print(f"Build finished: {app}")
    return app


def entitlements_of(app: Path) -> str:
    done = run(["codesign", "-d", "--entitlements", "-", "--xml", app], timeout=CODESIGN_TIMEOUT)
    return done.stdout + done.stderr


class CodesignEntitlements:
    def __init__(self, reader=entitlements_of):
        self.reader = reader

    def entitlements(self, bundle: Path) -> dict:
        text = self.reader(Path(bundle))
        start = text.find("<?xml")
        if start < 0:
            return {}
        end = text.find(PLIST_END, start)
        if end < 0:
            return {}
        try:
            decoded = plistlib.loads(text[start:end + len(PLIST_END)].encode("utf-8"))
        except (ValueError, plistlib.InvalidFileException, ExpatError):
            return {}
        return decoded if isinstance(decoded, dict) else {}


class InfoPlistBundleId:
    def __init__(self, reader=common.plist_value):
        self.reader = reader

    def bundle_id(self, bundle: Path) -> str:
        value = self.reader(Path(bundle), "CFBundleIdentifier")
        return "" if value in ("", "?") else value


def store_map(home: Path | None = None) -> mac_storage.SettingsStores:
    return mac_storage.SettingsStores(CodesignEntitlements(), InfoPlistBundleId(), home)


def verify_entitlements(app: Path) -> None:
    text = entitlements_of(app)
    missing = [key for key in REQUIRED_ENTITLEMENTS if key not in text]
    if missing:
        fail("the Mac build does not carry the required entitlements: " + ", ".join(missing)
             + "\nWithout a keychain group no API key can be stored on the Mac, "
               "without the location entitlement CoreLocation cannot reach locationd.")
    print("  Entitlements: " + ", ".join(REQUIRED_ENTITLEMENTS))


def verify_signature(app: Path, require: bool) -> None:
    done = run(["codesign", "--verify", "--strict", "--verbose=1", app], timeout=CODESIGN_TIMEOUT)
    if done.returncode != 0:
        text = (done.stdout + done.stderr).strip()
        if require:
            fail(f"signature verification failed:\n{text}")
        print(f"WARNING: signature verification: {text}")
        return
    info = run(["codesign", "-dvv", app], timeout=CODESIGN_TIMEOUT)
    lines = (info.stdout + info.stderr).splitlines()
    for wanted in ("Identifier", "TeamIdentifier", "Format"):
        found = next((line for line in lines if line.startswith(wanted)), "")
        if found:
            print("  " + found)


def install(app: Path, target: Path) -> Path:
    if not app.is_dir():
        fail(f"{app} is missing — build the Mac app first.")
    if target.exists():
        try:
            shutil.rmtree(target)
        except OSError as exc:
            fail(f"cannot replace {target}: {exc}\n"
                 "Either quit the running GwenMobile or install with sudo.")
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"Installing {app} → {target} …")
    try:
        shutil.copytree(app, target, symlinks=True)
    except OSError as exc:
        fail(f"cannot copy the app to {target}: {exc}")
    return target


def register(path: Path) -> None:
    if not Path(LAUNCHSERVICES).is_file():
        print(f"  lsregister not found — Launch Services keeps {path} as it is")
        return
    run([LAUNCHSERVICES, "-f", path], timeout=CODESIGN_TIMEOUT, echo=True)


def profile_of(bundle: Path) -> signing_state.Profile | None:
    for name in ("embedded.provisionprofile", "embedded.mobileprovision"):
        inside = bundle / "Contents" / name
        if not inside.is_file():
            inside = bundle / name
        if inside.is_file():
            return signing_state.parse(signing_reader.decode(inside), inside)
    return None


def app_name_of(bundle: Path) -> str:
    return bundle.name[: -len(".app")] if bundle.name.endswith(".app") else bundle.name


def running(name: str) -> tuple:
    done = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
    return tuple(done.stdout.split()) if done.returncode == 0 else ()
