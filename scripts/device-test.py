#!/usr/bin/env python3
import argparse
import faulthandler
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
from common import BUNDLE_ID, Device, REPO, URL_SCHEME, fail, tail

DERIVED = REPO / "build" / "Runner"
PROBE_DIR = REPO / "GwenMobileProbes"
APP_DIR = REPO / "GwenMobile"
REPORT_ROOT = REPO / "build" / "reports"
TRACE_NAME = "flow_trace.txt"

MODIFIERS = r"(?:(?:private|fileprivate|static|@MainActor|mutating|nonisolated|final|public|internal)\s+)*"
CASE_RE = re.compile(r'^\s*case "([A-Za-z0-9_.]+)":\s*(?:await|return \{)(.*)$', re.M)
PREFIX_LINE_RE = re.compile(r'^.*hasPrefix\("([A-Za-z0-9_.]+)"\).*$', re.M)
CASE_END_RE = re.compile(r'^\s*(?:case\s+"|default\s*:)', re.M)
WAY_RE = re.compile(r'way\s*(?:==|!=)\s*"([a-z]+)"')
FUNC_CALL_RE = re.compile(r'\b([a-zA-Z_][A-Za-z0-9_]*)\s*\(')
QUALIFIED_CALL_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\.([a-zA-Z_][A-Za-z0-9_]*)\s*\(')
FUNC_HEAD_RE = re.compile(r'^    ' + MODIFIERS + r'func\s+([A-Za-z0-9_]+)')
BODY_END_RE = re.compile(r'^    ' + MODIFIERS + r'(?:func|var|let|init|subscript|@)|^\}')
TYPE_RE = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)?' + MODIFIERS
                     + r'(?:class|enum|struct|extension|actor|protocol)\s+([A-Za-z0-9_]+)')
REPORT_RE = re.compile(r'"([A-Za-z0-9_]+\.(?:txt|jpg))"')
REPORT_CONSTANT_RE = re.compile(r'^    ' + MODIFIERS + r'let\s+([A-Za-z0-9_]+)\s*(?::\s*String\s*)?=\s*"([A-Za-z0-9_]+\.(?:txt|jpg))"')
TRAVEL_CASE_RE = re.compile(r'^    case ([a-z]+)$', re.M)
DISPATCH_SWITCH_RE = re.compile(r'switch\s+\w+\s*\{')
DISPATCH_CASE_RE = re.compile(r'^\s*case\s+"', re.M)

GROUP_LABELS = {
    "DebugFeatureProbes": "Feature probes",
    "DebugFileProbes": "File/PDF probes",
    "ProbeCommands": "UI flow tests",
}
DESTRUCTIVE = ("historywipe",)
RELEASABLE = {"listenroute": "listen_release"}
EXTERNAL_VOICE_TRIGGERS = {
    "conversationcancelword": ("CANCELWORD_TTS_START", "abbrechen"),
    "listencancel": ("LISTENCANCEL_TTS_START", "abbrechen"),
    "conversationbarge": ("BARGE_TTS_START", "Moment, ich habe eine Frage"),
    "conversationturn": ("TURN_TTS_START", "Moment, ich habe eine Frage"),
}
EXTERNAL_VOICE_DELAY = 2
EXTERNAL_VOICE_GAP = 4
EXTERNAL_VOICE_REPEATS = {"conversationcancelword": 3, "listencancel": 3}
EXTERNAL_VOICE_RATE = "145"
EXTERNAL_VOICE_VOLUME = "2.0"
EXTERNAL_VOICE = "Anna"
FIXTURE_MARKERS = ("flowTestBigImage", "flowTestEditImage", "conversationHolding(", "heavyConversation(",
                    "Fixtures.all", "fixture.", "ProbePicture")
REPORT_LIMIT = 4000
FIXTURES_SCENARIO = "makefixtures"
DEVICE_READ_TIMEOUT = 240
DEVICE_READ_ATTEMPTS = 3


@dataclass
class Scenario:
    name: str
    group: str
    needs_fixtures: bool
    destructive: bool
    reports: tuple = ()
    index: int = 0


@dataclass
class RunResult:
    name: str
    finished: bool
    seconds: int
    folder: Path
    pulled: list
    skipped: bool = False
    reason: str = ""


