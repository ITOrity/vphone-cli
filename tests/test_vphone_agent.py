import json
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock


from tools.vphone_agent.client import (
    ValidationError,
    TransportError,
    send_request,
    validate_request,
)


class UnixSocketServer:
    def __init__(self, root, handler, connections=1):
        self.path = Path(root) / "vphone.sock"
        self.handler = handler
        self.connections = connections
        self._server = None
        self._thread = None
        self.error = None

    def __enter__(self):
        self._server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server.bind(str(self.path))
        self._server.listen(1)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()
        return self

    def _serve(self):
        try:
            for _ in range(self.connections):
                connection, _ = self._server.accept()
                with connection:
                    self.handler(connection)
        except Exception as error:  # pragma: no cover - surfaced by __exit__
            self.error = error

    def __exit__(self, exc_type, exc, tb):
        if self._server is not None:
            self._server.close()
        if self._thread is not None:
            self._thread.join(timeout=1)
        if self.error is not None and exc_type is None:
            raise self.error


class FakeSocketServer(UnixSocketServer):
    def __init__(self, root, response):
        def handler(connection):
            request = read_json_line(connection)
            self.request = request
            connection.sendall((json.dumps(response) + "\n").encode())

        self.request = None
        super().__init__(root, handler)


class HangingSocketServer(UnixSocketServer):
    def __init__(self, root):
        def handler(connection):
            connection.recv(1)
            time.sleep(1)

        super().__init__(root, handler)


def read_json_line(connection):
    data = bytearray()
    while b"\n" not in data:
        chunk = connection.recv(4096)
        if not chunk:
            break
        data.extend(chunk)
    return json.loads(bytes(data).split(b"\n", 1)[0])


class ValidationTests(unittest.TestCase):
    def test_rejects_negative_delay(self):
        with self.assertRaises(ValidationError):
            validate_request({"t": "tap", "x": 1, "y": 2, "delay": -1})

    def test_rejects_non_finite_coordinate(self):
        with self.assertRaises(ValidationError):
            validate_request({"t": "tap", "x": float("nan"), "y": 2})

    def test_normalizes_tap_defaults_and_coordinates(self):
        self.assertEqual(
            validate_request({"t": "tap", "x": 1, "y": 2}),
            {"t": "tap", "x": 1.0, "y": 2.0, "delay": 500, "screen": True},
        )

    def test_rejects_oversized_text(self):
        with self.assertRaises(ValidationError):
            validate_request({"t": "type", "text": "x" * (64 * 1024 + 1)})

    def test_rejects_unknown_key(self):
        with self.assertRaises(ValidationError):
            validate_request({"t": "key", "name": "menu"})

    def test_normalizes_swipe_duration(self):
        request = validate_request(
            {"t": "swipe", "x1": 1, "y1": 2, "x2": 3, "y2": 4, "ms": 20}
        )
        self.assertEqual(
            request,
            {
                "t": "swipe",
                "x1": 1.0,
                "y1": 2.0,
                "x2": 3.0,
                "y2": 4.0,
                "ms": 20,
                "delay": 500,
                "screen": True,
            },
        )


class TransportTests(unittest.TestCase):
    def test_fake_socket_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            server = FakeSocketServer(directory, {"ok": True})
            with server:
                self.assertEqual(
                    send_request(server.path, {"t": "ping"}, timeout=0.5),
                    {"ok": True},
                )
            self.assertEqual(server.request, {"t": "ping"})

    def test_socket_timeout_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            server = HangingSocketServer(directory)
            with server, self.assertRaisesRegex(TransportError, "timed out"):
                send_request(server.path, {"t": "ping"}, timeout=0.05)

    def test_rejects_oversized_response(self):
        def handler(connection):
            connection.recv(4096)
            connection.sendall(("{" + "x" * (64 * 1024) + "}\n").encode())

        with tempfile.TemporaryDirectory() as directory:
            server = UnixSocketServer(directory, handler)
            with server, self.assertRaisesRegex(TransportError, "64 KiB"):
                send_request(server.path, {"t": "ping"}, timeout=0.5)


class LifecycleTests(unittest.TestCase):
    def test_wait_ready_polls_until_ping_succeeds(self):
        responses = iter([{"ok": False}, {"ok": True, "ready": True}])

        def handler(connection):
            request = read_json_line(connection)
            self.assertEqual(request, {"t": "ping"})
            connection.sendall((json.dumps(next(responses)) + "\n").encode())

        from tools.vphone_agent import cli

        with tempfile.TemporaryDirectory() as directory:
            server = UnixSocketServer(directory, handler, connections=2)
            with server:
                output = StringIO()
                with redirect_stdout(output):
                    exit_code = cli.main(
                        [
                            "--socket",
                            str(server.path),
                            "wait-ready",
                            "--deadline",
                            "1",
                            "--interval",
                            "0",
                        ]
                    )
            self.assertEqual(exit_code, 0)
            self.assertEqual(json.loads(output.getvalue()), {"ok": True, "ready": True})

    def test_wait_ready_returns_nonzero_after_deadline(self):
        def handler(connection):
            read_json_line(connection)
            connection.sendall(b'{"ok":false}\n')

        from tools.vphone_agent import cli

        with tempfile.TemporaryDirectory() as directory:
            server = UnixSocketServer(directory, handler, connections=2)
            with server:
                stderr = StringIO()
                with mock.patch("sys.stderr", stderr):
                    exit_code = cli.main(
                        [
                            "--socket",
                            str(server.path),
                            "wait-ready",
                            "--deadline",
                            "0.01",
                            "--interval",
                            "0",
                        ]
                    )
            self.assertEqual(exit_code, cli.EXIT_TRANSPORT)
            self.assertIn("wait-ready timed out", stderr.getvalue())

    def test_reset_uses_argument_vector_without_shell(self):
        from tools.vphone_agent.cli import run_reset

        with mock.patch("tools.vphone_agent.cli.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess(["reset-vm"], 0)
            response = run_reset(["reset-vm", "--snapshot", "clean"])

        self.assertEqual(response, {"ok": True, "reset": True})
        run.assert_called_once_with(
            ["reset-vm", "--snapshot", "clean"],
            check=True,
            capture_output=True,
            text=True,
            shell=False,
        )


if __name__ == "__main__":
    unittest.main()
