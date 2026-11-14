#!/usr/bin/env python3
import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
from common import (APP_NAME, BUNDLE_ID, PROJECT, REPO, SCHEME, Device, explain, fail, git_info,
                    installed_build, plist_value, probe_url, tail, xcodebuild_path, xcrun)

DERIVED = REPO / "build" / "Deploy"
INSTALL_RETRIES = 2


def print_devices(devices: list) -> None:
    if not devices:
        print("No paired physical device in 'xcrun devicectl list devices'.")
        print(explain("reality"))
        return
    for position, device in enumerate(devices, start=1):
        print(f"  {position}  {device.name}  {device.model}  iOS {device.system}  "
              f"{device.link}  {device.udid}")


def pick_device(requested: str, assume_yes: bool) -> Device:
    devices = common.list_devices()
    if not devices:
        fail("No paired physical device found.\n"
             "Plug in the cable (or put the iPhone and the Mac on the same Wi-Fi), unlock the iPhone,\n"
             "confirm “Trust This Computer”, turn developer mode on.")
    if requested:
        for device in devices:
            if requested in (device.udid, device.name) or requested == device.udid.lower():
                return common.check_reachable(device)
        fail(f"Device '{requested}' is not in the list. Available: "
             + ", ".join(f"{item.name} ({item.link})" for item in devices))
    if len(devices) == 1:
        return common.check_reachable(devices[0])
    print("Several devices found:")
    print_devices(devices)
    if assume_yes:
        fail("Several devices — decide with --device UDID|Name.")
    answer = input("Device (number): ").strip()
    if not (answer.isdigit() and 1 <= int(answer) <= len(devices)):
        fail("Not a valid device number")
    return common.check_reachable(devices[int(answer) - 1])


def build(destination: str, configuration: str, clean: bool) -> Path:
    return common.build_app(configuration, destination, DERIVED, clean=clean)


def install(app: Path, device: Device, retries: int, assume_yes: bool) -> None:
    print(f"Installing on {device.name} …")
    for attempt in range(1, retries + 2):
        done = common.install_app(app, device)
        text = done.stdout + done.stderr
        if done.returncode == 0:
            print(f"Installation ok (attempt {attempt}).")
            return
        print(f"Attempt {attempt} failed (exit {done.returncode}):\n{tail(text, 12)}")
        hint = explain(text)
        if hint:
            print("Possible cause:\n" + hint)
        if attempt > retries:
            break
        if not assume_yes and ("unlock" in text.lower() or "locked" in text.lower() or attempt >= 2):
            print("   the device has to be unlocked and reachable")
            try:
                input("iPhone unlocked? [Enter for another attempt, anything else aborts]: ")
            except (EOFError, KeyboardInterrupt):
                fail("Aborted before the installation — the built .app stays under "
                     f"{app} and can be installed with --skip-build.")
        else:
            print("   next attempt after a short pause …")
            time.sleep(5)
    fail("Installation not possible. Check: cable/Wi-Fi, unlocked display, "
         "“Trust This Computer”, developer mode on, free storage on the iPhone.\n"
         "The built .app stays where it is: --skip-build installs it again.")


def launch(device: Device, url: str, console: bool) -> None:
    print("Starting the app on the device …" + (f" with {url}" if url else ""))
    if console:
        common.launch_app(device, url=url, console=True)
        return
    done = common.launch_app(device, url=url)
    if done.returncode != 0:
        text = done.stdout + done.stderr
        fail(f"Start failed (exit {done.returncode}):\n{tail(text, 10)}"
             + explain(text) + "\nThe installation itself went through — open the app by hand.")
    print("App is running.")


def show_plan(arguments: list) -> None:
    print("Planned command sequence (--plan, nothing was executed):")
    for item in arguments:
        print("  $ " + " ".join(str(part) for part in item))


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="deploy-iphone",
        description="Build GwenMobile and install it on the connected iPhone",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
    ./scripts/deploy-iphone.py                       # build, install, launch
    ./scripts/deploy-iphone.py --list                # paired devices
    ./scripts/deploy-iphone.py --device <UDID|Name>  # pick one, without asking
    ./scripts/deploy-iphone.py --no-launch           # install only
    ./scripts/deploy-iphone.py --skip-build          # install the .app that is already built
    ./scripts/deploy-iphone.py --open webask         # start straight into a probe
    ./scripts/deploy-iphone.py --console             # attach the device console
    ./scripts/deploy-iphone.py --build-only          # no device, generic destination
    ./scripts/deploy-iphone.py --plan                # show the commands, do nothing
