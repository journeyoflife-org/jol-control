#!/usr/bin/env python3
"""Detect drift between the repos/*.yml allow-list and the live GitHub organization.

Exit codes follow scripts/plan_gate.py and scripts/state_gate.py:

  0  EVALUATED, NO DRIFT   the allow-list and GitHub agree, and we know that because
                           we could actually see the organization
  1  DRIFT                 a declared repository is genuinely absent, or a live
                           repository is undeclared
  2  UNEVALUATED          the check could not be trusted — the API call failed, the
                           listing is provably partial, or this token cannot see the
                           repositories the allow-list says are private

Why the third code had to exist (finding S14, verified 2026-10-09): the weekly
Compliance Scan failed with `in_defined_not_github: ["jol-dr"]` while `make drift`
on this host reported `NO DRIFT — All 40 repos match`. Nothing is missing — `jol-dr`
exists and is PRIVATE (gh api repos/journeyoflife-org/jol-dr -> visibility=PRIVATE).
CI runs drift detection with `secrets.GITHUB_TOKEN`, whose installation can only
enumerate public repositories, so the one private repo in the fleet looked absent.

Two defects followed from that, and both are worse than the false alarm:

  * "cannot see" was reported as "does not exist", so a real absence and a
    permission artefact produced identical output; and
  * the old code returned 0 — green — when the listing came back EMPTY
    (`if not actual: return 0`), so a fully blind run passed silently.

A control that cries wolf when half-blind and says nothing when fully blind is not
evidence. Every partial view now returns 2, never 0 and never 1.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

BASE_DIR = Path(__file__).resolve().parent.parent
REPOS_DIR = BASE_DIR / "repos"

EXIT_CLEAN = 0
EXIT_DRIFT = 1
EXIT_UNEVALUATED = 2

# `gh repo list --limit N` stops at N. Hitting the cap means the set difference is
# meaningless, so the number must be far above the fleet and the cap must be checked.
LIST_LIMIT = 500


def gh_bin() -> str:
    """Overridable for tests: DRIFT_GH points at a stub that replays captured API output."""
    return os.environ.get("DRIFT_GH", "gh")


def run(args: list[str]) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, check=False)
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", f"{args[0]} not found on PATH"


def get_defined(repos_dir: Path) -> dict[str, str]:
    """{name: visibility} from the allow-list. Visibility is what makes blindness detectable."""
    defined: dict[str, str] = {}
    for yml_file in sorted(repos_dir.glob("*.yml")):
        try:
            data = yaml.safe_load(yml_file.read_text())
        except (OSError, yaml.YAMLError) as exc:
            print(f"UNEVALUATED: cannot read {yml_file.name}: {exc}", file=sys.stderr)
            return {}
        if isinstance(data, dict) and data.get("name"):
            defined[str(data["name"])] = str(data.get("visibility", "public"))
    return defined


def list_live_repos(org: str) -> tuple[list[dict] | None, str]:
    """Repositories this token can see. Returns (rows, error); error is never swallowed."""
    rc, out, err = run([gh_bin(), "repo", "list", org, "--limit", str(LIST_LIMIT),
                        "--json", "name,visibility"])
    if rc != 0:
        return None, f"gh repo list failed (exit {rc}): {err.strip()[:300]}"
    try:
        rows = json.loads(out)
    except json.JSONDecodeError as exc:
        return None, f"gh repo list returned unparseable output: {exc}"
    if not isinstance(rows, list):
        return None, "gh repo list returned a non-list document"
    return rows, ""


def probe_repo(org: str, name: str) -> str:
    """'exists' | 'absent' | 'unverifiable' for one repository, by direct lookup.

    404 is ambiguous on GitHub: it means both "does not exist" and "you may not see it".
    It is only read as 'absent' when the caller has already proven the token can see
    private repositories; otherwise it is 'unverifiable'.
    """
    rc, out, err = run([gh_bin(), "api", f"repos/{org}/{name}"])
    if rc == 0:
        return "exists"
    blob = (out + err).lower()
    if "404" in blob or "not found" in blob:
        return "absent"
    return "unverifiable"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--org", default=os.environ.get("DRIFT_ORG", "journeyoflife-org"))
    ap.add_argument("--repos-dir", default=str(REPOS_DIR))
    a = ap.parse_args()
    org, repos_dir = a.org, Path(a.repos_dir)

    defined = get_defined(repos_dir)
    if not defined:
        print(f"UNEVALUATED: no repository definitions found under {repos_dir}", file=sys.stderr)
        return EXIT_UNEVALUATED

    rows, err = list_live_repos(org)
    if rows is None:
        print(f"UNEVALUATED: {err}", file=sys.stderr)
        print("Cannot compare the allow-list to an organization we cannot enumerate. "
              "This is NOT a pass.", file=sys.stderr)
        return EXIT_UNEVALUATED
    if not rows:
        print(f"UNEVALUATED: {org} returned an EMPTY repository list. An organization "
              "with declared repos cannot list zero — that is a token/permission artefact.",
              file=sys.stderr)
        return EXIT_UNEVALUATED
    if len(rows) >= LIST_LIMIT:
        print(f"UNEVALUATED: listing hit the --limit cap ({LIST_LIMIT}); the set "
              "difference would be computed from a truncated view.", file=sys.stderr)
        return EXIT_UNEVALUATED

    live = {r["name"] for r in rows if "name" in r}
    live_no_special = live - {".github"}
    vis = {r["name"]: str(r.get("visibility", "")).upper() for r in rows if "name" in r}
    saw_private = any(v == "PRIVATE" for v in vis.values())
    declared_private = sorted(n for n, v in defined.items() if v == "private")

    missing = sorted(set(defined) - live_no_special)
    extra = sorted(live_no_special - set(defined))

    # Blindness test: the allow-list declares private repositories but the enumeration
    # contains none. This is exactly the CI shape that produced the S14 false alarm.
    blind = bool(declared_private) and not saw_private
    if blind:
        for name in missing:
            if probe_repo(org, name) == "exists":
                print(f"UNEVALUATED: {org}/{name} exists but did not appear in the "
                      "enumeration — this token cannot see private repositories.",
                      file=sys.stderr)
                report = {"evaluated": False, "reason": "token cannot see private repos",
                          "defined_count": len(defined), "github_count": len(live_no_special),
                          "unevaluated_missing": missing}
                print(json.dumps(report, indent=2))
                return EXIT_UNEVALUATED
        print(f"UNEVALUATED: {len(declared_private)} repo(s) are declared private "
              f"({', '.join(declared_private)}) and the listing contains no private "
              "repositories, so absence cannot be concluded from it.", file=sys.stderr)
        print("Use a token that can read the organization, or run `make drift` on the "
              "control-plane host.", file=sys.stderr)
        report = {"evaluated": False, "reason": "cannot enumerate private repos",
                  "defined_count": len(defined), "github_count": len(live_no_special),
                  "unevaluated_missing": missing}
        print(json.dumps(report, indent=2))
        return EXIT_UNEVALUATED

    # Not blind: confirm each absence by direct lookup before calling it a fact.
    # "exists" here means the enumeration itself was incomplete — reporting that as drift
    # would repeat the S14 mistake with a different cause.
    answers = {name: probe_repo(org, name) for name in missing}
    contradicted = [n for n in missing if answers[n] == "exists"]
    if contradicted:
        print(f"UNEVALUATED: {', '.join(contradicted)} answered a direct lookup but was "
              "absent from the enumeration — the listing is incomplete, so no conclusion "
              "about absence can be drawn.", file=sys.stderr)
        return EXIT_UNEVALUATED

    unverifiable = [n for n in missing if answers[n] == "unverifiable"]
    if unverifiable:
        print(f"UNEVALUATED: could not confirm {', '.join(unverifiable)} — the API call "
              "for them failed rather than answering.", file=sys.stderr)
        return EXIT_UNEVALUATED

    report = {
        "evaluated": True,
        "defined_count": len(defined),
        "github_count": len(live_no_special),
        "matched_count": len(set(defined) & live_no_special),
        "in_defined_not_github": missing,
        "in_github_not_defined": extra,
        "drift_detected": bool(missing or extra),
    }
    print(json.dumps(report, indent=2))

    if missing or extra:
        for name in missing:
            print(f"DRIFT: {name} is declared in repos/ but does not exist in {org}",
                  file=sys.stderr)
        for name in extra:
            print(f"DRIFT: {name} exists in {org} but is not declared in repos/", file=sys.stderr)
        return EXIT_DRIFT

    print(f"NO DRIFT — All {len(set(defined) & live_no_special)} repos match between "
          "allow-list and GitHub.", file=sys.stderr)
    return EXIT_CLEAN


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:      # a crash is "cannot check", never "pass" and never "drift"
        print(f"UNEVALUATED: internal error: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(EXIT_UNEVALUATED)
