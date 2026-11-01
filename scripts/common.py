#!/usr/bin/env python3
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import signing_config
from report import fail

REPO = Path(__file__).resolve().parent.parent
SCHEME = "GwenMobile"
BUNDLE_ID = "com.mortis.gwenmobile"
PROJECT = REPO / "GwenMobile.xcodeproj"
PROJECT_YML = REPO / "project.yml"
APP_NAME = "GwenMobile.app"
URL_SCHEME = "gwenmobile"

BUILD_TIMEOUT = 3600
DEVICE_TIMEOUT = 240
INSTALL_TIMEOUT = 900
TOOLCHAIN_TIMEOUT = 3600
WARNING_LIMIT = 8
METAL_COMPONENT = "MetalToolchain"

ENV: dict = {}
XCODE: list = []

HINTS = (
    ("reality", "No physical device in the list — devicectl does not count iPhones in simulator mode."),
    ("developer mode is currently disabled",
     "On the iPhone: Settings → Privacy & Security → Developer Mode → On."),
    ("not, or could not be, unlocked", "Unlock the iPhone (passcode) and repeat the operation."),
    ("already in use by application",
     "The app is already running — install with --no-launch or quit it beforehand."),
    ("profile has not been explicitly trusted",
     "iPhone: Settings → General → VPN & Device Management → trust the developer app."),
    ("no profiles for", "Signing: sign in with the Apple ID account in Xcode → Settings → Accounts, "
                        "then build again (the team id lives in Config/Signing.xcconfig)."),
    ("requires a development team",
     "Signing: put your team id into Config/Signing.xcconfig, or run ./scripts/signing_config.py."),
    ("no account for team",
     "The Xcode account does not hold the team — check Xcode → Settings → Accounts."),
    ("could not locate device support files",
     "This iOS version is unknown to the Mac — update Xcode (Settings → Platforms)."),
    ("unable to find a destination matching",
     "Xcode does not know the destination — reconnect the device or use --generic / --build-only."),
    ("0xe8008017", "The app does not match the provisioning profile — rebuild once with --generate."),
    ("tunnel", "The Wi-Fi tunnel just dropped — the iPhone and the Mac have to be on the same network, "
               "then try again (the script retries on its own)."),
    ("not found", "The device disappeared from the list — plug in the cable or check the Wi-Fi connection."),
)


def tail(text: str, lines: int = 25) -> str:
    return "\n".join((text or "").strip().splitlines()[-lines:])


def explain(text: str) -> str:
    lowered = (text or "").lower()
    return "\n".join(f"  → {hint}" for needle, hint in HINTS if needle in lowered)


def xcode_candidates() -> list:
    paths = []
    done = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
    if done.returncode == 0 and done.stdout.strip():
        paths.append(Path(done.stdout.strip()))
    if os.environ.get("DEVELOPER_DIR"):
        paths.append(Path(os.environ["DEVELOPER_DIR"]))
    for pattern in ("/Applications/Xcode*.app/Contents/Developer",
                    "/Applications/Xcode*/Contents/Developer"):
        paths.extend(Path(match) for match in sorted(glob.glob(pattern), reverse=True))
    paths.append(Path("/Applications/Xcode.app/Contents/Developer"))
    return paths


def xcode_root() -> Path:
    if XCODE:
        return XCODE[0]
    for root in xcode_candidates():
        if (root / "usr" / "bin" / "xcodebuild").is_file():
            XCODE.append(root)
            return root
    shown = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    fail("no full Xcode found (`xcode-select -p` points at "
         + (shown or "nothing") + ").\n"
         "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer\n"
         "    sudo xcodebuild -license accept")


def xcodebuild_path() -> str:
    return str(xcode_root() / "usr" / "bin" / "xcodebuild")


def xcrun() -> str:
    return shutil.which("xcrun") or "/usr/bin/xcrun"


def environment() -> dict:
    global ENV
    if not ENV:
        ENV = dict(os.environ, DEVELOPER_DIR=str(xcode_root()))
    return ENV


