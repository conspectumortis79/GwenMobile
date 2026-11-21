#!/usr/bin/env python3
import subprocess
import sys
from datetime import datetime
from pathlib import Path

NOTIFY_TITLE = "GwenMobile 7-day signing"
MANUAL_TITLE = "GwenMobile: a manual step is due"
HISTORY = "history.log"
NOTIFY_TIMEOUT = 30
GREETING = "renewal run at {when:%Y-%m-%d %H:%M:%S}"
MARKS = {True: "✓", False: "✗"}


def keep_line(plan) -> str:
    return f"  {plan.title}: kept — {plan.reason}"


def outcome_line(outcome) -> str:
    return f"  {MARKS[outcome.ok]} {outcome.title}: {outcome.status_text()}"


def note_line(outcome) -> str:
    lines = []
    if outcome.note:
        lines.append(f"    note: {outcome.note}")
    if outcome.manual:
        lines.append(f"    manual step: {outcome.manual}")
    return "\n".join(lines)


def plan_lines(plans, options) -> tuple:
    lines = []
    for plan in plans:
        if not plan.renew:
            continue
        steps = [f"  retire the cached {plan.spec.kind} profile of {plan.spec.bundle_id}",
                 f"  xcodebuild build ({plan.spec.kind}, {options.configuration or plan.spec.configuration})"]
        if plan.target_id == "iphone":
            steps.append("  devicectl device install app")
            if options.launch:
                steps.append("  devicectl device process launch")
        else:
            steps.append("  copy the bundle to " + str(options.mac_target))
        lines.extend(steps)
    return tuple(lines)


def report(plans, outcomes, moment: datetime) -> str:
    lines = [GREETING.format(when=moment)]
    for plan in plans:
        lines.append(keep_line(plan) if not plan.renew else f"  {plan.title}: {plan.reason}")
    for outcome in outcomes:
        extra = note_line(outcome)
        lines.append(outcome_line(outcome) + ("\n" + extra if extra else ""))
    return "\n".join(lines)


def summary(plans, outcomes) -> str:
    renewed = tuple(item for item in outcomes if item.ok)
    failed = tuple(item.title for item in outcomes if not item.ok)
    skipped = tuple(plan.title for plan in plans if not plan.renew)
    parts = []
    if renewed:
        parts.append("renewed: " + ", ".join(f"{item.title} → {item.expires_text()}"
                                             for item in renewed))
    if skipped:
        parts.append("unchanged: " + ", ".join(skipped))
    if failed:
        parts.append("FAILED: " + ", ".join(failed))
    return "; ".join(parts) or "nothing to do"


def manual_text(outcomes) -> str:
    return "\n".join(item.manual for item in outcomes if item.manual)


def history_line(plans, outcomes, moment: datetime) -> str:
    return f"{moment:%Y-%m-%d %H:%M:%S}  {summary(plans, outcomes)}\n"


def append_history(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)
    return path


def apple_script(text: str, title: str, sound: bool) -> str:
    body = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    head = title.replace('"', '\\"')
    return (f'display notification "{body}" with title "{head}"'
            + (' sound name "Ping"' if sound else ""))


def notify(text: str, title: str = NOTIFY_TITLE, sound: bool = True, run=subprocess.run) -> int:
    done = run(["/usr/bin/osascript", "-e", apple_script(text, title, sound)],
               capture_output=True, text=True, timeout=NOTIFY_TIMEOUT)
    if done.returncode != 0:
        print("notification failed: " + (done.stderr or done.stdout).strip()[:200], file=sys.stderr)
    return done.returncode


def want_notify(flag: bool, quiet: bool, stream=None) -> bool:
    if quiet:
        return False
    if flag:
        return True
    return not (stream or sys.stdout).isatty()


def exit_code(outcomes) -> int:
    return 1 if any(not item.ok for item in outcomes) else 0
