#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
import time


PROMPT_MARKERS = (
    "要允许远程调试吗？",
    "Allow remote debugging?",
    "远程调试",
    "remote debugging",
)

ALLOW_LABELS = ("允许", "Allow")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Best-effort auto-approve for Chrome remote debugging prompt.")
    parser.add_argument("--timeout-seconds", type=float, default=15.0)
    parser.add_argument("--poll-seconds", type=float, default=0.25)
    return parser.parse_args()


def contains_prompt_text(window) -> bool:
    try:
        texts = []
        for element in window.descendants():
            text = (element.window_text() or "").strip()
            if text:
                texts.append(text)
        blob = "\n".join(texts).lower()
        return any(marker.lower() in blob for marker in PROMPT_MARKERS)
    except Exception:
        return False


def find_allow_button(window):
    try:
        for element in window.descendants():
            text = (element.window_text() or "").strip()
            if text in ALLOW_LABELS:
                return element
    except Exception:
        return None
    return None


def main() -> int:
    args = parse_args()

    try:
        from pywinauto import Desktop
    except Exception as exc:
        print(f"ERROR: pywinauto unavailable: {exc}", file=sys.stderr)
        return 2

    deadline = time.time() + max(args.timeout_seconds, 0)

    while time.time() < deadline:
        try:
            windows = Desktop(backend="uia").windows()
        except Exception as exc:
            print(f"ERROR: cannot enumerate windows: {exc}", file=sys.stderr)
            return 3

        for window in windows:
            title = (window.window_text() or "").strip()
            if "Chrome" not in title:
                continue
            if not contains_prompt_text(window):
                continue

            allow_button = find_allow_button(window)
            if allow_button is None:
                continue

            try:
                window.set_focus()
            except Exception:
                pass

            try:
                allow_button.click_input()
                print("approved")
                return 0
            except Exception:
                try:
                    allow_button.invoke()
                    print("approved")
                    return 0
                except Exception:
                    continue

        time.sleep(max(args.poll_seconds, 0.05))

    print("prompt-not-found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
