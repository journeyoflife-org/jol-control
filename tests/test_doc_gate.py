#!/usr/bin/env python3
"""Self-tests for scripts/validate_doc_control.py — the document-control block gate.

The fixture tests/fixtures/doc_control/qoder_real.md is captured verbatim from QODER.md's
Document control section on 2026-11-01 (byte-identity is asserted by test 2 below, not
claimed by this comment), and the broken variants are derived from it by mutation so each
case reproduces a mistake an editor can actually make in a metadata table: a row deleted
during a rewrap, a date written as prose, a value cell left empty, an authority row
reworded until it names no superior document.

Why this gate exists: QODER.md §7 points at control IDs and §8 makes a claim about what CI
does and does not enforce. Both age silently. A policy document with no owner, no review
date and no checker is exactly the "overstated control" this repository already documents as
an audit finding, so the minimum measurable property of the document is enforced here:
fields present, precedence declared, review unexpired.

Exit-code convention shared with the other gates: 0 pass, 1 violation, 2 cannot-check.

Run directly (no pytest required):
    python3 tests/test_doc_gate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE = REPO_ROOT / "scripts" / "validate_doc_control.py"
FIXTURE = REPO_ROOT / "tests" / "fixtures" / "doc_control" / "qoder_real.md"
LIVE_DOC = REPO_ROOT / "QODER.md"

EXIT_PASS = 0
EXIT_VIOLATION = 1
EXIT_UNEVALUATED = 2

FAILURES: list[str] = []


def run_gate(path: Path | str, *args: str) -> tuple[int, str]:
    """Invoke the gate as a subprocess; return (exit_code, combined_output)."""
    proc = subprocess.run(
        [sys.executable, str(GATE), str(path), *args],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ✓ {name}" + (f": {detail}" if detail else ""))
    else:
        FAILURES.append(f"{name} — {detail or 'condition false'}")
        print(f"  ✗ {name}" + (f": {detail}" if detail else ""))


def broken(text: str, expect_changed: bool = True) -> tuple[Path, str]:
    """Write mutated text to a temp file; assert the mutation actually applied."""
    if expect_changed:
        assert text != FIXTURE.read_text(encoding="utf-8"), \
            "mutation did not apply (fixture line drifted)"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(text)
        return Path(fh.name), text


def without_row(field: str) -> str:
    out = [l for l in FIXTURE.read_text(encoding="utf-8").splitlines()
           if not l.startswith(f"| {field} |")]
    assert len(out) < len(FIXTURE.read_text(encoding="utf-8").splitlines()), \
        f"row for {field} not present in fixture"
    return "\n".join(out) + "\n"


def revalue(field: str, new_value: str) -> str:
    text = FIXTURE.read_text(encoding="utf-8")
    line = next((l for l in text.splitlines() if l.startswith(f"| {field} |")), None)
    assert line is not None, f"row for {field} not present in fixture"
    return text.replace(line, f"| {field} | {new_value} |") + "\n"


# --------------------------------------------------------------------------- tests

def test_real_fixture_passes() -> None:
    rc, out = run_gate(FIXTURE)
    check("captured document-control block passes", rc == EXIT_PASS, f"exit={rc}")
    check("and reports PASSED, not a silent zero", "PASSED" in out)


def test_fixture_is_a_verbatim_capture() -> None:
    """A fixture that no longer matches the live doc proves nothing about the live doc."""
    contained = FIXTURE.read_text(encoding="utf-8") in LIVE_DOC.read_text(encoding="utf-8")
    check("fixture is byte-identical to a slice of QODER.md", contained)


def test_all_required_fields_are_present_in_the_capture() -> None:
    rc, out = run_gate(FIXTURE)
    check("and the gate counts six fields, not zero", "6" in out.splitlines()[0],
          out.splitlines()[0][:70])


def test_missing_review_date_is_refused() -> None:
    path, _ = broken(without_row("Last reviewed"))
    rc, out = run_gate(path)
    path.unlink()
    check("a block with no review date is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and names the missing field", "Last reviewed" in out)


def test_prose_date_is_refused() -> None:
    path, _ = broken(revalue("Last reviewed", "recently, when the fleet changed"))
    rc, out = run_gate(path)
    path.unlink()
    check("an unparseable review date is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and is described as a date problem", "date" in out.lower())


def test_future_date_is_refused() -> None:
    path, _ = broken(revalue("Last reviewed", "2099-01-01"))
    rc, out = run_gate(path, "--today", "2026-11-01")
    path.unlink()
    check("a review date in the future is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and never reported as fresh", "PASSED" not in out)


def test_overdue_review_is_refused() -> None:
    """The point of the row: an unreviewed policy document must not read as current."""
    rc, out = run_gate(FIXTURE, "--today", "2027-06-01")
    check("a block past its cadence is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and says overdue", "overdue" in out.lower(), out.strip().splitlines()[-1][:70])


def test_cadence_argument_is_wired_not_decorative() -> None:
    """Same document, two thresholds, two verdicts — otherwise --max-age-days is theatre."""
    rc_tight, _ = run_gate(FIXTURE, "--today", "2026-11-02", "--max-age-days", "0")
    rc_loose, _ = run_gate(FIXTURE, "--today", "2026-11-02", "--max-age-days", "92")
    check("a zero-day cadence fails on a one-day-old block", rc_tight == EXIT_VIOLATION,
          f"exit={rc_tight}")
    check("a quarterly cadence passes the same block", rc_loose == EXIT_PASS,
          f"exit={rc_loose}")


def test_empty_value_cell_is_refused() -> None:
    path, _ = broken(revalue("Classification", ""))
    rc, out = run_gate(path)
    path.unlink()
    check("a field with no value is refused", rc == EXIT_VIOLATION, f"exit={rc}")
    check("and the field is named", "Classification" in out)


def test_missing_authority_row_is_refused() -> None:
    path, _ = broken(without_row("Authority"))
    rc, out = run_gate(path)
    path.unlink()
    check("a block that declares no superior document is refused",
          rc == EXIT_VIOLATION, f"exit={rc}")


def test_authority_naming_nothing_is_refused() -> None:
    """'Subordinate to the usual conventions' is not a precedence statement."""
    path, _ = broken(revalue("Authority", "Advisory in the usual way, subordinate to nothing"))
    rc, out = run_gate(path)
    path.unlink()
    check("authority that names no governing file is refused", rc == EXIT_VIOLATION,
          f"exit={rc}")
    check("and says precedence is undeclared", "precedence" in out.lower())


def test_missing_header_fails_closed() -> None:
    text = "\n".join(l for l in FIXTURE.read_text(encoding="utf-8").splitlines()
                     if not l.startswith("| Field |")) + "\n"
    path, _ = broken(text)
    rc, out = run_gate(path)
    path.unlink()
    check("absent header row is UNEVALUATED, not compliant", rc == EXIT_UNEVALUATED,
          f"exit={rc}")
    check("and 'PASSED' never appears for it", "PASSED" not in out)


def test_missing_section_file_and_argument_fail_closed() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write("# Nothing relevant here\n")
        path = Path(fh.name)
    rc, out = run_gate(path)
    path.unlink()
    check("file with no Document control heading is UNEVALUATED", rc == EXIT_UNEVALUATED,
          f"exit={rc}")

    rc, out = run_gate(REPO_ROOT / "tests" / "definitely-not-here.md")
    check("unreadable path is UNEVALUATED", rc == EXIT_UNEVALUATED, f"exit={rc}")
    check("a missing file is never reported as passing", "PASSED" not in out)

    proc = subprocess.run([sys.executable, str(GATE)], capture_output=True, text=True)
    check("running with no path is UNEVALUATED", proc.returncode == EXIT_UNEVALUATED,
          f"exit={proc.returncode}")


def test_live_qoder_md_agrees_with_fixture() -> None:
    """If the live document rots, this case says so on every PR — not only the fixture."""
    rc, out = run_gate(LIVE_DOC)
    check("live QODER.md passes the gate", rc == EXIT_PASS, f"exit={rc}")


def main() -> int:
    if not GATE.is_file():
        print(f"FAILED — gate not found: {GATE}", file=sys.stderr)
        return 1
    if not FIXTURE.is_file():
        print(f"FAILED — fixture not found: {FIXTURE}", file=sys.stderr)
        return 1

    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        print(f"{t.__name__}:")
        t()

    if FAILURES:
        print(f"\nFAILED — {len(FAILURES)} assertion(s) across {len(tests)} test(s):",
              file=sys.stderr)
        for f in FAILURES:
            print(f"  ✗ {f}", file=sys.stderr)
        return 1

    print(f"\nPASSED — {len(tests)} doc-gate tests, 0 failures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
