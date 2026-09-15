# Local AI Agent Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local, deterministic AI-agent adapter around `vphone.sock` while hardening the socket, archive extraction, package setup, Makefile inputs, and signing-credential boundary.

**Architecture:** A stdlib-only Python CLI (`tools/vphone-agent`) owns transport, validation, lifecycle hooks, and machine-readable output. The existing Swift host-control socket remains the VM command backend, but gains shared validation, explicit `0600` permissions, and bounded client reads. Firmware/jailbreak code remains unchanged except for the security gates required by the approved spec.

**Tech Stack:** Python 3 standard library, Swift 6/Testing, Objective-C libarchive, Make/zsh, Unix domain sockets.

**Spec:** `docs/superpowers/specs/2026-09-15-agent-harness-design.md`

## Global Constraints

- The first release is macOS-local and Unix-socket based.
- The Python adapter has no third-party dependencies.
- No signing private key may remain tracked or required from the repository.
- Numeric socket inputs are bounded before any `UInt64` conversion.
- Unauthenticated guest packages require explicit local opt-in.
- Real-VM smoke tests remain opt-in; default tests do not boot a VM.

---

### Task 1: Python transport, validation, and CLI

**Files:**
- Create: `tools/vphone_agent/__init__.py`
- Create: `tools/vphone_agent/client.py`
- Create: `tools/vphone_agent/cli.py`
- Create: `tools/vphone-agent` (executable shim)
- Create: `tests/test_vphone_agent.py`

**Interfaces:**
- `validate_request(request: dict) -> dict` returns a normalized request or raises `ValidationError`.
- `send_request(socket_path: pathlib.Path, request: dict, timeout: float) -> dict` returns the parsed response or raises `TransportError`.
- CLI emits one JSON object on stdout for protocol responses and exits non-zero for validation/transport failures.

- [ ] **Step 1: Write failing validation and transport tests**

```python
def test_rejects_negative_delay():
    with self.assertRaises(ValidationError):
        validate_request({"t": "tap", "x": 1, "y": 2, "delay": -1})

def test_fake_socket_round_trip(tmp_path):
    server = FakeSocketServer(tmp_path, {"ok": True})
    with server:
        assert send_request(server.path, {"t": "ping"}, timeout=0.5) == {"ok": True}

def test_socket_timeout_is_bounded(tmp_path):
    server = HangingSocketServer(tmp_path)
    with server, self.assertRaisesRegex(TransportError, "timed out"):
        send_request(server.path, {"t": "ping"}, timeout=0.05)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v`

Expected: collection/import failure because `tools.vphone_agent` and its validation/transport functions do not exist yet.

- [ ] **Step 3: Implement the minimal client and CLI**

Use `socket.AF_UNIX`, `SOCK_STREAM`, `settimeout(timeout)`, a 64 KiB maximum response, and `json.loads` after reading one newline-delimited response. Validate coordinates as finite numbers, `delay` in `0...5000`, swipe `ms` in `1...10000`, text at most 64 KiB, and keys against `home/power/volup/voldown`. The CLI maps `tap`, `swipe`, `key`, `type`, and `screenshot` arguments to the existing request keys and prints normalized JSON.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v`

Expected: all adapter tests pass without a VM.

- [ ] **Step 5: Add lifecycle hook behavior and CLI integration tests**

`wait-ready` polls `ping` until the deadline; `reset` executes only an explicit `--reset-command` using `subprocess.run(..., shell=False)`. Add tests for successful polling, deadline failure, and reset argument handling.

- [ ] **Step 6: Run the complete adapter suite**

Run: `python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v`

Expected: all tests pass.

- [ ] **Step 7: Commit the adapter**

```bash
git add tools/vphone_agent tools/vphone-agent tests/test_vphone_agent.py
git commit -m "feat: add local vphone agent adapter"
```

### Task 2: Harden the Swift host-control socket

**Files:**
- Modify: `sources/vphone-cli/VPhoneHostControl.swift`
- Create: `sources/VPhoneCore/VPhoneHostControlLimits.swift`
- Create: `tests/VPhoneCoreTests/HostControlValidationTests.swift`

**Interfaces:**
- `VPhoneHostControlLimits` defines the exact delay, swipe duration, text, and request-size bounds.
- `VPhoneHostControlLimits.validateInteger(_ value: Int?, range: ClosedRange<Int>, name: String) throws -> Int` rejects malformed values before conversion.

- [ ] **Step 1: Write failing tests for limits and normalization**

```swift
@Test func rejectsNegativeDelay() {
    #expect(throws: VPhoneHostControlValidationError.self) {
        try VPhoneHostControlLimits.delay(-1)
    }
}

