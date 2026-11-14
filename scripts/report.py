#!/usr/bin/env python3
import sys


def fail(text: str) -> None:
    print(f"\nERROR: {text}", file=sys.stderr)
    raise SystemExit(1)
