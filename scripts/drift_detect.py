#!/usr/bin/env python3
"""Detect drift between jol-control definitions and actual GitHub state.

Compares repos/*.yml allow-list against the GitHub organization's actual
repository list using the GitHub API.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

BASE_DIR = Path(__file__).resolve().parent.parent
REPOS_DIR = BASE_DIR / "repos"


def get_github_repos() -> set[str]:
    """Get list of repos from GitHub using gh CLI."""
    token = os.environ.get("GITHUB_TOKEN", "")
    try:
        result = subprocess.run(
            ["gh", "repo", "list", "journeyoflife-org", "--limit", "200", "--json", "name"],
            capture_output=True,
            text=True,
            env={**os.environ, "GITHUB_TOKEN": token} if token else os.environ,
        )
        if result.returncode != 0:
            print(f"ERROR: gh CLI failed: {result.stderr}", file=sys.stderr)
            return set()
        repos = json.loads(result.stdout)
        return {r["name"] for r in repos}
    except FileNotFoundError:
        print("ERROR: gh CLI not found", file=sys.stderr)
        return set()


def get_defined_repos() -> set[str]:
    """Get list of repos from YAML definitions."""
    defined = set()
    for yml_file in REPOS_DIR.glob("*.yml"):
        with open(yml_file) as f:
            data = yaml.safe_load(f)
            if data and "name" in data:
                defined.add(data["name"])
    return defined


def main() -> int:
    defined = get_defined_repos()
    actual = get_github_repos()

    if not actual:
        print("WARNING: Could not fetch GitHub repos — skipping drift detection", file=sys.stderr)
        return 0

    # Exclude .github special repo
    actual_repos = actual - {".github"}

    # Drift analysis
    in_defined_not_github = defined - actual_repos
    in_github_not_defined = actual_repos - defined
    matched = defined & actual_repos

    report = {
        "defined_count": len(defined),
        "github_count": len(actual_repos),
        "matched_count": len(matched),
        "in_defined_not_github": sorted(in_defined_not_github),
        "in_github_not_defined": sorted(in_github_not_defined),
        "drift_detected": bool(in_defined_not_github or in_github_not_defined),
    }

    # Structured report -> stdout (machine-parseable, pipeable to jq / json.load)
    print(json.dumps(report, indent=2))

    # Human-readable summary -> stderr (never pollutes the JSON on stdout)
    if report["drift_detected"]:
        if in_defined_not_github:
            print(f"DRIFT: {len(in_defined_not_github)} repo(s) in allow-list but NOT on GitHub:", file=sys.stderr)
            for r in sorted(in_defined_not_github):
                print(f"  - {r}", file=sys.stderr)
        if in_github_not_defined:
            print(f"DRIFT: {len(in_github_not_defined)} repo(s) on GitHub but NOT in allow-list:", file=sys.stderr)
            for r in sorted(in_github_not_defined):
                print(f"  - {r}", file=sys.stderr)
        return 1

    print(f"NO DRIFT — All {len(matched)} repos match between allow-list and GitHub.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