@Test func acceptsDefaultDelay() throws {
    #expect(try VPhoneHostControlLimits.delay(500) == 500)
}
```

- [ ] **Step 2: Run the focused Swift tests and verify RED**

Run: `swift test --filter HostControlValidationTests`

Expected: compile failure because the validation type does not exist.

- [ ] **Step 3: Implement validation and socket safety**

Add explicit `chmod(socketPath, 0o600)` after `bind`, apply `SO_RCVTIMEO` to accepted clients, reject requests above 64 KiB, validate `delay`/`ms` before all `UInt64` conversions, and close a client that sends no newline before the deadline. Keep the same-user Unix-socket threat model and do not add TCP.

- [ ] **Step 4: Run focused tests and a compile check**

Run: `swift test --filter HostControlValidationTests`

Expected: focused tests pass and the executable target compiles.

- [ ] **Step 5: Commit the host hardening**

```bash
git add sources/vphone-cli/VPhoneHostControl.swift tests
git commit -m "fix: bound host control socket inputs"
```

### Task 3: Remove repository signing secret and make IPA signing explicit

**Files:**
- Delete: `scripts/vphoned/signcert.p12`
- Modify: `Makefile` signing/resource copy rules
- Modify: `sources/vphone-cli/VPhoneControl.swift` or its signing helper to accept an explicit external certificate path and fail closed when absent.
- Modify: `.gitignore` to ignore local signing material.

**Interfaces:**
- `VPHONE_SIGNCERT=/absolute/path/to/cert.p12` is the only supported credential input.
- Missing `VPHONE_SIGNCERT` produces a clear error; no bundled fallback exists.

- [ ] **Step 1: Add a failing test/check for missing external signing material**

Add a shell test that runs the signing-preparation target with no `VPHONE_SIGNCERT` and asserts a non-zero exit plus an error containing `VPHONE_SIGNCERT`.

- [ ] **Step 2: Run the check and verify RED**

Run: `bash tests/test_signing_config.sh`

Expected: failure because the old bundled certificate path is still accepted.

- [ ] **Step 3: Remove the bundled credential and wire the external path**

Delete the file, remove resource-copy references, use the environment path only, validate it is a regular file with restrictive permissions, and add the local path pattern to `.gitignore`.

- [ ] **Step 4: Purge the credential from this fork’s Git history**

Use `git filter-repo --path scripts/vphoned/signcert.p12 --invert-paths` if available; otherwise use an equivalent history rewrite limited to that exact path. Verify with `git log --all -- scripts/vphoned/signcert.p12` and `git rev-list --objects --all | rg 'signcert\.p12'` that no reachable commit contains the path.

- [ ] **Step 5: Run the signing check and verify GREEN**

Run: `bash tests/test_signing_config.sh`

Expected: missing credential fails closed and a supplied temporary fixture is accepted without adding it to Git.

- [ ] **Step 6: Commit the credential boundary**

```bash
git add -A Makefile sources tests .gitignore
git commit -m "security: remove bundled signing credential"
```

### Task 4: Harden archive extraction and package installation

**Files:**
- Modify: `scripts/vphoned/unarchive.m`
- Modify: `scripts/vphone_jb_setup.sh`
- Modify: `scripts/fetch_debs.sh`
- Modify: `scripts/cfw_install_jb.sh` only where it passes package verification state.
- Create: `tests/test_package_security.sh`

**Interfaces:**
- `VPHONE_ALLOW_INSECURE_PACKAGES=1` is the explicit local opt-in for legacy unsigned apt/deb flows.
- Default setup exits before unauthenticated install rather than silently continuing.

- [ ] **Step 1: Write failing static security checks**

```bash
grep -q 'ARCHIVE_EXTRACT_SECURE_SYMLINKS' scripts/vphoned/unarchive.m
! grep -q 'AllowUnauthenticated=true' scripts/vphone_jb_setup.sh
grep -q 'VPHONE_ALLOW_INSECURE_PACKAGES' scripts/vphone_jb_setup.sh
```

- [ ] **Step 2: Run the checks and verify RED**

Run: `bash tests/test_package_security.sh`

Expected: failure because symlink protection is absent and unsigned apt is unconditional.

- [ ] **Step 3: Implement fail-closed package and archive behavior**

Add `ARCHIVE_EXTRACT_SECURE_SYMLINKS`; reject unsafe link entries if libarchive reports them. Gate legacy unsigned apt/dpkg commands behind `VPHONE_ALLOW_INSECURE_PACKAGES=1`, print an explicit warning when enabled, and make `fetch_debs.sh` require a hash manifest for downloaded packages unless the same opt-in is present.

- [ ] **Step 4: Run security checks and shell syntax checks**

Run: `bash tests/test_package_security.sh; bash -n scripts/vphone_jb_setup.sh scripts/fetch_debs.sh scripts/cfw_install_jb.sh`

Expected: all checks pass.

- [ ] **Step 5: Commit archive/package hardening**

```bash
git add scripts tests/test_package_security.sh
git commit -m "security: harden archive and guest package setup"
```

### Task 5: Remove Makefile shell interpolation and document the harness

**Files:**
- Modify: `Makefile`
- Modify: `AGENTS.md` or the main README with local agent usage and explicit limitations.
- Create: `docs/agent-harness.md`

**Interfaces:**
- Make recipes export `SUDO_PASSWORD`, `INTERACTIVE`, `NO_BINPACK`, `NO_VPHONED`, `SPOOF_BUILD`, and `VARIANT` through the environment rather than embedding their values in shell source.
- The adapter usage documentation includes a real command example and a fake-server test command.

- [ ] **Step 1: Add a regression test for Makefile recipe safety**

Add a shell test that runs `make -n setup_tools VARIANT='$(touch /tmp/vphone-agent-injection)'` and asserts the generated recipe contains no interpolated command substitution. Use a temporary directory under `mktemp -d`, never a broad path.

- [ ] **Step 2: Run the regression test and verify RED**

Run: `bash tests/test_makefile_safety.sh`

Expected: failure because the current recipe embeds `VARIANT` directly.

- [ ] **Step 3: Export variables and quote script paths**

Use Make `export` declarations and recipes such as `VARIANT=...` only through the environment; keep the executable invocation as `zsh "$(SCRIPTS)/setup_tools.sh"`. Do not put secrets in command-line arguments.

- [ ] **Step 4: Run Makefile safety and adapter docs checks**

Run: `bash tests/test_makefile_safety.sh; python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v`

Expected: all checks pass.

- [ ] **Step 5: Commit the Makefile/docs changes**

```bash
git add Makefile AGENTS.md docs/agent-harness.md tests/test_makefile_safety.sh
git commit -m "docs: expose local agent harness workflow"
```

### Task 6: Full verification and fork handoff

**Files:**
- Modify: none unless verification reveals a regression.

- [ ] **Step 1: Run adapter and shell checks**

Run: `python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v; bash tests/test_package_security.sh; bash tests/test_makefile_safety.sh; bash -n scripts/vphone_jb_setup.sh scripts/fetch_debs.sh scripts/cfw_install_jb.sh`

- [ ] **Step 2: Run Swift tests**

Run: `swift test`

Record fixture-dependent failures separately from failures introduced by these changes; do not claim the suite is green if the known firmware fixtures are absent.

- [ ] **Step 3: Inspect the final diff and secret reachability**

Run: `git status --short; git diff --check; git log --all -- scripts/vphoned/signcert.p12; git rev-list --objects --all | rg 'signcert\\.p12'`

Expected: no whitespace errors, no tracked signing path, and only intended files changed.

- [ ] **Step 4: Push the sanitized branch to the fork**

```bash
git push --force-with-lease origin main
```

Use force-with-lease only after verifying the fork has no user commits beyond the fork baseline and the signing path is absent from all reachable history.

- [ ] **Step 5: Report the fork URL, local path, commits, test evidence, and remaining VM/firmware gates**