def run(args: list, timeout: int = DEVICE_TIMEOUT, cwd: Path = None,
        echo: bool = False) -> subprocess.CompletedProcess:
    if echo:
        print("  $ " + " ".join(str(item) for item in args)[:180])
    try:
        return subprocess.run([str(item) for item in args], cwd=str(cwd or REPO),
                              capture_output=True, text=True, timeout=timeout, env=environment())
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, -1, "", f"timeout after {timeout}s")
    except OSError as exc:
        fail(f"could not start {args[0]}: {exc}")


def devicectl_json(pieces: list, udid: str = None) -> dict:
    args = [xcrun(), "devicectl"] + pieces + ["--json-output", "-"]
    if udid:
        args += ["--device", udid]
    done = run(args)
    raw = done.stdout.strip()
    start = raw.find("{")
    if start < 0:
        fail(f"devicectl {' '.join(pieces)} returned no JSON:\n{tail(done.stderr, 10)}"
             + explain(done.stderr))
    payload = json.loads(raw[start:])
    outcome = payload.get("info", {}).get("outcome")
    if done.returncode != 0 or outcome not in (None, "success"):
        fail(f"devicectl {' '.join(pieces)} failed"
             f"{' (' + str(outcome) + ')' if outcome not in (None, 'success') else ''}:\n"
             f"{tail(done.stderr or done.stdout, 12)}" + explain(done.stderr or done.stdout))
    return payload.get("result", {})


@dataclass
class Device:
    udid: str
    name: str
    model: str
    system: str
    link: str = ""

    def label(self) -> str:
        return f"{self.name} ({self.model}, iOS {self.system}, {self.udid}, {self.link})"


def list_devices() -> list:
    found = []
    for entry in devicectl_json(["list", "devices"]).get("devices", []):
        props = entry.get("properties") or {}
        hardware = props.get("hardware") or {}
        connection = props.get("connection") or {}
        software = props.get("software") or {}
        state = props.get("state") or {}
        reality = hardware.get("reality")
        if reality == "simulated" or state.get("visibilityClass") == "simulators":
            continue
        if reality not in (None, "physical"):
            continue
        if connection.get("pairingState") not in (None, "paired"):
            continue
        version = software.get("osVersionNumber")
        version = version.get("stringValue") if isinstance(version, dict) else version
        found.append(Device(
            udid=hardware.get("udid") or entry.get("identifier", ""),
            name=state.get("name") or (entry.get("deviceProperties") or {}).get("name")
            or hardware.get("marketingName") or entry.get("identifier", "?"),
            model=hardware.get("marketingName") or hardware.get("productType") or "?",
            system=version or "?",
            link=connection.get("state") or state.get("status") or "?",
        ))
    found.sort(key=lambda item: 0 if item.link == "connected" else 1)
    return found


def check_reachable(device: Device) -> Device:
    done = run([xcrun(), "devicectl", "device", "info", "lockState", "--device", device.udid])
    if done.returncode != 0:
        fail(f"{device.name} is in the device list ({device.link}), but devicectl cannot reach it:\n"
             f"{tail(done.stderr or done.stdout, 12)}" + explain(done.stderr or done.stdout)
             + "\nCheck: cable or Wi-Fi connection, device unlocked, "
               "“Trust This Computer” confirmed, developer mode on.")
    if "unlockedSinceBoot: false" in done.stdout:
        print("Note: the device has not been unlocked since boot — "
              "installing and probing need an unlocked display.")
    return device


def newest_source() -> float:
    stamp = 0.0
    for folder in ("GwenMobile", "GwenMobileProbes", "GwenMobileSystem", "GwenMobileAdapters", "GwenMobileDevice", "GwenMobileShell"):
        for swift in (REPO / folder).rglob("*.swift"):
            stamp = max(stamp, swift.stat().st_mtime)
    return stamp


def needs_generation() -> bool:
    if not PROJECT.exists():
        return True
    pbxproj = PROJECT / "project.pbxproj"
    built = pbxproj.stat().st_mtime if pbxproj.exists() else 0.0
    return PROJECT_YML.stat().st_mtime > built or newest_source() > built


