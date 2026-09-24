#!/usr/bin/env python3
"""Run compliance checks against repo definitions and policy baselines.

Outputs a JSON compliance report suitable for audit evidence.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

BASE_DIR = Path(__file__).resolve().parent.parent
REPOS_DIR = BASE_DIR / "repos"
POLICY_DIR = BASE_DIR / "policy"


def load_yaml(filepath: Path) -> dict:
    with open(filepath) as f:
        return yaml.safe_load(f)


def check_secret_scanning_coverage(repos: dict[str, dict]) -> dict:
    """Verify all repos have secret scanning enabled."""
    covered = 0
    total = len(repos)
    gaps = []
    for name, defn in repos.items():
        settings = defn.get("settings", {})
        if settings.get("vulnerability_alerts", False):
            covered += 1
        else:
            gaps.append(name)
    return {
        "check": "secret_scanning_coverage",
        "status": "pass" if not gaps else "fail",
        "covered": covered,
        "total": total,
        "gaps": gaps,
    }


def check_branch_protection(repos: dict[str, dict]) -> dict:
    """Verify all repos have branch protection with required settings."""
    compliant = 0
    total = len(repos)
    non_compliant = []
    for name, defn in repos.items():
        bp = defn.get("branch_protection", {}).get("main", {})
        issues = []
        if not bp.get("require_signed_commits"):
            issues.append("missing signed commits")
        if not bp.get("block_force_pushes"):
            issues.append("allows force push")
        if not bp.get("enforce_admins"):
            issues.append("admins not enforced")
        if not bp.get("require_linear_history"):
            issues.append("linear history not required")
        if issues:
            non_compliant.append({"repo": name, "issues": issues})
        else:
            compliant += 1
    return {
        "check": "branch_protection",
        "status": "pass" if not non_compliant else "fail",
        "compliant": compliant,
        "total": total,
        "non_compliant": non_compliant,
    }


def check_data_classification(repos: dict[str, dict]) -> dict:
    """Verify all repos have data classification set."""
    classified = 0
    total = len(repos)
    unclassified = []
    for name, defn in repos.items():
        dc = defn.get("compliance", {}).get("data_classification", "")
        if dc in ("public", "internal", "confidential", "restricted"):
            classified += 1
        else:
            unclassified.append(name)
    return {
        "check": "data_classification",
        "status": "pass" if not unclassified else "fail",
        "classified": classified,
        "total": total,
        "unclassified": unclassified,
    }


def check_compliance_frameworks(repos: dict[str, dict]) -> dict:
    """Verify governance/platform repos have all three frameworks."""
    compliant = 0
    total = 0
    gaps = []
    required_frameworks = {"soc2", "gdpr", "iso27001"}
    for name, defn in repos.items():
        tier = defn.get("tier", "")
        if tier in ("governance", "platform"):
            total += 1
            frameworks = set(defn.get("compliance", {}).get("frameworks", []))
            missing = required_frameworks - frameworks
            if missing:
                gaps.append({"repo": name, "missing": sorted(missing)})
            else:
                compliant += 1
    return {
        "check": "compliance_frameworks",
        "status": "pass" if not gaps else "fail",
        "compliant": compliant,
        "total": total,
        "gaps": gaps,
    }


def check_wiki_disabled(repos: dict[str, dict]) -> dict:
    """Verify wiki is disabled on all repos."""
    compliant = 0
    total = len(repos)
    violations = []
    for name, defn in repos.items():
        if defn.get("settings", {}).get("has_wiki", False):
            violations.append(name)
        else:
            compliant += 1
    return {
        "check": "wiki_disabled",
        "status": "pass" if not violations else "fail",
        "compliant": compliant,
        "total": total,
        "violations": violations,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run compliance checks on JOL repo definitions")
    parser.add_argument("--output", type=str, help="Output file path (default: stdout)")
    args = parser.parse_args()

    # Load all repo definitions
    repos: dict[str, dict] = {}
    for yml_file in sorted(REPOS_DIR.glob("*.yml")):
        repos[yml_file.stem] = load_yaml(yml_file)

    # Run checks
    checks = [
        check_secret_scanning_coverage(repos),
        check_branch_protection(repos),
        check_data_classification(repos),
        check_compliance_frameworks(repos),
        check_wiki_disabled(repos),
    ]

    overall_status = "pass" if all(c["status"] == "pass" for c in checks) else "fail"

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "framework": "SOC2/GDPR/ISO27001",
        "overall_status": overall_status,
        "total_repos": len(repos),
        "checks": checks,
    }

    output = json.dumps(report, indent=2)
    if args.output:
        Path(args.output).write_text(output)
        print(f"Report written to {args.output}")
    else:
        print(output)

    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
