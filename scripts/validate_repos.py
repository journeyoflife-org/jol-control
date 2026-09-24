#!/usr/bin/env python3
"""Validate all repository YAML definitions against the allow-list and policy."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPOS_DIR = Path(__file__).resolve().parent.parent / "repos"
POLICY_FILE = Path(__file__).resolve().parent.parent / "policy" / "repo-defaults.yml"

REQUIRED_FIELDS = ["name", "description", "visibility", "tier", "settings", "branch_protection", "compliance"]
VALID_VISIBILITIES = {"public", "private", "internal"}
VALID_TIERS = {"governance", "platform", "devops", "site", "template"}
VALID_CLASSIFICATIONS = {"public", "internal", "confidential", "restricted"}


def load_policy() -> dict:
    with open(POLICY_FILE) as f:
        return yaml.safe_load(f)


def validate_repo(filepath: Path, policy: dict) -> list[str]:
    errors: list[str] = []

    with open(filepath) as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            return [f"{filepath.name}: Invalid YAML — {e}"]

    if not isinstance(data, dict):
        return [f"{filepath.name}: Root must be a YAML mapping"]

    # Required fields
    for field in REQUIRED_FIELDS:
        if field not in data:
            errors.append(f"{filepath.name}: Missing required field '{field}'")

    # Name consistency
    expected_name = filepath.stem
    if data.get("name") != expected_name:
        errors.append(f"{filepath.name}: name='{data.get('name')}' does not match filename '{expected_name}'")

    # Visibility
    vis = data.get("visibility", "")
    if vis not in VALID_VISIBILITIES:
        errors.append(f"{filepath.name}: Invalid visibility '{vis}' — must be one of {VALID_VISIBILITIES}")

    # Tier
    tier = data.get("tier", "")
    if tier not in VALID_TIERS:
        errors.append(f"{filepath.name}: Invalid tier '{tier}' — must be one of {VALID_TIERS}")

    # Settings validation
    settings = data.get("settings", {})
    if not isinstance(settings, dict):
        errors.append(f"{filepath.name}: 'settings' must be a mapping")
    else:
        # Wiki must be disabled (security best practice)
        if settings.get("has_wiki", False):
            errors.append(f"{filepath.name}: has_wiki should be false (security policy)")

    # Branch protection validation
    bp = data.get("branch_protection", {})
    if "main" not in bp:
        errors.append(f"{filepath.name}: Missing branch protection for 'main'")
    else:
        main_bp = bp["main"]
        if not main_bp.get("require_signed_commits", False):
            errors.append(f"{filepath.name}: main branch must require signed commits")
        if not main_bp.get("block_force_pushes", False):
            errors.append(f"{filepath.name}: main branch must block force pushes")
        if not main_bp.get("enforce_admins", False):
            errors.append(f"{filepath.name}: main branch must enforce admins")

    # Compliance validation
    compliance = data.get("compliance", {})
    if not compliance.get("frameworks"):
        errors.append(f"{filepath.name}: compliance.frameworks must not be empty")
    dc = compliance.get("data_classification", "")
    if dc not in VALID_CLASSIFICATIONS:
        errors.append(f"{filepath.name}: Invalid data_classification '{dc}' — must be one of {VALID_CLASSIFICATIONS}")

    return errors


def main() -> int:
    if not REPOS_DIR.is_dir():
        print(f"ERROR: repos directory not found: {REPOS_DIR}", file=sys.stderr)
        return 1

    policy = load_policy()
    all_errors: list[str] = []
    repo_count = 0

    for yml_file in sorted(REPOS_DIR.glob("*.yml")):
        repo_count += 1
        errors = validate_repo(yml_file, policy)
        all_errors.extend(errors)

    if all_errors:
        print(f"FAILED — {len(all_errors)} error(s) in {repo_count} repo definitions:\n")
        for err in all_errors:
            print(f"  ✗ {err}")
        return 1

    print(f"PASSED — {repo_count} repo definitions validated successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
