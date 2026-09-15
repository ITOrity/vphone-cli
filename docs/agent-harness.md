# Local AI Agent Harness

The repository includes a small, local-only adapter for agents that need to
drive a booted vphone VM. It talks to the existing Unix socket and never opens
a TCP listener.

## Install and run

The adapter uses only the Python standard library:

```sh
python3 -m unittest discover -s tests -p 'test_vphone_agent.py' -v
tools/vphone-agent --socket /absolute/path/to/vphone.sock wait-ready
tools/vphone-agent --socket /absolute/path/to/vphone.sock tap --x 645 --y 1398
tools/vphone-agent --socket /absolute/path/to/vphone.sock type --text 'hello' --no-screen
tools/vphone-agent --socket /absolute/path/to/vphone.sock screenshot --path /tmp/vphone-shot.png
```

Every successful operation prints one JSON object to stdout. Validation and
transport failures print a JSON error to stderr and return a non-zero exit
code. `reset` is deliberately an explicit caller-owned command:

```sh
tools/vphone-agent reset --reset-command ./scripts/reset_test_vm.sh --snapshot clean
```

The reset command is passed as an argument vector (`shell=False`); it is never
interpreted by a shell.

## Real VM boundary

The VM must already be booted with host control enabled. `wait-ready` polls the
host `ping` command until its deadline; it does not boot, restore, or patch
firmware. Snapshot/reset orchestration belongs to the caller so a test runner
can choose its own clean-state strategy.

For an agent test suite, keep action and assertion layers separate:

```text
agent action -> vphone-agent -> vphone.sock -> VM
                                      |
                           screenshot/log assertion
```

The adapter validates finite coordinates, bounded delay/duration values, text
size, supported hardware keys, request size, response size, and socket
timeouts. The Swift host applies the same limits before scheduling input.

## Signing and package setup

Signing material is not bundled. Firmware/guest signing commands require
`VPHONE_SIGNCERT` to point to an owner-only (`0400`, `0600`, or `0700`) external
file:

```sh
chmod 600 /path/to/local/signcert.p12
VPHONE_SIGNCERT=/path/to/local/signcert.p12 make vphoned
```

The `scripts/resources` storage submodule is pinned to the sanitized fork and
its `cfw_input` archive is checked to contain no signing credential.

Guest Sileo/apt/extra-deb installation is disabled unless the caller
explicitly sets `VPHONE_ALLOW_INSECURE_PACKAGES=1`. Downloaded `.deb` files are
otherwise accepted only with a SHA-256 manifest next to `debs.list` or at the
path in `VPHONE_DEBS_HASH_MANIFEST`.

These are research-VM controls, not a claim that jailbreak firmware is a
production-secure iOS environment.
