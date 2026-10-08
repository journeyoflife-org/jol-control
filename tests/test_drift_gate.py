#!/usr/bin/env python3
"""Self-tests for scripts/drift_detect.py — the allow-list vs live-organization gate.

Fixture provenance (AGENTS.md §7: a gate that reads tool output must be proven
against real captured output of that tool):

  live_host_user_token.json   `gh repo list journeyoflife-org --limit 500
                               --json name,visibility` captured on this host with an
                               operator token: 41 rows, one of them PRIVATE (jol-dr).
  ci_github_actions_token.json the same fleet as seen by `secrets.GITHUB_TOKEN` in the
                               scheduled Compliance Scan run 37107745958: 39 rows, no
                               private repository at all, jol-dr simply not there. That
                               run reported `in_defined_not_github: ["jol-dr"]` and
                               failed. Nothing was missing — the token could not see it.

The rest are synthesised, including the two the old script got wrong by returning 0:
a failing `gh` call and an empty organization listing.

Run directly (no pytest required):
    python3 tests/test_drift_gate.py
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE = REPO_ROOT / "scripts" / "drift_detect.py"
FIXTURES = REPO_ROOT / "tests" / "fixtures" / "drift_detect"
REAL_ALLOW_LIST = REPO_ROOT / "repos"

EXIT_CLEAN = 0
EXIT_DRIFT = 1
EXIT_UNEVALUATED = 2

FAILURES: list[str] = []

STUB = r"""#!/usr/bin/env bash
# Replays captured gh output. Behaviour chosen by env vars set per test.
# Exact-match membership only: a glob like ",${name}," against an empty name matches
# every word containing two commas, which is how the first version of this stub made
# every probe answer "exists".
contains() {  # contains <needle> <csv>
  local IFS=',' item
  [ -n "${2:-}" ] || return 1
  for item in $2; do [ "$item" = "$1" ] && return 0; done
  return 1
}

if [ "$1" = "repo" ] && [ "$2" = "list" ]; then
  rc="${STUB_LIST_RC:-0}"
  if [ "$rc" != "0" ]; then
    echo "${STUB_LIST_STDERR:-gh: repository not found (HTTP 404)}" >&2
    exit "$rc"
  fi
  cat "${STUB_LIST_FILE}"
  exit 0
