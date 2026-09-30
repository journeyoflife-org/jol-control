#!/usr/bin/env python3
"""Self-tests for scripts/plan_gate.py — the destroy/replace STOP gate.

Fixtures under tests/fixtures/plan_gate/ are structurally faithful to real
``terraform show -json tfplan`` output captured on the control-plane host
(Terraform 1.9.0, integrations/github 6.x): same top-level keys, same
resource_change shape, and the real replace encoding — ``actions:
["delete", "create"]`` with ``replace_paths: [["repository"]]``.

A gate that parses tool output must be proven against real captured output of
that tool; these tests exist so the gate cannot go inert silently.

Run directly (no pytest required):
    python3 tests/test_plan_gate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE = REPO_ROOT / "scripts" / "plan_gate.py"
FIXTURES = REPO_ROOT / "tests" / "fixtures" / "plan_gate"

EXIT_SAFE = 0
EXIT_HALT = 1
EXIT_UNEVALUATED = 2

FAILURES: list[str] = []


def run_gate(*args: str) -> tuple[int, str]:
    """Invoke the gate as a subprocess and return (exit_code, combined_output)."""
    proc = subprocess.run(
        [sys.executable, str(GATE), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout + proc.stderr


def expect_exit(label: str, want: int, got: int, output: str) -> None:
    if got != want:
        FAILURES.append(f"{label}: expected exit {want}, got {got}")
        print(f"  ✗ {label}: exit {got} (want {want})\n{output}")
    else:
        print(f"  ✓ {label}: exit {got}")


def expect_text(label: str, needle: str, output: str) -> None:
    if needle not in output:
        FAILURES.append(f"{label}: expected output to contain {needle!r}")
        print(f"  ✗ {label}: missing {needle!r}\n{output}")
    else:
        print(f"  ✓ {label}: reported {needle!r}")


def test_clean_plan_passes() -> None:
    code, out = run_gate(str(FIXTURES / "clean.json"))
    expect_exit("clean plan (create/update/no-op only)", EXIT_SAFE, code, out)
    expect_text("clean plan", "PASSED", out)


def test_destroy_halts() -> None:
    code, out = run_gate(str(FIXTURES / "destroy.json"))
    expect_exit("plan with delete actions", EXIT_HALT, code, out)
    expect_text("destroy", "HALT", out)
    expect_text("destroy names the repository", 'github_repository.repo["jol-repo-template"]', out)
    expect_text("destroy names branch protection", 'github_branch_protection.standard["jol-repo-template"]', out)
    expect_text("destroy flags critical types", "CRITICAL", out)


def test_replace_halts() -> None:
    code, out = run_gate(str(FIXTURES / "replace.json"))
    expect_exit("plan with delete+create (replace)", EXIT_HALT, code, out)
    expect_text("replace", "replace", out)
    expect_text("replace reports forcing attribute", "forces replacement", out)


def test_allow_suppresses_named_resource() -> None:
    code, out = run_gate(
        str(FIXTURES / "destroy.json"),
        "--allow",
        'github_repository.repo["jol-repo-template"]',
        "--allow",
        'github_branch_protection.standard["jol-repo-template"]',
    )
    expect_exit("fully allow-listed destroy plan", EXIT_SAFE, code, out)
    expect_text("allow-list is visible in output", "permitted via --allow", out)


def test_allow_does_not_suppress_others() -> None:
    code, out = run_gate(
        str(FIXTURES / "destroy.json"),
        "--allow",
        'github_repository.repo["jol-repo-template"]',
    )
    expect_exit("partially allow-listed destroy plan", EXIT_HALT, code, out)
    expect_text("unlisted resource still blocks", "github_branch_protection.standard", out)


def test_missing_file_fails_closed() -> None:
    code, out = run_gate(str(FIXTURES / "does-not-exist.json"))
    expect_exit("missing plan JSON", EXIT_UNEVALUATED, code, out)
    expect_text("missing plan", "UNEVALUATED", out)


def test_empty_file_fails_closed() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        empty = handle.name
    code, out = run_gate(empty)
    expect_exit("empty plan JSON", EXIT_UNEVALUATED, code, out)
    expect_text("empty plan", "UNEVALUATED", out)


def test_not_a_plan_fails_closed() -> None:
    code, out = run_gate(str(FIXTURES / "not_a_plan.json"))
    expect_exit("JSON that is not a plan", EXIT_UNEVALUATED, code, out)
    expect_text("not-a-plan", "resource_changes", out)


def test_empty_state_mass_create_halts() -> None:
    code, out = run_gate(str(FIXTURES / "empty_state.json"))
    expect_exit("create-heavy plan with no prior state", EXIT_HALT, code, out)
    expect_text("empty state", "EMPTY state", out)


def test_allow_empty_state_override() -> None:
    code, out = run_gate(str(FIXTURES / "empty_state.json"), "--allow-empty-state")
    expect_exit("audited bootstrap override", EXIT_SAFE, code, out)
    expect_text("bootstrap override", "PASSED", out)


def test_max_add_budget_enforced() -> None:
    code, out = run_gate(str(FIXTURES / "clean.json"), "--max-add", "0")
    expect_exit("creates above --max-add budget", EXIT_HALT, code, out)
    expect_text("max-add", "--max-add", out)


def main() -> int:
    if not GATE.is_file():
        print(f"FAILED — gate not found: {GATE}", file=sys.stderr)
        return 1
    if not FIXTURES.is_dir():
        print(f"FAILED — fixtures not found: {FIXTURES}", file=sys.stderr)
        return 1

    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        print(f"{test.__name__}:")
        test()

    if FAILURES:
        print(f"\nFAILED — {len(FAILURES)} assertion(s) across {len(tests)} test(s):", file=sys.stderr)
        for failure in FAILURES:
            print(f"  ✗ {failure}", file=sys.stderr)
        return 1

    print(f"\nPASSED — {len(tests)} plan-gate tests, 0 failures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
