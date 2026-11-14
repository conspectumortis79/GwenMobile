#!/usr/bin/env python3
import argparse
import hashlib
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import mac_app
from common import APP_NAME, BUILD_TIMEOUT, PROJECT_YML, REPO, fail, plist_value, run

DERIVED = REPO / "build" / "MacDMG"
INSTALL_NOTE = "INSTALL.txt"


def build_app(configuration: str) -> Path:
    return mac_app.build(configuration, DERIVED)


def install_note(app: Path) -> str:
    version = plist_value(app, "CFBundleShortVersionString")
    build = plist_value(app, "CFBundleVersion")
    return "\n".join([
        f"GwenMobile {version} (build {build}) — Mac edition (Catalyst)",
        "",
        "1. Double-click this .dmg — the volume appears.",
        "2. Drag GwenMobile.app onto Applications.",
        "3. Eject the volume and start GwenMobile from Applications.",
        "",
        "Signature: Apple Development. If another Mac marks the file as downloaded:",
        "right-click GwenMobile -> Open, or",
        "    xattr -dr com.apple.quarantine /Applications/GwenMobile.app",
        "",
    ])


def stage(app: Path, note: str) -> Path:
    directory = Path(tempfile.mkdtemp(prefix="gwenmobile-dmg-"))
    shutil.copytree(app, directory / APP_NAME, symlinks=True)
    (directory / "Applications").symlink_to(Path("/Applications"))
    (directory / INSTALL_NOTE).write_text(note, encoding="utf-8")
    return directory


def create_dmg(source: Path, target: Path, volume: str) -> Path:
    print(f"Creating image {target.name} …")
    if target.exists():
        target.unlink()
    done = run(["hdiutil", "create", "-volname", volume, "-srcfolder", source, "-ov",
                "-format", "UDZO", target], echo=True, timeout=BUILD_TIMEOUT)
    if done.returncode != 0 or not target.is_file():
        fail("hdiutil create failed:\n" + (done.stdout + done.stderr)[-1500:])
    return target


def verify_image(image: Path) -> None:
    print("Checking the image (mount, signature, contents) …")
    mount = Path(tempfile.mkdtemp(prefix="gwenmobile-mount-"))
    attached = run(["hdiutil", "attach", image, "-nobrowse", "-readonly", "-mountpoint", mount],
                   echo=False)
    if attached.returncode != 0:
        fail("the image cannot be mounted:\n" + (attached.stdout + attached.stderr)[-800:])
    try:
        for name in (APP_NAME, "Applications", INSTALL_NOTE):
            if not (mount / name).exists() and not (mount / name).is_symlink():
                fail(f"{name} is missing from the image")
        check = run(["codesign", "--verify", "--strict", mount / APP_NAME], echo=False)
        if check.returncode != 0:
            fail("the app inside the image is not signed correctly:\n"
                 + (check.stdout + check.stderr)[-600:])
        files = sum(1 for item in (mount / APP_NAME).rglob("*") if item.is_file())
        print(f"  contents ok, {files} files in GwenMobile.app")
    finally:
        run(["hdiutil", "detach", mount, "-quiet"], echo=False)
        mount.rmdir()


def digest(path: Path) -> str:
    hash_ = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hash_.update(block)
    return hash_.hexdigest()


def human(bytes_: int) -> str:
    return f"{bytes_ / 1024 / 1024:.1f} MiB"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Builds GwenMobile for the Mac and packages it into an installable .dmg")
    parser.add_argument("--configuration", default="Release", choices=["Debug", "Release"])
    parser.add_argument("--out", default=str(Path.home() / "Desktop"),
                        help="target folder of the .dmg (default: ~/Desktop)")
    parser.add_argument("--name", help="file name without extension "
                                       "(default: GwenMobile-<version>-<date>)")
    parser.add_argument("--no-verify", action="store_true", help="do not mount and check the image")
    parser.add_argument("--clean-build", action="store_true",
                        help="delete build/MacDMG first (full rebuild instead of incremental)")
    args = parser.parse_args()

    if not PROJECT_YML.is_file():
        fail(f"{PROJECT_YML} is missing — this script belongs in the GwenMobile repository")
    if args.clean_build and DERIVED.exists():
        print(f"Removing {DERIVED} (clean build) …")
        shutil.rmtree(DERIVED)
    elif DERIVED.exists():
        print(f"Reusing {DERIVED} (incremental; --clean-build forces a full rebuild)")

    common.generate_project(force=True)
    app = build_app(args.configuration)
    mac_app.verify_entitlements(app)
    mac_app.verify_signature(app, require=args.configuration == "Release")
    note = install_note(app)
    version = plist_value(app, "CFBundleShortVersionString")
    staging = stage(app, note)
    try:
        directory = Path(args.out).expanduser()
        directory.mkdir(parents=True, exist_ok=True)
        name = args.name or f"GwenMobile-{version}-{datetime.now():%Y%m%d-%H%M}"
        image = create_dmg(staging, directory / f"{name}.dmg", f"GwenMobile {version}")
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    if not args.no_verify:
        verify_image(image)

    print(f"\nDone: {image}")
    print(f"Size: {human(image.stat().st_size)}   sha256: {digest(image)}")
    print("Installation: double-click the image, drag the app onto Applications, eject, start it.")


if __name__ == "__main__":
    os.chdir(REPO)
    main()