fi
if [ "$1" = "api" ]; then
  path="$2"                 # gh api takes the path as ONE argument: repos/<org>/<name>
  name="${path##*/}"
  if [ -z "$name" ] || [ "$name" = "$path" ]; then
    echo "stub gh: could not read a repository name from '$path'" >&2
    exit 125
  fi
  if contains "$name" "${STUB_API_EXISTS:-}"; then
    echo "{\"name\":\"${name}\",\"private\":true}"
    exit 0
  fi
  if contains "$name" "${STUB_API_UNVERIFIABLE:-}"; then
    echo "read tcp: connection reset by peer" >&2
    exit 1
  fi
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
echo "stub gh: unhandled arguments: $*" >&2
exit 125
"""


def write_allow_list(names: dict[str, str]) -> str:
    """A minimal repos/ directory: {name: visibility}."""
    tmp = tempfile.mkdtemp(prefix="allowlist-")
    for name, visibility in names.items():
        Path(tmp, f"{name}.yml").write_text(f"name: {name}\nvisibility: {visibility}\n")
    return tmp


def run_gate(listing: object, repos_dir: str, *, list_rc: int = 0, list_stderr: str = "",
             api_exists: list[str] | None = None,
             api_unverifiable: list[str] | None = None) -> tuple[int, str]:
    stub_dir = Path(tempfile.mkdtemp(prefix="stub-"))
    stub = stub_dir / "gh"
    stub.write_text(STUB)
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
    if isinstance(listing, Path):
        list_file = listing
    else:
        list_file = stub_dir / "listing.json"
        list_file.write_text(json.dumps(listing))
    env = {
        **os.environ,
        "DRIFT_GH": str(stub),
        "STUB_LIST_FILE": str(list_file),
        "STUB_LIST_RC": str(list_rc),
        "STUB_LIST_STDERR": list_stderr,
        "STUB_API_EXISTS": ",".join(api_exists or []),
        "STUB_API_UNVERIFIABLE": ",".join(api_unverifiable or []),
    }
    proc = subprocess.run(
        [sys.executable, str(GATE), "--org", "example-org", "--repos-dir", repos_dir],
        capture_output=True, text=True, env=env, check=False,
    )
    return proc.returncode, proc.stdout + proc.stderr


def expect(label: str, want: int, got: int, output: str, needle: str = "") -> None:
    if got != want:
        FAILURES.append(f"{label}: expected exit {want}, got {got}")
        print(f"  ✗ {label}: exit {got} (want {want})\n{output}")
        return
    if needle and needle not in output:
        FAILURES.append(f"{label}: expected output to contain {needle!r}")
        print(f"  ✗ {label}: missing {needle!r}\n{output}")
        return
    print(f"  ✓ {label}: exit {got}" + (f", reported {needle!r}" if needle else ""))


def test_full_visibility_clean() -> None:
    """The real allow-list against the real capture an operator token can make."""
    code, out = run_gate(FIXTURES / "live_host_user_token.json", str(REAL_ALLOW_LIST))
    expect("allow-list agrees with a fully visible org", EXIT_CLEAN, code, out, "NO DRIFT")


def test_ci_blindness_is_unevaluated_not_drift() -> None:
    code, out = run_gate(FIXTURES / "ci_github_actions_token.json", str(REAL_ALLOW_LIST))
    expect("S14: private-blind CI token must NOT be reported as drift", EXIT_UNEVALUATED,
           code, out, "cannot enumerate private repos")


def test_gh_failure_is_unevaluated() -> None:
    real_error = (FIXTURES / "gh_failure.txt").read_text().strip()
    code, out = run_gate([], str(REAL_ALLOW_LIST), list_rc=1, list_stderr=real_error)
    expect("failing gh call fails closed, not green", EXIT_UNEVALUATED, code, out, "UNEVALUATED")
    expect("the gh error is surfaced, not swallowed", EXIT_UNEVALUATED, code, out, real_error[:20])


def test_empty_listing_is_unevaluated() -> None:
    code, out = run_gate([], str(REAL_ALLOW_LIST))
    expect("empty org listing is a token artefact, not a pass", EXIT_UNEVALUATED, code, out,
           "EMPTY repository list")


def test_no_definitions_is_unevaluated() -> None:
    code, out = run_gate(FIXTURES / "live_host_user_token.json", write_allow_list({}))
    expect("unreadable/empty allow-list cannot pass", EXIT_UNEVALUATED, code, out,
           "no repository definitions")


def test_genuine_absence_is_drift() -> None:
    repos = write_allow_list({"alpha": "public", "beta": "public"})
    code, out = run_gate([{"name": "alpha", "visibility": "PUBLIC"}], repos)
    expect("declared repo that a direct lookup also says is absent", EXIT_DRIFT, code, out,
           "DRIFT: beta")


def test_undeclared_live_repo_is_drift() -> None:
    repos = write_allow_list({"alpha": "public"})
    rows = [{"name": "alpha", "visibility": "PUBLIC"}, {"name": "rogue", "visibility": "PUBLIC"}]
    code, out = run_gate(rows, repos)
    expect("live repo missing from the allow-list", EXIT_DRIFT, code, out, "DRIFT: rogue")


def test_probe_contradicts_listing() -> None:
    repos = write_allow_list({"alpha": "public", "beta": "public"})
    code, out = run_gate([{"name": "alpha", "visibility": "PUBLIC"}], repos,
                         api_exists=["beta"])
    expect("listing omitted a repo that answers lookups", EXIT_UNEVALUATED, code, out,
           "listing is incomplete")


def test_probe_transport_error() -> None:
    repos = write_allow_list({"alpha": "public", "beta": "public"})
    code, out = run_gate([{"name": "alpha", "visibility": "PUBLIC"}], repos,
                         api_unverifiable=["beta"])
    expect("lookup that errors rather than answers", EXIT_UNEVALUATED, code, out,
           "could not confirm")


def test_private_repo_visible_to_token() -> None:
    repos = write_allow_list({"alpha": "public", "secret": "private"})
    rows = [{"name": "alpha", "visibility": "PUBLIC"},
            {"name": "secret", "visibility": "PRIVATE"}]
    code, out = run_gate(rows, repos)
    expect("a token that can see private repos still passes", EXIT_CLEAN, code, out, "NO DRIFT")


def test_private_absence_still_drift_when_visibility_proven() -> None:
    repos = write_allow_list({"alpha": "public", "secret": "private", "other": "private"})
    rows = [{"name": "alpha", "visibility": "PUBLIC"},
            {"name": "other", "visibility": "PRIVATE"}]
    code, out = run_gate(rows, repos)
    expect("private repo genuinely absent, while other private repos are visible",
           EXIT_DRIFT, code, out, "DRIFT: secret")


def main() -> int:
    if not GATE.is_file():
        print(f"FAILED — gate not found: {GATE}", file=sys.stderr)
        return 1
    if not FIXTURES.is_dir():
        print(f"FAILED — fixtures not found: {FIXTURES}", file=sys.stderr)
        return 1

    tests = [value for name, value in sorted(globals().items())
             if name.startswith("test_")]
    for test in tests:
        print(f"{test.__name__}:")
        test()

    if FAILURES:
        print(f"\nFAILED — {len(FAILURES)} assertion(s) across {len(tests)} test(s):",
              file=sys.stderr)
        for failure in FAILURES:
            print(f"  ✗ {failure}", file=sys.stderr)
        return 1

    print(f"\nPASSED — {len(tests)} drift-gate tests, 0 failures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
