"""Local, stdlib-only client for the vphone host-control socket."""

from .client import (
    MAX_RESPONSE_BYTES,
    MAX_TEXT_BYTES,
    ValidationError,
    TransportError,
    send_request,
    validate_request,
)

__all__ = [
    "MAX_RESPONSE_BYTES",
    "MAX_TEXT_BYTES",
    "ValidationError",
    "TransportError",
    "send_request",
    "validate_request",
]