""")
    parser.add_argument("--device", help="UDID or device name (otherwise asked, or picked automatically)")
    parser.add_argument("--list", action="store_true", help="show paired devices and exit")
    parser.add_argument("--configuration", default="Debug",
                        help="Debug (default) or Release")
    parser.add_argument("--clean", action="store_true", help="clean before building")
    parser.add_argument("--generate", action="store_true", help="always run xcodegen")
    parser.add_argument("--no-generate", action="store_true", help="never run xcodegen")
    parser.add_argument("--skip-build", action="store_true",
                        help="install the .app that is already there (fast iteration cycle)")
    parser.add_argument("--build-only", action="store_true",
                        help="build only, no device needed (generic iOS destination)")
    parser.add_argument("--no-install", action="store_true", help="build, but install nothing")
    parser.add_argument("--no-launch", action="store_true", help="install, but do not launch")
    parser.add_argument("--open", metavar="URL", help="launch with a URL, e.g. gwenmobile://test/webask "
                                                  "or just a scenario name such as webask")
    parser.add_argument("--console", action="store_true", help="attach the device console to the app")
    parser.add_argument("--retries", type=int, default=INSTALL_RETRIES, help="repetitions of the install step")
    parser.add_argument("--no-verify", action="store_true",
                        help="do not read the installed build back off the device")
    parser.add_argument("--yes", action="store_true", help="never prompt (device choice)")
    parser.add_argument("--plan", action="store_true", help="show what would run, without a device")
    args = parser.parse_args()

    if args.list:
        print_devices(common.list_devices())
        return

    started = time.monotonic()
    print(f"Start: {datetime.now():%Y-%m-%d %H:%M:%S}")
    print(f"Xcode: {common.xcode_root()}")
    print(f"Revision: {git_info()}")

    if args.plan:
        print("Project generation: " + ("forced" if args.generate else
              ("skipped" if args.no_generate else
               ("needed (project older than the sources)" if common.needs_generation() else "not needed"))))
        show_plan(([["xcodegen", "generate"]]
                   if (args.generate or common.needs_generation()) else []) + [
            [xcodebuild_path(), "-project", PROJECT, "-scheme", SCHEME,
             "-configuration", args.configuration, "-destination",
             "platform=iOS,id=<UDID>", "-derivedDataPath", DERIVED,
             "-allowProvisioningUpdates", "-skipMacroValidation"] + (["clean"] if args.clean else []) + ["build"],
            [xcrun(), "devicectl", "device", "install", "app", "--device", "<UDID>",
             f"{DERIVED}/Build/Products/{args.configuration}-iphoneos/{APP_NAME}"],
            [xcrun(), "devicectl", "device", "process", "launch", "--device", "<UDID>",
             "--terminate-existing", BUNDLE_ID],
        ])
        return

    if args.build_only and not args.device:
        print("--build-only without a device: building for the generic iOS destination.")
        common.generate_project(args.generate, args.no_generate)
        app = build("generic/platform=iOS", args.configuration, args.clean)
        print(f"Done: {app}\nInstall it with: ./scripts/deploy-iphone.py --skip-build")
        return

    device = pick_device(args.device, args.yes)
    print(f"Device: {device.name} ({device.model}, iOS {device.system}, {device.link})")

    common.generate_project(args.generate, args.no_generate)
    if args.skip_build:
        app = DERIVED / "Build" / "Products" / f"{args.configuration}-iphoneos" / APP_NAME
        if not app.is_dir():
            fail(f"{app} is missing — build it once without --skip-build.")
        print(f"Reusing the finished build: {app}")
    else:
        app = build(f"platform=iOS,id={device.udid}", args.configuration, args.clean)

    print(f"App inside the build: version {plist_value(app, 'CFBundleShortVersionString')} "
          f"(build {plist_value(app, 'CFBundleVersion')}), bundle {BUNDLE_ID}")

    if args.no_install:
        print("--no-install: installation skipped.")
        return

    install(app, device, max(0, args.retries), args.yes)
    on_device = installed_build(device) if not args.no_verify else "?"

    if not args.no_launch:
        launch(device, probe_url(args.open), args.console)

    print(f"\nDeployed to {device.name} in {int(time.monotonic() - started)}s — "
          f"installed build according to the device: {on_device}")
    print("Next: ./scripts/device-test.py --list  (feature probes on the device)")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted.")
        raise SystemExit(130)