def _terminate_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        proc.kill()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def device_read(args: list, timeout: int = DEVICE_READ_TIMEOUT,
                attempts: int = DEVICE_READ_ATTEMPTS) -> Optional[subprocess.CompletedProcess]:
    for attempt in range(attempts):
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                start_new_session=True, env=common.environment())
        try:
            stdout, stderr = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            _terminate_group(proc)
            if attempt + 1 < attempts:
                time.sleep(2 * (attempt + 1))
                continue
            return None
        if proc.returncode == 0 or attempt + 1 >= attempts:
            return subprocess.CompletedProcess(args, proc.returncode, stdout, stderr)
        time.sleep(2 * (attempt + 1))
    return None


class ProbeIndex:
    def __init__(self, folder: Path):
        self.bodies = {}
        self.by_func = {}
        self.constants = {}
        for path in sorted(folder.rglob("*.swift")):
            self.absorb(path.read_text(encoding="utf-8"))
        for key in [key for key, body in self.bodies.items() if self.is_dispatcher(body)]:
            self.drop(key)

    @staticmethod
    def is_dispatcher(body: str) -> bool:
        return bool(DISPATCH_SWITCH_RE.search(body) and DISPATCH_CASE_RE.search(body))

    def absorb(self, text: str) -> None:
        type_name = ""
        key = None
        buffer = []
        for line in text.splitlines():
            declared = TYPE_RE.match(line)
            if declared:
                self.store(key, buffer)
                key, buffer, type_name = None, [], declared.group(1)
                continue
            head = FUNC_HEAD_RE.match(line)
            if head:
                self.store(key, buffer)
                key, buffer = f"{type_name}.{head.group(1)}", [line]
                continue
            constant = REPORT_CONSTANT_RE.match(line)
            if constant and type_name:
                self.constants.setdefault(type_name, {})[constant.group(1)] = constant.group(2)
            if key is None:
                continue
            if BODY_END_RE.match(line):
                self.store(key, buffer)
                key, buffer = None, []
            else:
                buffer.append(line)
        self.store(key, buffer)

    def store(self, key: str, buffer: list) -> None:
        if not key or not buffer:
            return
        self.bodies[key] = (self.bodies.get(key, "") + "\n" + "\n".join(buffer)).strip()
        name = key.split(".", 1)[1]
        self.by_func.setdefault(name, [])
        if key not in self.by_func[name]:
            self.by_func[name].append(key)

    def drop(self, key: str) -> None:
        self.bodies.pop(key, None)
        name = key.split(".", 1)[1]
        if key in self.by_func.get(name, []):
            self.by_func[name].remove(key)

    def calls(self, text: str) -> set:
        found = set()
        for receiver, name in QUALIFIED_CALL_RE.findall(text):
            candidate = f"{receiver}.{name}"
            if candidate in self.bodies:
                found.add(candidate)
        for name in FUNC_CALL_RE.findall(text):
            matches = self.by_func.get(name, [])
            if len(matches) == 1:
                found.add(matches[0])
        return found

    def closure_keys(self, text: str) -> list:
        seen = set()
        pending = sorted(self.calls(text))
        collected = []
        while pending:
            key = pending.pop()
            if key in seen or key not in self.bodies:
                continue
            seen.add(key)
            collected.append(key)
            pending.extend(sorted(self.calls(self.bodies[key]) - seen))
        return collected

    def closure(self, text: str) -> str:
        return "\n".join(self.bodies[key] for key in self.closure_keys(text))

    def constant_reports(self, text: str) -> set:
        found = set()
        keys = self.closure_keys(text)
        whole = text + "\n" + "\n".join(self.bodies[key] for key in keys)
        for owner, named in self.constants.items():
            for name, file in named.items():
                if re.search(rf'\b{re.escape(owner)}\.{re.escape(name)}\b', whole):
                    found.add(file)
        for key in keys:
            owner = key.split(".", 1)[0]
            for name, file in self.constants.get(owner, {}).items():
                if re.search(rf'(?<![.\w]){re.escape(name)}\b', self.bodies[key]):
                    found.add(file)
        return found

    def needs_fixtures(self, seed_text: str) -> bool:
        closure = self.closure(seed_text)
        return any(marker in closure for marker in FIXTURE_MARKERS)

    @staticmethod
    def creates_fixtures(seed_text: str) -> bool:
        return "makeFixtures" in seed_text

    def reports(self, seed_text: str) -> tuple:
        literals = set(REPORT_RE.findall(seed_text + "\n" + self.closure(seed_text)))
        return tuple(sorted(literals | self.constant_reports(seed_text)))

    def ways(self, seed_text: str) -> tuple:
        return tuple(dict.fromkeys(WAY_RE.findall(self.closure(seed_text)) + ["url"]))