def generate_project(force: bool = False, skip: bool = False) -> None:
    if skip:
        print("Project generation skipped (--no-generate).")
        return
    if not (force or needs_generation()):
        print("Project up to date, xcodegen not needed.")
        return
    print("Regenerating project (forced) …" if force else "Generating project from project.yml …")
    signing_config.ensure(BUNDLE_ID)
    xcodegen = shutil.which("xcodegen")
    if not xcodegen:
        fail("xcodegen is missing from PATH (brew install xcodegen) — or use --no-generate.")
    done = run([xcodegen, "generate"], timeout=300)
    if done.returncode != 0:
        fail("xcodegen generate failed:\n" + tail(done.stdout + done.stderr))


def metal_component_status(component: str = METAL_COMPONENT) -> str:
    done = run([xcodebuild_path(), "-showComponent", component], timeout=DEVICE_TIMEOUT)
    return (done.stdout + done.stderr).strip()


def metal_toolchain_ready() -> bool:
    return "Status: installed" in metal_component_status()


def download_metal_toolchain(export: Path = None) -> int:
    arguments = [xcodebuild_path(), "-downloadComponent", METAL_COMPONENT]
    if export:
        arguments += ["-exportPath", str(export)]
    print("  $ " + " ".join(arguments))
    try:
        return subprocess.run(arguments, cwd=str(REPO), env=environment(),
                              timeout=TOOLCHAIN_TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        return -1
    except OSError as exc:
        fail(f"could not start {arguments[0]}: {exc}")


def import_metal_toolchain() -> None:
    spare = Path(tempfile.mkdtemp(prefix="gwenmobile-metal-"))
    try:
        download_metal_toolchain(export=spare)
        bundles = sorted(spare.glob("*.exportedBundle"))
        if not bundles:
            print(f"  no component bundle in {spare} — nothing to import")
            return
        arguments = [xcodebuild_path(), "-importComponent", METAL_COMPONENT,
                     "-importPath", str(bundles[-1])]
        print("  $ " + " ".join(arguments))
        subprocess.run(arguments, cwd=str(REPO), env=environment(), timeout=TOOLCHAIN_TIMEOUT)
    except subprocess.TimeoutExpired:
        print("  the component import timed out")
    finally:
        shutil.rmtree(spare, ignore_errors=True)


def ensure_metal_toolchain() -> None:
    if metal_toolchain_ready():
        return
    print("Metal Toolchain is missing — Xcode 27 ships the Metal compiler as a separate component.")
    print("Installing it now (about 840 MB download, can take several minutes) …")
    download_metal_toolchain()
    if metal_toolchain_ready():
        print("Metal Toolchain installed.")
        return
    print("The download alone did not register the toolchain — importing the component …")
    import_metal_toolchain()
    if metal_toolchain_ready():
        print("Metal Toolchain installed.")
        return
    fail("the Metal Toolchain is still missing, so the MLX Metal kernels cannot be compiled.\n"
         "    xcodebuild -downloadComponent MetalToolchain\n"
         "Check network, proxy and free disk space (about 1 GB), then repeat the build.")


def build_app(configuration: str, destination: str, derived: Path, extra: list = (),
              clean: bool = False) -> Path:
    ensure_metal_toolchain()
    derived.mkdir(parents=True, exist_ok=True)
    log_path = derived / "xcodebuild.log"
    app = derived / "Build" / "Products" / f"{configuration}-iphoneos" / APP_NAME
    arguments = [xcodebuild_path(), "-project", PROJECT, "-scheme", SCHEME,
                 "-configuration", configuration, "-destination", destination,
                 "-derivedDataPath", derived, "-allowProvisioningUpdates",
                 "-skipMacroValidation",
                 "MTL_COMPILER_FLAGS=-Wno-c++17-extensions"] + list(extra)
    arguments += ["clean"] if clean else []
    arguments.append("build")
    print(f"Building {configuration} for {destination} …")
    print("  $ " + " ".join(str(item) for item in arguments)[:180])
    code, shown = stream_build(arguments, log_path)
    text = log_path.read_text(errors="replace")
    if code != 0 or "BUILD FAILED" in text:
        fail(f"xcodebuild failed (exit {code}). Last lines:\n{tail(text, 30)}\n"
             + explain(text) + f"\nFull log: {log_path}")
    if not app.is_dir():
        fail(f"{app} was not produced — was something wrong with the destination? Log: {log_path}")
    size = sum(item.stat().st_size for item in app.rglob("*") if item.is_file())
    print(f"Build finished: {app}  ({size / 1024 / 1024:.1f} MB, {shown} log lines)")
    return app


def stream_build(arguments: list, log_path: Path) -> tuple:
    started = time.monotonic()
    state = [0, 0]
    with log_path.open("w", encoding="utf-8") as log:
        try:
            child = subprocess.Popen([str(item) for item in arguments], cwd=str(REPO),
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, env=environment())
        except OSError as exc:
            fail(f"xcodebuild cannot start: {exc}")
        for line in child.stdout:
            log.write(line)
            log.flush()
            state[1] += 1
            if "error:" in line or line.startswith("** "):
                print("  " + line.rstrip()[:200])
            elif "warning:" in line and state[0] < WARNING_LIMIT:
                state[0] += 1
                print("  " + line.rstrip()[:200])
            elif state[1] % 500 == 0:
                print(f"  … {state[1]} lines ({int(time.monotonic() - started)}s)")
        state[0] = child.wait(timeout=BUILD_TIMEOUT)
    minutes = int(time.monotonic() - started) // 60
    print(f"Build log: {log_path} ({state[1]} lines, {minutes}m "
          f"{int(time.monotonic() - started) % 60}s)")
    return state[0], state[1]


def install_app(app: Path, device: Device, timeout: int = INSTALL_TIMEOUT) -> subprocess.CompletedProcess:
    return run([xcrun(), "devicectl", "device", "install", "app",
                "--device", device.udid, str(app)], timeout=timeout, echo=True)


def launch_app(device: Device, url: str = "", arguments: list = (), console: bool = False) -> subprocess.CompletedProcess:
    args = [xcrun(), "devicectl", "device", "process", "launch", "--device", device.udid,
            "--terminate-existing"]
    if url:
        args += ["--payload-url", url]
    args += list(arguments)
    args.append(BUNDLE_ID)
    if console:
        print("  (console attached — Ctrl+C detaches, the app keeps running)")
        try:
            subprocess.run([str(item) for item in args], cwd=str(REPO), env=environment())
        except KeyboardInterrupt:
            print("\nConsole detached.")
        return subprocess.CompletedProcess(args, 0, "", "")
    return run(args, echo=True)


def probe_url(given: str) -> str:
    if not given:
        return ""
    return given if "://" in given else f"{URL_SCHEME}://test/{given}"


def info_plist(app: Path) -> Path:
    inside = app / "Contents" / "Info.plist"
    return inside if inside.is_file() else app / "Info.plist"


def plist_value(app: Path, key: str) -> str:
    done = run(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", info_plist(app)], echo=False)
    return done.stdout.strip() if done.returncode == 0 else "?"


def find_app(node, wanted: str = BUNDLE_ID):
    stack = [node]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            values = {str(item) for item in current.values() if isinstance(item, str)}
            if wanted in values or wanted.lower() in values:
                return current
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
    return None


def installed_build(device: Device) -> str:
    try:
        result = devicectl_json(["device", "info", "apps"], device.udid)
    except SystemExit:
        return "?"
    entry = find_app(result)
    if not entry:
        return "?"
    version = entry.get("version") or entry.get("bundleVersion") or "?"
    short = entry.get("shortVersionString") or entry.get("displayVersion") or ""
    return f"{short} ({version})" if short else str(version)


def git_info() -> str:
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], echo=False).stdout.strip() or "?"
    commit = run(["git", "rev-parse", "--short", "HEAD"], echo=False).stdout.strip() or "?"
    dirty = [line for line in run(["git", "status", "--porcelain"], echo=False).stdout.splitlines()
             if line.strip()]
    return f"{branch}@{commit}" + (f", {len(dirty)} modified files (uncommitted)" if dirty
                                   else ", clean working tree")
