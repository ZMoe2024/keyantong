#!/usr/bin/env python3
"""
Sync ablesci.com cookies from a Chrome remote debugging session.

Prerequisites:
1. Chrome "Allow remote debugging for this browser instance" is enabled.
2. You are already logged in at https://www.ablesci.com/ in that browser.
3. Python package websockets is installed:
     pip install websockets
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys

import websockets


_local_app_data = os.environ.get("LOCALAPPDATA")
if _local_app_data:
    DEFAULT_ACTIVE_PORT_PATH = Path(_local_app_data) / "Google/Chrome/User Data/DevToolsActivePort"
else:
    DEFAULT_ACTIVE_PORT_PATH = Path.home() / "AppData/Local/Google/Chrome/User Data/DevToolsActivePort"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync AbleSci cookie from Chrome DevTools.")
    parser.add_argument(
        "--active-port-file",
        type=Path,
        default=DEFAULT_ACTIVE_PORT_PATH,
        help="Path to Chrome DevToolsActivePort file.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "ablesci_cookie.txt",
        help="Output cookie file path.",
    )
    return parser.parse_args()


def load_ws_url(active_port_file: Path) -> str:
    if not active_port_file.exists():
        raise FileNotFoundError(
            f"DevToolsActivePort file not found: {active_port_file}. "
            "Enable Chrome remote debugging first."
        )

    lines = active_port_file.read_text(encoding="utf-8").splitlines()
    if len(lines) < 2:
        raise RuntimeError(f"Invalid DevToolsActivePort format: {active_port_file}")

    port = lines[0].strip()
    ws_path = lines[1].strip()
    if not port.isdigit():
        raise RuntimeError(f"Invalid DevTools port in {active_port_file}: {port}")
    if not ws_path.startswith("/"):
        raise RuntimeError(f"Invalid DevTools websocket path in {active_port_file}: {ws_path}")

    return f"ws://127.0.0.1:{port}{ws_path}"


async def recv_for_id(ws: websockets.ClientConnection, wanted_id: int) -> dict:
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == wanted_id:
            return msg


async def pull_ablesci_cookies(ws_url: str) -> list[dict]:
    async with websockets.connect(ws_url, open_timeout=5) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Storage.getCookies"}))
        resp = await recv_for_id(ws, 1)
        result = resp.get("result", {})
        cookies = result.get("cookies", [])

    return [c for c in cookies if "ablesci.com" in c.get("domain", "")]


def to_cookie_header(cookies: list[dict]) -> str:
    ordered = sorted(cookies, key=lambda c: (c.get("name", ""), c.get("domain", "")))
    return "; ".join(f"{c['name']}={c['value']}" for c in ordered)


def main() -> int:
    args = parse_args()

    try:
        ws_url = load_ws_url(args.active_port_file)
        cookies = asyncio.run(pull_ablesci_cookies(ws_url))
        if not cookies:
            raise RuntimeError(
                "No ablesci.com cookies found. Open https://www.ablesci.com/ and login first."
            )

        cookie_header = to_cookie_header(cookies)
        args.output.write_text(cookie_header, encoding="utf-8")
        print(f"Saved {len(cookies)} cookies to {args.output}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
