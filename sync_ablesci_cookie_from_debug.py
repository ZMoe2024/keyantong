#!/usr/bin/env python3
"""
Sync ablesci.com cookies from a Chrome remote debugging session.

This script can optionally visit/refresh https://www.ablesci.com/ before
reading cookies so the next-day sign state is discoverable without manual
page refresh.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
from urllib.request import ProxyHandler, build_opener

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
        help="Path to Chrome DevToolsActivePort file (used when --debug-port is not provided).",
    )
    parser.add_argument(
        "--debug-host",
        default="127.0.0.1",
        help="DevTools host when using --debug-port (default: 127.0.0.1).",
    )
    parser.add_argument(
        "--debug-port",
        type=int,
        default=None,
        help="DevTools fixed port (reads webSocketDebuggerUrl from /json/version).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "ablesci_cookie.txt",
        help="Output cookie file path.",
    )
    parser.add_argument(
        "--visit-url",
        default="",
        help="Optional URL to open or refresh before reading cookies.",
    )
    parser.add_argument(
        "--visit-wait-seconds",
        type=float,
        default=6.0,
        help="Seconds to wait after navigation before reading cookies.",
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


def load_ws_url_from_debug_port(debug_host: str, debug_port: int) -> str:
    version_url = f"http://{debug_host}:{debug_port}/json/version"
    try:
        opener = build_opener(ProxyHandler({}))
        with opener.open(version_url, timeout=3) as resp:
            content = resp.read().decode("utf-8")
    except Exception as exc:
        raise RuntimeError(f"Cannot read {version_url}: {exc}") from exc

    try:
        payload = json.loads(content)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON from {version_url}: {exc}") from exc

    ws_url = payload.get("webSocketDebuggerUrl")
    if not ws_url or not isinstance(ws_url, str):
        raise RuntimeError(f"webSocketDebuggerUrl missing in {version_url}")

    return ws_url


async def recv_for_id(
    ws: websockets.ClientConnection, wanted_id: int, session_id: str | None = None
) -> dict:
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") != wanted_id:
            continue
        if session_id is not None and msg.get("sessionId") != session_id:
            continue
        if "error" in msg:
            raise RuntimeError(f"CDP error for id={wanted_id}: {msg['error']}")
        return msg


async def cdp_call(
    ws: websockets.ClientConnection,
    call_id: int,
    method: str,
    params: dict | None = None,
    session_id: str | None = None,
) -> dict:
    payload: dict = {"id": call_id, "method": method}
    if params:
        payload["params"] = params
    if session_id is not None:
        payload["sessionId"] = session_id

    await ws.send(json.dumps(payload))
    resp = await recv_for_id(ws, call_id, session_id=session_id)
    return resp.get("result", {})


async def refresh_ablesci_page(
    ws: websockets.ClientConnection,
    visit_url: str,
    wait_seconds: float,
) -> None:
    target_infos = (
        await cdp_call(ws, 1, "Target.getTargets")
    ).get("targetInfos", [])

    target_id = None
    for info in target_infos:
        if info.get("type") == "page" and "ablesci.com" in info.get("url", ""):
            target_id = info.get("targetId")
            break

    if target_id is None:
        for info in target_infos:
            if info.get("type") != "page":
                continue
            url = info.get("url", "")
            if url.startswith("about:blank") or url.startswith("chrome://newtab") or url.startswith("chrome://new-tab-page"):
                target_id = info.get("targetId")
                break

    if target_id is None:
        target_id = (await cdp_call(ws, 2, "Target.createTarget", {"url": visit_url})).get("targetId")
        if not target_id:
            raise RuntimeError("Failed to create DevTools target for AbleSci")

    attach_result = await cdp_call(
        ws, 3, "Target.attachToTarget", {"targetId": target_id, "flatten": True}
    )
    session_id = attach_result.get("sessionId")
    if not session_id:
        raise RuntimeError("Failed to attach to DevTools target")

    await cdp_call(ws, 4, "Page.enable", session_id=session_id)
    await cdp_call(ws, 5, "Target.activateTarget", {"targetId": target_id})
    await cdp_call(ws, 6, "Page.navigate", {"url": visit_url}, session_id=session_id)
    await asyncio.sleep(max(wait_seconds, 0))


async def pull_ablesci_cookies(
    ws_url: str, visit_url: str = "", visit_wait_seconds: float = 0
) -> list[dict]:
    async with websockets.connect(ws_url, open_timeout=5) as ws:
        if visit_url:
            await refresh_ablesci_page(ws, visit_url, visit_wait_seconds)

        result = await cdp_call(ws, 10, "Storage.getCookies")
        cookies = result.get("cookies", [])

    return [c for c in cookies if "ablesci.com" in c.get("domain", "")]


def to_cookie_header(cookies: list[dict]) -> str:
    ordered = sorted(cookies, key=lambda c: (c.get("name", ""), c.get("domain", "")))
    return "; ".join(f"{c['name']}={c['value']}" for c in ordered)


def has_login_cookie(cookies: list[dict]) -> bool:
    names = {str(c.get("name", "")).strip() for c in cookies}
    # _identity-frontend is the stable authenticated cookie observed on AbleSci.
    # advanced-frontend is a fallback session identifier.
    return ("_identity-frontend" in names) or ("advanced-frontend" in names)


def main() -> int:
    args = parse_args()

    try:
        if args.debug_port is not None:
            ws_url = load_ws_url_from_debug_port(args.debug_host, args.debug_port)
        else:
            ws_url = load_ws_url(args.active_port_file)
        cookies = asyncio.run(
            pull_ablesci_cookies(
                ws_url,
                visit_url=args.visit_url,
                visit_wait_seconds=args.visit_wait_seconds,
            )
        )
        if not cookies:
            raise RuntimeError(
                "No ablesci.com cookies found. Open https://www.ablesci.com/ and login first."
            )
        if not has_login_cookie(cookies):
            raise RuntimeError(
                "Found ablesci.com cookies but no login session cookie. "
                "Please login at https://www.ablesci.com/ in the managed debug Chrome first."
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