def travel_tokens() -> tuple:
    source = next(APP_DIR.rglob("TravelMode.swift"), None)
    if source is None:
        return ("walking",)
    return tuple(TRAVEL_CASE_RE.findall(source.read_text(encoding="utf-8"))) or ("walking",)


def discover_scenarios() -> list:
    if not PROBE_DIR.is_dir():
        fail(f"{PROBE_DIR} is missing — the scenarios cannot be read out of the code")
    index = ProbeIndex(PROBE_DIR)
    scenarios = {}
    for path in sorted(PROBE_DIR.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        group = GROUP_LABELS.get(path.stem, path.stem)
        for match in CASE_RE.finditer(text):
            name = match.group(1)
            boundary = CASE_END_RE.search(text, match.end(2))
            rest = text[match.start(2):boundary.start() if boundary else len(text)]
            scenarios[name] = Scenario(
                name=name,
                group=group,
                needs_fixtures=index.needs_fixtures(rest) and not index.creates_fixtures(rest),
                destructive=name in DESTRUCTIVE,
                reports=index.reports(rest),
            )
        for found in PREFIX_LINE_RE.finditer(text):
            prefix = re.search(r'hasPrefix\("([A-Za-z0-9_.]+)"\)', found.group(0)).group(1)
            line = found.group(0)
            for way in index.ways(line):
                variants = [f"{prefix}{way}"] if way == "url" else [
                    f"{prefix}{way}.{token}" for token in travel_tokens()]
                for variant in variants:
                    scenarios.setdefault(variant, Scenario(
                        name=variant,
                        group=f"Handoff {prefix.rstrip('.')}",
                        needs_fixtures=False,
                        destructive=False,
                        reports=index.reports(line),
                    ))
    return sorted(scenarios.values(), key=lambda item: (item.group, item.name))


def pull_document(device: Device, relative: str, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    done = device_read([
        common.xcrun(), "devicectl", "device", "copy", "from",
        "--device", device.udid,
        "--domain-type", "appDataContainer",
        "--domain-identifier", BUNDLE_ID,
        "--source", f"Documents/{relative}",
        "--destination", str(destination),
    ], timeout=30, attempts=2)
    return done is not None and done.returncode == 0


def capture_screen(device: Device, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    done = device_read([
        common.xcrun(), "devicectl", "device", "capture", "screenshot",
        "--device", device.udid, "--destination", str(destination),
    ])
    return done is not None and done.returncode == 0


def file_service_ok(device: Device) -> bool:
    done = device_read([
        common.xcrun(), "devicectl", "--timeout", "30", "device", "info", "files",
        "--device", device.udid,
        "--domain-type", "appDataContainer",
        "--domain-identifier", BUNDLE_ID,
        "--subdirectory", "Documents",
        "--json-output", "-",
    ], timeout=45, attempts=1)
    return done is not None and done.returncode == 0 and bool(done.stdout.strip())


def remoted_pid(device: Device) -> Optional[str]:
    done = device_read([
        common.xcrun(), "devicectl", "device", "info", "processes",
        "--device", device.udid,
    ], timeout=60, attempts=1)
    if done is None or done.returncode != 0:
        return None
    for line in done.stdout.splitlines():
        if "/usr/libexec/remoted" in line:
            fields = line.split()
            if fields and fields[0].isdigit():
                return fields[0]
    return None


def heal_file_service(device: Device, budget: int = 240) -> bool:
    if file_service_ok(device):
        return True
    pid = remoted_pid(device)
    if pid:
        print(f"  the file service is stuck — restarting remoted (pid={pid}) on the device …")
        device_read([
            common.xcrun(), "devicectl", "device", "process", "signal",
            "--device", device.udid, "--pid", pid, "--signal", "SIGKILL",
        ], timeout=60, attempts=1)
    deadline = time.time() + budget
    while time.time() < deadline:
        if file_service_ok(device):
            print("  the file service answers again.")
            return True
        time.sleep(3)
    print("  the file service did not come back within the budget.")
    return False


def launch_scenario(device: Device, name: str, via: str) -> subprocess.Popen:
    def command() -> list:
        args = [common.xcrun(), "devicectl", "device", "process", "launch",
                "--device", device.udid, "--terminate-existing", "--console"]
        if via == "url":
            args += ["--payload-url", f"{URL_SCHEME}://test/{name}", BUNDLE_ID]
        else:
            args += [BUNDLE_ID, "--", "-gwenflowtest", name]
        return args

    for attempt in range(2):
        proc = subprocess.Popen(command(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1, start_new_session=True,
                                env=common.environment())
        deadline = time.time() + 2
        while time.time() < deadline and proc.poll() is None:
            time.sleep(0.1)
        if proc.poll() is None:
            return proc
        if attempt == 0:
            print("  the console launch failed once — trying again …")
    fail(f"starting '{name}' failed. Device unlocked and app installed?")


def stop_app(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        _terminate_group(proc)


def release_shot(device: Device, folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    shot = folder / "screen.png"
    if capture_screen(device, shot):
        print(f"  screenshot: {shot}")
    else:
        print("  the screenshot could not be captured.")
    write_release_marker(device, folder, "shot_release")


def write_release_marker(device: Device, folder: Path, marker_name: str) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    marker = folder / marker_name
    marker.write_text("release", encoding="utf-8")
    for attempt in range(2):
        done = device_read([
            common.xcrun(), "devicectl", "device", "copy", "to",
            "--device", device.udid,
            "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE_ID,
            "--source", str(marker),
            "--destination", f"Documents/{marker_name}",
        ], timeout=30, attempts=1)
        if done is not None and done.returncode == 0:
            print(f"  release marker '{marker_name}' written.")
            return
        if attempt == 0:
            detail = tail((done.stderr if done else "timeout") or "", 2)
            print(f"  the release marker did not reach the device: {detail}")
            heal_file_service(device, budget=180)
            print("  retrying the release marker …")
    print("  the release marker could not be written — the probe keeps waiting on its own.")


def wait_for_trace(device: Device, name: str, deadline: float, folder: Path, poll: int,
                   stale: int) -> tuple:
    marker = f"FLOWTEST finished cmd={name}"
    target = folder / TRACE_NAME
    last = ""
    last_change = time.time()
    while time.time() < deadline:
        if pull_document(device, TRACE_NAME, target):
            text = target.read_text(encoding="utf-8", errors="replace")
            if text != last:
                last = text
                last_change = time.time()
            if marker in last:
                print("  the console is gone, but the trace file reports the finish signal.")
                return True, last
            if time.time() - last_change >= max(stale, 45):
                print("  the trace file stopped growing — the app seems suspended or gone.")
                return False, last
        else:
            heal_file_service(device, budget=60)
        time.sleep(max(3, min(poll, 10)))
    return False, last


def say_external(phrase: str) -> None:
    if shutil.which("say") is None:
        print("  external voice unavailable: 'say' was not found.")
        return
    with tempfile.TemporaryDirectory(prefix="gwen-voice-") as folder:
        audio = Path(folder) / "phrase.aiff"
        attempts = [["say", "-v", EXTERNAL_VOICE, "-r", EXTERNAL_VOICE_RATE, "-o", str(audio), phrase],
                    ["say", "-r", EXTERNAL_VOICE_RATE, "-o", str(audio), phrase]]
        synthesized = False
        for command in attempts:
            try:
                done = subprocess.run(command, capture_output=True, text=True, timeout=30)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"  external voice failed: {error}")
                continue
            if done.returncode == 0:
                synthesized = True
                break
            print("  external voice failed: " + tail((done.stderr or done.stdout).strip(), 2))
        if not synthesized:
            print("  external voice could not be generated.")
            return
        player = (["afplay", "-v", EXTERNAL_VOICE_VOLUME, str(audio)] if shutil.which("afplay")
                  else ["say", "-r", EXTERNAL_VOICE_RATE, phrase])
        try:
            done = subprocess.run(player, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f"  external voice failed: {error}")
            return
        if done.returncode == 0:
            print(f"  external voice: {phrase}")
            return
        print("  external voice failed: " + tail((done.stderr or done.stdout).strip(), 2))
    print("  external voice could not be played.")


def external_voice_sequence(phrase: str, attempts: int) -> None:
    for attempt in range(attempts):
        if attempt:
            time.sleep(EXTERNAL_VOICE_GAP)
        say_external(phrase)


def wait_for_finish(device: Device, proc: subprocess.Popen, name: str, poll: int, timeout: int,
                    stale: int, folder: Path, shot: bool, release_marker: str = "",
                    release_after: int = 0) -> tuple:
    finished = f"FLOWTEST finished cmd={name}"
    external_voice = EXTERNAL_VOICE_TRIGGERS.get(name)
    external_voice_started = False
    lines: queue.Queue = queue.Queue()

    def pump() -> None:
        for line in proc.stdout:
            lines.put(line)

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    collected = []
    deadline = time.time() + timeout
    started = time.time()
    last_line = time.time()
    last_notice = time.time()
    released = False
    auto_released = False
    while time.time() < deadline:
        if release_marker and not auto_released and release_after > 0 \
                and time.time() - started >= release_after:
            print(f"Releasing '{name}' after {release_after}s …")
            write_release_marker(device, folder, release_marker)
            auto_released = True
        try:
            line = lines.get(timeout=poll)
        except queue.Empty:
            if not thread.is_alive() and lines.empty():
                print("  the console stream closed — reading the finish signal from the trace file instead.")
                done, trace = wait_for_trace(device, name, deadline, folder, poll, stale)
                if done:
                    return True, trace, ""
                return False, trace or "\n".join(collected), "console_closed"
            silence = time.time() - last_line
            if silence >= 15 and time.time() - last_notice >= 15:
                print(f"  … no console line for {int(silence)}s (cmd={name})")
                last_notice = time.time()
            if silence >= stale:
                print("  the console stayed silent — reading the finish signal from the trace file instead.")
                done, trace = wait_for_trace(device, name, deadline, folder, poll, stale)
                if done:
                    return True, trace, ""
                return False, trace or "\n".join(collected), f"console_silent_for_{int(silence)}s"
            continue
        last_line = time.time()
        stripped = line.strip()
        print("  " + stripped)
        collected.append(stripped)
        if shot and not released and "SHOT bereit" in stripped:
            print("Shot fixture ready — capturing the screen and releasing the hold.")
            release_shot(device, folder)
            released = True
        if external_voice and not external_voice_started and external_voice[0] in stripped:
            external_voice_started = True
            attempts = EXTERNAL_VOICE_REPEATS.get(name, 1)
            print(f"  external voice queued: {external_voice[1]} ({attempts}x)")
            timer = threading.Timer(EXTERNAL_VOICE_DELAY, external_voice_sequence,
                                    args=(external_voice[1], attempts))
            timer.daemon = True
            timer.start()
        if finished in stripped:
            return True, "\n".join(collected), ""
    return False, "\n".join(collected), "timeout"


def trace_summary(trace: str) -> str:
    stalls = 0
    main_stalls = 0
    for line in trace.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        if parts[1] == "STALL":
            stalls += 1
        if parts[1] == "MAINSTALL":
            main_stalls += 1
    return f"stall={stalls} mainstall={main_stalls} trace_lines={len(trace.splitlines())}"


def print_reports(folder: Path, limit: int) -> None:
    texts = sorted(p for p in folder.rglob("*")
                   if p.is_file() and p.suffix == ".txt" and p.name != TRACE_NAME)
    others = sorted(p for p in folder.rglob("*")
                    if p.is_file() and p not in texts and p.name != TRACE_NAME)
    for path in texts:
        content = path.read_text(encoding="utf-8", errors="replace").strip()
        print(f"\n--- {path.relative_to(folder)} ({len(content)} characters) ---")
        print(content[:limit] + ("\n… truncated" if len(content) > limit else ""))
    if others:
        print("\nOther files:")
        for path in others:
            print(f"  {path.relative_to(folder)} ({path.stat().st_size} bytes)")


def build_and_install(device: Device) -> None:
    common.generate_project(force=True)
    app = common.build_app("Debug", f"platform=iOS,id={device.udid}", DERIVED)
    print("Installing on the device …")
    installed = common.install_app(app, device)
    if installed.returncode != 0:
        fail(f"installation failed (exit {installed.returncode}):\n"
             + tail(installed.stdout + installed.stderr) + common.explain(installed.stderr))
    print(f"Installation finished: {app}")


def run_scenario(device: Device, scenario: Scenario, args) -> RunResult:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    folder = Path(args.outdir) / f"{stamp}-{scenario.name.replace('.', '_')}"
    print(f"\n=== {scenario.name} on {device.name} ===")
    if scenario.reports:
        print("Expected reports: " + ", ".join(scenario.reports))
    if scenario.needs_fixtures:
        print("Note: uses the stored test pictures — on 'kein bild' run 'makefixtures' first.")
    if scenario.destructive and not args.yes:
        answer = input(f"'{scenario.name}' deletes data on the device. Type YES to run: ").strip()
        if answer != "YES":
            print("Skipped.")
            return RunResult(scenario.name, False, 0, folder, [], True)
    print("Keep the device unlocked and the app in the foreground — the run starts now. "
          "Do not use the device while it runs.")
    proc = launch_scenario(device, scenario.name, args.via)
    print(f"Started. Waiting for the finish signal (timeout {args.timeout}s) …")
    started = time.time()
    release_marker = RELEASABLE.get(scenario.name, "")
    release_after = args.listen_release if release_marker else 0
    finished, trace, reason = wait_for_finish(device, proc, scenario.name, args.poll, args.timeout,
                                              args.stale, folder, scenario.name.startswith("shot"),
                                              release_marker, release_after)
    stop_app(proc)
    elapsed = int(time.time() - started)
    if finished:
        print(f"Finished after {elapsed}s. {trace_summary(trace)}")
    else:
        print(f"NO finish signal after {elapsed}s ({reason or 'unknown'}). {trace_summary(trace)}")
        if reason == "console_closed" or reason.startswith("console_silent"):
            print("The console stream closed or stayed silent — the app reports only while it runs in the "
                  "foreground. Causes: device locked, app terminated, another app in the foreground.")
            shot = folder / "aborted_screen.png"
            if capture_screen(device, shot):
                print(f"Screenshot of the abort: {shot}")
            else:
                print("the screenshot of the abort could not be captured.")
        else:
            print("Causes: the probe is still running (raise --timeout), the app was terminated, "
                  "or the device was locked.")
    time.sleep(args.settle)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / TRACE_NAME).write_text(trace, encoding="utf-8")
    pulled = []
    for relative in scenario.reports:
        if pull_document(device, relative, folder / relative):
            pulled.append(relative)
            continue
        print(f"  could not pull '{relative}' — healing the file service and retrying once")
        heal_file_service(device, budget=120)
        if pull_document(device, relative, folder / relative):
            pulled.append(relative)
    print(f"Reports are in: {folder}")
    print("Pulled: " + (", ".join(pulled) if pulled else "nothing but the trace"))
    missing = [name for name in scenario.reports if name not in pulled]
    if missing:
        print("Warning: expected but never written: " + ", ".join(missing))
    print_reports(folder, args.limit)
    return RunResult(scenario.name, finished, elapsed, folder, pulled, False, reason)


def ordered_groups(scenarios: list) -> list:
    names = sorted({item.group for item in scenarios})
    return [(f"g{position}", name, [item for item in scenarios if item.group == name])
            for position, name in enumerate(names, start=1)]


def find_group(token: str, scenarios: list):
    for key, name, members in ordered_groups(scenarios):
        if token.casefold() in (key.casefold(), name.casefold()):
            return members
    return None


def group_keys_text(scenarios: list) -> str:
    return ", ".join(f"{key}={name}" for key, name, _ in ordered_groups(scenarios))


def dedupe(picked: list) -> list:
    seen = set()
    unique = []
    for item in picked:
        if item.name in seen:
            continue
        seen.add(item.name)
        unique.append(item)
    return unique


def describe_batch(wanted: list) -> str:
    groups = sorted({item.group for item in wanted})
    destructive = [item.name for item in wanted if item.destructive]
    fixtures = [item.name for item in wanted if item.needs_fixtures]
    text = f"{len(wanted)} run(s) in a row from {len(groups)} group(s): {', '.join(groups)}"
    if destructive:
        text += f"\n  Deletes data on the device: {', '.join(destructive)}"
    if fixtures:
        text += (f"\n  Needs the stored test pictures ({len(fixtures)} run(s)) — "
                 "without them they measure nothing, they just report 'kein bild'")
    return text


def confirm_batch(wanted: list, args) -> bool:
    if len(wanted) < 2 or args.yes or not sys.stdin.isatty():
        return True
    print("\n" + describe_batch(wanted))
    answer = input("Run all of it on the device? [y/N] ").strip().lower()
    return answer in ("y", "yes")


def run_batch(device: Device, wanted: list, args, all_scenarios: list = ()) -> list:
    results = []
    total = len(wanted)
    fixtures = next((item for item in all_scenarios if item.name == FIXTURES_SCENARIO), None)
    provisioned = False
    for position, scenario in enumerate(wanted, start=1):
        if total > 1:
            print(f"\n--- run {position}/{total} ---")
        if fixtures is not None and scenario.needs_fixtures:
            if not provisioned:
                print(f"Creating the test pictures for '{scenario.name}' first ({FIXTURES_SCENARIO}) …")
                run_scenario(device, fixtures, args)
                provisioned = True
            elif scenario.destructive:
                print(f"Fresh test pictures after the deletion in '{scenario.name}' …")
                results.append(run_scenario(device, scenario, args))
                provisioned = False
                continue
        results.append(run_scenario(device, scenario, args))
        if scenario.destructive:
            provisioned = False
    return results


def print_summary(results: list) -> None:
    if len(results) < 2:
        return
    print(f"\nSummary ({len(results)} runs)")
    for result in results:
        if result.skipped:
            status = "SKIPPED"
            detail = "-"
        elif result.finished:
            status = "FINISHED"
            detail = f"{result.seconds}s, {len(result.pulled)} file(s)"
        else:
            status = "NO FINISH"
            detail = f"{result.seconds}s, {len(result.pulled)} file(s), {result.reason or '?'}"
        print(f"  {status:<13} {result.name:<30} {detail:<20} {result.folder.name}")
    unfinished = [item.name for item in results if not item.finished and not item.skipped]
    if unfinished:
        print("Without a finish signal: " + ", ".join(unfinished))


def print_menu(scenarios: list) -> None:
    width = shutil.get_terminal_size((150, 40)).columns
    for key, name, members in ordered_groups(scenarios):
        print(f"\n{name}  [{key} = all {len(members)} of them]")
        for scenario in members:
            marks = ""
            if scenario.destructive:
                marks += " [DELETES DATA]"
            if scenario.needs_fixtures:
                marks += " [Fixtures]"
            line = f"  {scenario.index:>3}  {scenario.name}{marks}"
            if scenario.reports:
                line += " → " + ", ".join(scenario.reports)
            print(line[:max(70, width - 2)])


def resolve_choice(choice: str, scenarios: list) -> list:
    picked = []
    for token in [part.strip() for part in choice.replace(";", ",").split(",") if part.strip()]:
        if token.casefold() == "all":
            picked.extend(scenarios)
            continue
        members = find_group(token, scenarios)
        if members is not None:
            picked.extend(members)
            continue
        if token.isdigit():
            number = int(token)
            match = [item for item in scenarios if item.index == number]
            if not match:
                print(f"Number {number} is not in the menu.")
                continue
            picked.append(match[0])
            continue
        match = [item for item in scenarios if item.name == token]
        if not match:
            print(f"Unknown scenario '{token}' — the list shows every valid name "
                  f"(an unknown name triggers a picture edit in the app instead).")
            continue
        picked.append(match[0])
    return dedupe(picked)


def pick_device(requested: str) -> Device:
    devices = common.list_devices()
    if not devices:
        fail("No physical, paired device in 'xcrun devicectl list devices' — "
             "check the cable/Wi-Fi and let the device trust this Mac")
    chosen = None
    if requested:
        for device in devices:
            if requested in (device.udid, device.name):
                chosen = device
                break
        if chosen is None:
            fail(f"Device '{requested}' not found. Available: "
                 + ", ".join(f"{item.name} ({item.link})" for item in devices))
    elif len(devices) == 1:
        chosen = devices[0]
    else:
        print("Several devices available:")
        for position, device in enumerate(devices, start=1):
            print(f"  {position}  {device.label()}")
        answer = input("Device (number): ").strip()
        if not (answer.isdigit() and 1 <= int(answer) <= len(devices)):
            fail("Not a valid device number")
        chosen = devices[int(answer) - 1]
    common.check_reachable(chosen)
    return chosen


def pick_scenarios(requested: str, scenarios: list) -> list:
    wanted = []
    for token in [part.strip() for part in requested.split(",") if part.strip()]:
        match = [item for item in scenarios if item.name == token]
        if not match:
            fail(f"Unknown scenario '{token}' — --list shows every name")
        wanted.append(match[0])
    if not wanted:
        fail("--scenario was empty")
    return wanted


def pick_groups(requested: str, scenarios: list) -> list:
    wanted = []
    for token in [part.strip() for part in requested.split(",") if part.strip()]:
        if token.casefold() == "all":
            wanted.extend(scenarios)
            continue
        members = find_group(token, scenarios)
        if members is None:
            fail(f"Unknown group '{token}'. Available: {group_keys_text(scenarios)}, or 'all'")
        wanted.extend(members)
    if not wanted:
        fail("--group was empty")
    return dedupe(wanted)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="device-test",
        description="Test individual GwenMobile features on the connected iPhone, one at a time")
    parser.add_argument("--list", action="store_true", help="show the scenarios and exit")
    parser.add_argument("--scenario", help="scenario(s), comma-separated; replaces the menu")
    parser.add_argument("--group", help="whole group(s): g1…, group name or 'all', comma-separated")
    parser.add_argument("--plan", action="store_true",
                        help="only show what --scenario/--group would run, without a device")
    parser.add_argument("--device", help="UDID or device name")
    parser.add_argument("--build", action="store_true", help="rebuild and reinstall before the run")
    parser.add_argument("--via", choices=("url", "args"), default="url",
                        help="how to start: URL scheme (default) or launch argument -gwenflowtest")
    parser.add_argument("--poll", type=int, default=1,
                        help="seconds between the console reads (the app reports over --console)")
    parser.add_argument("--timeout", type=int, default=1800, help="seconds to wait before giving up")
    parser.add_argument("--stale", type=int, default=45,
                        help="seconds without a new console line before the run counts as broken "
                             "(the app writes a STATS line every 2s while it is in the foreground)")
    parser.add_argument("--settle", type=int, default=1, help="seconds to wait before pulling the reports")
    parser.add_argument("--listen-release", type=int, default=20,
                        help="seconds before the runner releases the listen-route probe early "
                             "(0 = never, the probe waits its own 300s)")
    parser.add_argument("--limit", type=int, default=REPORT_LIMIT, help="characters per report in the terminal")
    parser.add_argument("--outdir", default=str(REPORT_ROOT), help="target folder for the reports")
    parser.add_argument("--yes", action="store_true",
                        help="no follow-up questions, not even for destructive probes")
    args = parser.parse_args()

    scenarios = discover_scenarios()
    if not scenarios:
        fail("No scenario found in the code")
    for position, scenario in enumerate(scenarios, start=1):
        scenario.index = position

    if args.list:
        print_menu(scenarios)
        print(f"\n{len(scenarios)} scenarios in {len(ordered_groups(scenarios))} groups "
              f"({group_keys_text(scenarios)}), read from {PROBE_DIR.relative_to(REPO)}/")
        return

    wanted = []
    if args.group:
        wanted.extend(pick_groups(args.group, scenarios))
    if args.scenario:
        wanted.extend(pick_scenarios(args.scenario, scenarios))
    wanted = dedupe(wanted)

    if args.plan:
        if not wanted:
            fail("--plan needs --scenario or --group")
        print(describe_batch(wanted))
        for item in wanted:
            marks = ""
            if item.destructive:
                marks += " [DELETES DATA]"
            if item.needs_fixtures:
                marks += " [Fixtures]"
            print(f"  {item.index:>3}  {item.name}{marks}"
                  + (" → " + ", ".join(item.reports) if item.reports else ""))
        return

    device = pick_device(args.device)
    print(f"Device: {device.label()}")

    if args.build:
        build_and_install(device)

    if wanted:
        if not confirm_batch(wanted, args):
            print("Aborted — nothing was executed.")
            return
        results = run_batch(device, wanted, args, scenarios)
        print_summary(results)
        if any(not item.finished and not item.skipped for item in results):
            print("\nERROR: at least one run never reported its end.")
            raise SystemExit(1)
        print(f"\n{len(results)} run(s) reported that they finished.")
        return

    if not sys.stdin.isatty():
        fail("Without a terminal please use --scenario <name> or --group <g1|name|all>; "
             "--list shows both")

    print_menu(scenarios)
    print(f"\n{len(scenarios)} scenarios in {len(ordered_groups(scenarios))} groups. Input: "
          f"number, name or group ({group_keys_text(scenarios)}, 'all'), several separated by commas; "
          f"l=list, b=rebuild+install, d=another device, q=quit")
    while True:
        try:
            choice = input("\nWhat should be tested on the device? ").strip()
            if not choice:
                continue
            if choice.lower() == "q":
                return
            if choice.lower() == "l":
                print_menu(scenarios)
                continue
            if choice.lower() == "b":
                build_and_install(device)
                continue
            if choice.lower() == "d":
                device = pick_device(None)
                print(f"Device: {device.label()}")
                continue
            picked = resolve_choice(choice, scenarios)
            if not picked:
                continue
            if not confirm_batch(picked, args):
                print("Aborted — nothing was executed.")
                continue
            print_summary(run_batch(device, picked, args, scenarios))
        except KeyboardInterrupt:
            print("\nAborted — back to the menu.")
        except EOFError:
            print("\nFinished.")
            return


faulthandler.register(signal.SIGUSR1)

if __name__ == "__main__":
    main()
