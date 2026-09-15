"""Validation and transport for the newline-delimited vphone protocol."""

from __future__ import annotations

import json
import math
import socket
from pathlib import Path
from typing import Any, Mapping


MAX_REQUEST_BYTES = 64 * 1024
MAX_RESPONSE_BYTES = 64 * 1024
MAX_TEXT_BYTES = 64 * 1024
MAX_DELAY_MS = 5_000
MAX_SWIPE_MS = 10_000
DEFAULT_DELAY_MS = 500
DEFAULT_SWIPE_MS = 300
SUPPORTED_KEYS = frozenset({"home", "power", "volup", "voldown"})
SUPPORTED_COMMANDS = frozenset(
    {"ping", "tap", "swipe", "key", "type", "screenshot"}
)


class ValidationError(ValueError):
    """Raised when an agent request is malformed or outside safe limits."""


class TransportError(RuntimeError):
    """Raised when a socket request cannot complete or violates the protocol."""


def _require_mapping(request: Mapping[str, Any] | dict[str, Any]) -> Mapping[str, Any]:
    if not isinstance(request, Mapping):
        raise ValidationError("request must be a JSON object")
    return request


def _command(request: Mapping[str, Any]) -> str:
    command = request.get("t")
    if not isinstance(command, str) or command not in SUPPORTED_COMMANDS:
        raise ValidationError("unknown or missing command 't'")
    return command


def _finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"{name} must be a finite number")
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError) as error:
        raise ValidationError(f"{name} must be a finite number") from error
    if not math.isfinite(number):
        raise ValidationError(f"{name} must be a finite number")
    return number


def _bounded_integer(
    value: Any, name: str, minimum: int, maximum: int, default: int
) -> int:
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(f"{name} must be an integer")
    if not minimum <= value <= maximum:
        raise ValidationError(f"{name} must be between {minimum} and {maximum}")
    return value


def _screen_flag(request: Mapping[str, Any]) -> bool:
    screen = request.get("screen", True)
    if not isinstance(screen, bool):
        raise ValidationError("screen must be a boolean")
    return screen


def _normalize_coordinates(request: Mapping[str, Any], names: tuple[str, ...]) -> dict[str, float]:
    return {name: _finite_number(request.get(name), name) for name in names}


def validate_request(request: dict[str, Any]) -> dict[str, Any]:
    """Return a normalized copy of a supported host-control request.

    Coordinates are normalized to finite floats, bounded integer fields are
    normalized to integers, and the host's implicit screenshot/delay defaults
    are made explicit. No caller-owned mapping is mutated.
    """

    source = _require_mapping(request)
    command = _command(source)

    if command == "ping":
        return {"t": "ping"}

    if command == "tap":
        normalized: dict[str, Any] = {"t": command}
        normalized.update(_normalize_coordinates(source, ("x", "y")))
        normalized["delay"] = _bounded_integer(
            source.get("delay"), "delay", 0, MAX_DELAY_MS, DEFAULT_DELAY_MS
        )
        normalized["screen"] = _screen_flag(source)
        return normalized

    if command == "swipe":
        normalized = {"t": command}
        normalized.update(_normalize_coordinates(source, ("x1", "y1", "x2", "y2")))
        normalized["ms"] = _bounded_integer(
            source.get("ms"), "ms", 1, MAX_SWIPE_MS, DEFAULT_SWIPE_MS
        )
        normalized["delay"] = _bounded_integer(
            source.get("delay"), "delay", 0, MAX_DELAY_MS, DEFAULT_DELAY_MS
        )
        normalized["screen"] = _screen_flag(source)
        return normalized

    if command == "key":
        name = source.get("name")
        if not isinstance(name, str) or name not in SUPPORTED_KEYS:
            raise ValidationError("name must be one of home, power, volup, voldown")
        return {
            "t": command,
            "name": name,
            "delay": _bounded_integer(
                source.get("delay"), "delay", 0, MAX_DELAY_MS, DEFAULT_DELAY_MS
            ),
            "screen": _screen_flag(source),
        }

    if command == "type":
        text = source.get("text")
        if not isinstance(text, str):
            raise ValidationError("text must be a string")
        if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
            raise ValidationError("text exceeds 64 KiB")
        return {
            "t": command,
            "text": text,
            "delay": _bounded_integer(
                source.get("delay"), "delay", 0, MAX_DELAY_MS, DEFAULT_DELAY_MS
            ),
            "screen": _screen_flag(source),
        }

    # screenshot
    path = source.get("path")
    if path is not None and not isinstance(path, str):
        raise ValidationError("path must be a string")
    normalized = {"t": command, "delay": _bounded_integer(
        source.get("delay"), "delay", 0, MAX_DELAY_MS, DEFAULT_DELAY_MS
    )}
    if path is not None:
        if not path:
            raise ValidationError("path must not be empty")
        normalized["path"] = path
    return normalized


def _protocol_error(message: str) -> TransportError:
    return TransportError(f"protocol error: {message}")


def send_request(
    socket_path: Path | str, request: dict[str, Any], timeout: float
) -> dict[str, Any]:
    """Send one validated request and parse one newline-delimited response."""

    try:
        timeout_value = float(timeout)
    except (TypeError, ValueError) as error:
        raise TransportError("timeout must be a positive finite number") from error
    if not math.isfinite(timeout_value) or timeout_value <= 0:
        raise TransportError("timeout must be a positive finite number")

    normalized = validate_request(request)
    try:
        payload = json.dumps(
            normalized, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8") + b"\n"
    except (TypeError, ValueError) as error:
        raise ValidationError(f"request cannot be encoded: {error}") from error
    if len(payload) > MAX_REQUEST_BYTES:
        raise ValidationError("request exceeds 64 KiB")

    response_data = bytearray()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout_value)
            connection.connect(str(Path(socket_path)))
            connection.sendall(payload)
            while b"\n" not in response_data:
                chunk = connection.recv(min(4096, MAX_RESPONSE_BYTES + 1))
                if not chunk:
                    break
                response_data.extend(chunk)
                if b"\n" not in response_data and len(response_data) > MAX_RESPONSE_BYTES:
                    raise _protocol_error("response exceeds 64 KiB")
    except socket.timeout as error:
        raise TransportError("socket operation timed out") from error
    except TimeoutError as error:
        raise TransportError("socket operation timed out") from error
    except TransportError:
        raise
    except OSError as error:
        raise TransportError(f"socket error: {error}") from error

    if not response_data:
        raise _protocol_error("empty response")
    line = bytes(response_data).split(b"\n", 1)[0]
    if len(line) > MAX_RESPONSE_BYTES:
        raise _protocol_error("response exceeds 64 KiB")
    try:
        parsed = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise _protocol_error("response is not valid JSON") from error
    if not isinstance(parsed, dict) or not isinstance(parsed.get("ok"), bool):
        raise _protocol_error("response must be an object with boolean 'ok'")
    return parsed
