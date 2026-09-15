# Local AI Agent Harness Design

## Goal

Make the existing vphone host-control surface usable as a local, repeatable
test target for AI agents without turning the repository into a network
service or relying on a committed signing credential.

The first release is macOS-local and Unix-socket based. It does not promise a
portable CI simulator, App Store fidelity, or unattended firmware preparation.

## Recommended architecture

```text
AI agent
  -> tools/vphone-agent (Python CLI, stdlib only)
  -> vphone.sock (one JSON request/response per connection)
  -> VPhoneHostControl
  -> Virtual iPhone VM
```

The CLI is intentionally outside the Swift package so an agent can invoke it
without linking Virtualization.framework. It exposes stable, machine-readable
responses and translates transport/protocol failures into non-zero exit codes.

Supported operations in the first slice:

- `ping`
- `tap --x --y`
- `swipe --x1 --y1 --x2 --y2 --ms`
- `key --name`
- `type --text`
- `screenshot [--path]`
- `wait-ready`
- `reset` through an explicitly configured lifecycle command

`wait-ready` and `reset` are lifecycle hooks, not hidden VM boot behavior. The
CLI accepts a socket path and optional hook commands from the caller, so tests
can use a real VM or a fake server.

## Protocol and validation

- Requests remain one newline-delimited JSON object per connection.
- The CLI validates command names, required fields, finite coordinates, text
  size, and bounded delay/duration values before writing to the socket.
- Socket connect and read operations have finite timeouts.
- The host validates the same numeric limits before `UInt64` conversion and
  closes clients that exceed the request size or read deadline.
- Responses are normalized to `{ "ok": bool, ... }`; transport errors are
  emitted as structured stderr/exit-code failures.

The host socket is explicitly created with mode `0600`. The documented threat
model is same-user local automation; no remote TCP listener is added.

## Security changes

1. Remove the tracked `scripts/vphoned/signcert.p12` credential from the
   working tree and history. IPA signing must use an explicit external path or
   injected credential and must fail closed when absent.
2. Enable libarchive secure symlink extraction in addition to the existing
   `SECURE_NODOTDOT` check.
3. Make guest package installation fail closed by default. Any use of
   unauthenticated repositories/packages requires an explicit local opt-in
   environment variable and emits a warning.
4. Stop interpolating user-controlled Make variables into shell source;
   export values through the environment and quote script paths.

## Test strategy

- Add stdlib Python unit/contract tests for request validation, response
  parsing, timeout/error mapping, and a fake Unix-socket server.
- Add Swift tests for host-control input validation helpers where the existing
  package test target can exercise them without a running VM.
- Keep real-VM smoke tests opt-in and clearly separate from the default test
  command.
- Run `swift test` and the adapter test suite independently; missing firmware
  fixtures must be reported as fixture gaps, not treated as runtime success.

## Acceptance criteria

- An agent can execute `vphone-agent --socket <path> tap ...` and receive a
  deterministic JSON result or bounded error.
- Negative/oversized delay and swipe values never reach a crashing integer
  conversion.
- A client that sends no newline cannot block subsequent clients indefinitely.
- IPA extraction rejects symlink traversal.
- No signing private key is tracked or required from the repository.
- Make targets do not execute shell syntax supplied through exported values.
- All new tests pass without a booted VM.

## Out of scope

- Rewriting the firmware patcher or jailbreak research code.
- Adding a network API or multi-user authentication service.
- Downloading firmware or accepting new provider terms.
- Claiming that the resulting harness is a production-secure iOS emulator.
