"""Command-line entrypoint for the local vphone agent adapter."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Sequence

from .client import TransportError, ValidationError, send_request


EXIT_VALIDATION = 2
EXIT_TRANSPORT = 3
EXIT_HOOK = 4


def run_reset(command: Sequence[str]) -> dict[str, Any]:
    """Run an explicit lifecycle command without invoking a shell."""

    if not command or any(not isinstance(item, str) or not item for item in command):
        raise ValidationError("reset command must be a non-empty argument list")
    try:
        subprocess.run(
            list(command), check=True, capture_output=True, text=True, shell=False
        )
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        message = f"reset command failed with exit code {error.returncode}"
        if detail:
            message += f": {detail[-1000:]}"
        raise TransportError(message) from error
    except OSError as error:
        raise TransportError(f"reset command could not start: {error}") from error
    return {"ok": True, "reset": True}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vphone-agent",
        description="Send deterministic local agent actions to vphone.sock.",
    )
    parser.add_argument("--socket", type=Path, help="path to vphone.sock")
    parser.add_argument(
        "--timeout", type=float, default=2.0, help="per-request timeout in seconds"
    )
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("ping", help="check that the host-control socket responds")

    tap = commands.add_parser("tap", help="inject one tap")
    tap.add_argument("--x", type=float, required=True)
    tap.add_argument("--y", type=float, required=True)
    _add_settle_options(tap)

    swipe = commands.add_parser("swipe", help="inject a swipe")
    for name in ("x1", "y1", "x2", "y2"):
        swipe.add_argument(f"--{name}", type=float, required=True)
    swipe.add_argument("--ms", type=int, default=300)
    _add_settle_options(swipe)

    key = commands.add_parser("key", help="inject a hardware key")
    key.add_argument("--name", required=True, choices=("home", "power", "volup", "voldown"))
    _add_settle_options(key)

    type_command = commands.add_parser("type", help="type text through the guest clipboard")
    type_command.add_argument("--text", required=True)
    _add_settle_options(type_command)

    screenshot = commands.add_parser("screenshot", help="capture a screenshot")
    screenshot.add_argument("--path")
    screenshot.add_argument("--delay", type=int, default=500)

    wait_ready = commands.add_parser("wait-ready", help="poll ping until the VM is ready")
    wait_ready.add_argument("--deadline", type=float, default=30.0)
    wait_ready.add_argument("--interval", type=float, default=0.25)

    reset = commands.add_parser("reset", help="run an explicit VM reset hook")
    reset.add_argument(
        "--reset-command",
        nargs="+",
        required=True,
        metavar="ARG",
        help="executable and arguments; never interpreted by a shell",
    )
    return parser


def _add_settle_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--delay", type=int, default=500)
    parser.add_argument(
        "--no-screen", dest="screen", action="store_false", help="omit screenshot response"
    )
    parser.set_defaults(screen=True)


def _require_socket(args: argparse.Namespace) -> Path:
    if args.socket is None:
        raise ValidationError("--socket is required for this command")
    return args.socket


def _request_from_args(args: argparse.Namespace) -> dict[str, Any]:
    command = args.command
    if command == "ping":
        return {"t": "ping"}
    if command == "tap":
        return {"t": "tap", "x": args.x, "y": args.y, "delay": args.delay, "screen": args.screen}
    if command == "swipe":
        return {
            "t": "swipe",
            "x1": args.x1,
            "y1": args.y1,
            "x2": args.x2,
            "y2": args.y2,
            "ms": args.ms,
            "delay": args.delay,
            "screen": args.screen,
        }
    if command == "key":
        return {"t": "key", "name": args.name, "delay": args.delay, "screen": args.screen}
    if command == "type":
        return {"t": "type", "text": args.text, "delay": args.delay, "screen": args.screen}
    return {"t": "screenshot", **({"path": args.path} if args.path is not None else {}), "delay": args.delay}


def _wait_ready(args: argparse.Namespace) -> dict[str, Any]:
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        raise ValidationError("timeout must be a positive finite number")
    if not math.isfinite(args.deadline) or args.deadline <= 0:
        raise ValidationError("deadline must be a positive finite number")
    if not math.isfinite(args.interval) or args.interval < 0:
        raise ValidationError("interval must be a non-negative finite number")
    socket_path = _require_socket(args)
    deadline = time.monotonic() + args.deadline
    last_error: Exception | None = None
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            detail = f": {last_error}" if last_error else ""
            raise TransportError(f"wait-ready timed out{detail}")
        try:
            response = send_request(
                socket_path, {"t": "ping"}, min(args.timeout, remaining)
            )
            if response.get("ok"):
                return response
            last_error = TransportError(response.get("error", "ping not ready"))
        except (TransportError, ValidationError) as error:
            last_error = error
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            detail = f": {last_error}" if last_error else ""
            raise TransportError(f"wait-ready timed out{detail}")
        time.sleep(min(args.interval, remaining))


def _emit_error(error: Exception) -> int:
    print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
    if isinstance(error, ValidationError):
        return EXIT_VALIDATION
    if isinstance(error, TransportError):
        return EXIT_TRANSPORT
    return EXIT_HOOK


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "reset":
            response = run_reset(args.reset_command)
        elif args.command == "wait-ready":
            response = _wait_ready(args)
        else:
            response = send_request(
                _require_socket(args), _request_from_args(args), args.timeout
            )
        print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
        return 0
    except (ValidationError, TransportError) as error:
        return _emit_error(error)


if __name__ == "__main__":
    raise SystemExit(main())
