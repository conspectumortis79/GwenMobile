#!/usr/bin/env python3
import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import renew_report
import renew_state
import renew_targets
import renewal_policy
import renewal_schedule
import signing_config
import signing_reader
import signing_state
from report import fail

SCRIPT = Path(__file__).resolve()
HISTORY = Path(common.REPO) / "build" / "renew" / "history.log"
INSTALLS = Path(common.REPO) / "build" / "renew" / "installs.json"
SPECS = (signing_state.TargetSpec("iphone", "iPhone", signing_state.IOS, common.BUNDLE_ID, "Debug"),
         signing_state.TargetSpec("mac", "Mac (Catalyst)", signing_state.MAC, common.BUNDLE_ID,
                                  "Release"))
DEFAULT_SCHEDULE = f"{renewal_schedule.DEFAULT_HOUR:02d}:{renewal_schedule.DEFAULT_MINUTE:02d}"


def parser() -> argparse.ArgumentParser:
    usage = argparse.ArgumentParser(
        prog="renew-gwenmobile",
        description="Keeps the free 7-day Apple signing of GwenMobile alive: checks the provisioning "
                    "profiles, rebuilds and reinstalls before they expire, and can schedule itself "
                    "daily through launchd.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
    ./scripts/renew-gwenmobile.py                        # status: what expires when
    ./scripts/renew-gwenmobile.py --renew                # renew everything due
    ./scripts/renew-gwenmobile.py --renew --force        # rebuild and reinstall both targets now
    ./scripts/renew-gwenmobile.py --renew --targets mac  # only the Mac app
    ./scripts/renew-gwenmobile.py --plan                 # show the steps, run nothing
    ./scripts/renew-gwenmobile.py --install-schedule 09:20   # daily launchd job
    ./scripts/renew-gwenmobile.py --start-now            # trigger that job right now
    ./scripts/renew-gwenmobile.py --remove-schedule
""")
    usage.add_argument("--renew", action="store_true", help="rebuild and install the due targets")
    usage.add_argument("--status", action="store_true",
                       help="show the profile dates and the schedule (shown when no command is given)")
    usage.add_argument("--force", action="store_true", help="ignore the remaining days, renew anyway")
    usage.add_argument("--targets", default="all", help="iphone,mac,all (default: all)")
    usage.add_argument("--threshold", type=float, default=renewal_policy.DEFAULT_THRESHOLD_DAYS,
                       help=f"renew when fewer than this many days are left (default "
                            f"{renewal_policy.DEFAULT_THRESHOLD_DAYS:g})")
    usage.add_argument("--device", default="", help="iPhone name or UDID (default: the only paired one)")
    usage.add_argument("--wait-minutes", type=float, default=0.0,
                       help="wait for the iPhone to connect (the scheduled run uses 20)")
    usage.add_argument("--configuration", default="", choices=("", "Debug", "Release"),
                       help="build both targets this way (default: each target keeps its own — "
                            "Debug on the iPhone, Release on the Mac)")
    usage.add_argument("--clean", action="store_true", help="xcodebuild clean before building")
    usage.add_argument("--no-launch", action="store_true", help="install but do not start the app")
    usage.add_argument("--restart-mac", action="store_true",
                       help="restart the running Mac app after installing it")
    usage.add_argument("--plan", action="store_true", help="show the planned steps, run nothing")
    usage.add_argument("--install-schedule", metavar="HH:MM", nargs="?", const=DEFAULT_SCHEDULE,
                       help=f"write and load the daily launchd job (default {DEFAULT_SCHEDULE})")
    usage.add_argument("--remove-schedule", action="store_true", help="unload and delete the launchd job")
    usage.add_argument("--start-now", action="store_true", help="kickstart the scheduled job")
    usage.add_argument("--notify", action="store_true", help="always post a macOS notification")
    usage.add_argument("--no-notify", action="store_true", help="never post a notification")
    return usage


def wanted_targets(text: str) -> tuple:
    return tuple(item.strip() for item in (text or "all").split(",") if item.strip())


def plans_for(args, moment: datetime) -> tuple:
    state = signing_state.SigningState.load(signing_reader.read_all, moment)
    installs = renew_state.Installs.load(INSTALLS, moment)
    try:
        return renewal_policy.decide(SPECS, state, args.threshold, args.force,
                                     wanted_targets(args.targets), installs)
    except ValueError as exc:
        fail(str(exc))


def device_lines() -> tuple:
    devices = renew_targets.IPhoneActions().devices()
    if not devices:
        return ("  iPhone: none paired or unreachable — cable, unlock, “Trust This Computer”",)
    return tuple(f"  iPhone {item.name}: {item.model}, iOS {item.system}, {item.link}"
                 for item in devices)


def history_tail(lines: int = 3) -> tuple:
    if not HISTORY.is_file():
        return ()
    return tuple(f"  last runs: {line}" for line in HISTORY.read_text().splitlines()[-lines:])


def mac_store_lines() -> tuple:
    ok, store, _error = renew_targets.attempt(renew_targets.MacActions().store,
                                              renew_targets.Options().mac_target)
    return (f"  Mac settings: {store.describe()}",) if ok and store else ()


def status_lines(plans, schedule: dict, moment: datetime) -> tuple:
    team = signing_config.current_team() or "-"
    lines = [f"Team {team}   Xcode {common.xcode_root()}   now {moment:%Y-%m-%d %H:%M:%S}",
             "Free Apple ID: every profile lasts 7 days, then the app has to be rebuilt and reinstalled."]
    for plan in plans:
        lines.append(f"  {plan.title}: {plan.profile_text()}")
        lines.append(f"    on the target: {plan.deadline_text()}")
        lines.append(f"    decision: {'renew' if plan.renew else 'keep'} — {plan.reason}")
    lines.extend(mac_store_lines())
    lines.extend(device_lines())
    if schedule.get("installed"):
        lines.append(f"  schedule: {schedule['time']} daily, "
                     f"{'loaded' if schedule['loaded'] else 'NOT loaded'} — {schedule['file']}")
        if schedule.get("next"):
            lines.append(f"    next run: {schedule['next']:%Y-%m-%d %H:%M} — a check, renewal only when "
                         "the days are used up")
        lines.append(f"    log: {schedule['log']}")
    else:
        lines.append("  schedule: none — ./scripts/renew-gwenmobile.py --install-schedule "
                     + DEFAULT_SCHEDULE)
    lines.extend(history_tail())
    return tuple(lines)


def options_for(args) -> renew_targets.Options:
    return renew_targets.Options(configuration=args.configuration, clean=args.clean,
                                 launch=not args.no_launch, wait_minutes=args.wait_minutes,
                                 device=args.device, restart_mac=args.restart_mac)


def command_status(args, moment: datetime) -> int:
    plans = plans_for(args, moment)
    for line in status_lines(plans, renewal_schedule.status(), moment):
        print(line)
    due = renewal_policy.due(plans)
    if due:
        print(f"\nDue now: {', '.join(item.title for item in due)}")
        print("Run:  ./scripts/renew-gwenmobile.py --renew"
              + (" --force" if args.force else ""))
    return 0


def command_plan(args, moment: datetime) -> int:
    plans = plans_for(args, moment)
    print("Planned steps (--plan, nothing was executed):")
    for plan in plans:
        print(f"  {plan.title}: {'renew' if plan.renew else 'keep'} — {plan.reason}")
    for line in renew_report.plan_lines(plans, options_for(args)):
        print(line)
    return 0


def run_renewal(plans, options) -> tuple:
    outcomes = []
    for plan in plans:
        if not plan.renew:
            continue
        print(f"\n--- {plan.title} ---")
        ok, outcome, error = renew_targets.attempt(renew_targets.adapter_for(plan, options).renew,
                                                   plan)
        outcomes.append(outcome if ok and outcome
                        else renew_targets.Outcome(plan=plan, ok=False, detail=error))
    return tuple(outcomes)


def store_installs(outcomes, moment: datetime) -> Path:
    installs = renew_state.Installs.load(INSTALLS, moment)
    for outcome in outcomes:
        target = outcome.plan.target_id
        installs = installs.recorded(target, moment) if outcome.ok else installs.marked(target)
    return renew_state.store(INSTALLS, installs)


def command_renew(args, moment: datetime) -> int:
    os.chdir(common.REPO)
    plans = plans_for(args, moment)
    for plan in plans:
        print(f"{plan.title}: {'renew' if plan.renew else 'keep'} — {plan.reason}")
    if not renewal_policy.due(plans):
        print("\nNothing is due — every profile holds longer than the threshold.")
        return 0
    outcomes = run_renewal(plans, options_for(args))
    store_installs(outcomes, moment)
    print("\n" + renew_report.report(plans, outcomes, moment))
    renew_report.append_history(HISTORY, renew_report.history_line(plans, outcomes, moment))
    manual = renew_report.manual_text(outcomes)
    if manual:
        print("\nManual step:\n" + manual)
    if outcomes and renew_report.want_notify(args.notify, args.no_notify):
        renew_report.notify(renew_report.summary(plans, outcomes),
                            title=renew_report.MANUAL_TITLE if manual else renew_report.NOTIFY_TITLE,
                            sound=bool(manual))
    return renew_report.exit_code(outcomes)


def command_install_schedule(args) -> int:
    try:
        renewal_schedule.install(args.install_schedule, SCRIPT, device=args.device)
    except ValueError as exc:
        fail(str(exc))
    code = renewal_schedule.reload()
    status = renewal_schedule.status()
    print(f"  {'loaded' if status['loaded'] else 'not loaded'} — log: {status['log']}")
    if status.get("next"):
        print(f"  next run: {status['next']:%Y-%m-%d %H:%M} — until then nothing happens, which is")
        print("  correct: the job only rebuilds when a profile is inside the threshold.")
    print("launchd only runs the job while this Mac is awake; a missed run is caught up on the next")
    print("one, because the decision is made from the profile's remaining days, not from a timer.")
    return code


def main() -> int:
    args = parser().parse_args()
    moment = datetime.now()
    if args.remove_schedule:
        return renewal_schedule.unload()
    if args.install_schedule:
        return command_install_schedule(args)
    if args.start_now:
        return renewal_schedule.start_now()
    if args.plan:
        return command_plan(args, moment)
    if args.renew:
        return command_renew(args, moment)
    return command_status(args, moment)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nAborted.")
        raise SystemExit(130)
