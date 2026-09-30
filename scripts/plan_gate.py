#!/usr/bin/env python3
"""STOP gate: halt on any Terraform plan that destroys or replaces a resource.

Reads the JSON form of a saved plan (``terraform show -json tfplan``) and fails
if any resource change includes a delete action. Text-grep gates are
deliberately avoided — they go inert silently whenever plan wording changes,
which is a recorded failure mode in this project.

The gate fails CLOSED: a missing, empty, unparseable, or non-plan input is
treated as "cannot prove safe", never as "safe".

Exit codes:
    0 — plan is safe to apply (no destroy/replace, no empty-state mass create)
    1 — plan is refused (destroy/replace, or a create-heavy plan built on an
        empty state, or creates above the --max-add budget)
    2 — the gate could not evaluate the plan (fail closed)

Usage:
    terraform plan -input=false -out=tfplan
    terraform show -json tfplan > tfplan.json
    python3 scripts/plan_gate.py tfplan.json

    # explicit, audited exception for a known resource address:
    python3 scripts/plan_gate.py tfplan.json --allow github_repository.old
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

EXIT_SAFE = 0
EXIT_HALT = 1
EXIT_UNEVALUATED = 2

DEFAULT_PLAN_JSON = "tfplan.json"

# Resource types whose loss is irreversible or organisation-wide.
CRITICAL_TYPES = frozenset(
    {
        "github_repository",
        "github_branch_protection",
        "github_organization_settings",
        "github_team",
        "github_repository_environment",
    }
)


def classify(actions: list[str]) -> str:
    """Map a plan's action list onto destroy / replace / create / update / no-op."""
    has_create = "create" in actions
    has_delete = "delete" in actions
    if has_delete and has_create:
        return "replace"
    if has_delete:
        return "destroy"
    if has_create:
        return "create"
    if "update" in actions:
        return "update"
    return "no-op"


def load_plan(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    """Load plan JSON, returning (data, None) or (None, reason) — never a silent pass."""
    if not path.is_file():
        return None, (
            f"plan JSON not found: {path} — run `terraform plan -out=tfplan` "
            f"then `terraform show -json tfplan > {path}`"
        )
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"cannot read {path}: {exc}"
    if not raw.strip():
        return None, f"{path} is empty — an empty plan cannot be proven safe"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"{path} is not valid JSON: {exc}"
    if not isinstance(data, dict):
        return None, f"{path} does not contain a JSON object"
    if "resource_changes" not in data:
        return None, f"{path} has no 'resource_changes' key — not a terraform plan JSON"
    if not isinstance(data["resource_changes"], list):
        return None, f"{path}: 'resource_changes' is not a list"
    return data, None


def has_prior_state(data: dict[str, Any]) -> bool:
    """True only when the plan was computed against a non-empty prior state.

    A plan with creates and no prior state is the signature of a runner that
    cannot see terraform.tfstate. Verified in this project's own CI history:
    `apply.yml` planned "120 to add, 0 to change, 0 to destroy" and then failed
    with HTTP 403 — had the token been powerful enough, it would have attempted
    to re-create all 40 repositories. `prevent_destroy` cannot catch that case,
    because from an empty state nothing is being destroyed.
    """
    prior = data.get("prior_state")
    if not isinstance(prior, dict):
        return False
    values = prior.get("values")
    if not isinstance(values, dict):
        return False
    root = values.get("root_module")
    if not isinstance(root, dict):
        return False
    resources = root.get("resources")
    return isinstance(resources, list) and len(resources) > 0


def evaluate(
    data: dict[str, Any], allowed: set[str]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, int], int]:
    """Return (blocking, suppressed, totals, evaluated_count) for one plan."""
    blocking: list[dict[str, Any]] = []
    suppressed: list[dict[str, Any]] = []
    totals: dict[str, int] = {"create": 0, "update": 0, "destroy": 0, "replace": 0, "no-op": 0}

    changes = data["resource_changes"]
    for entry in changes:
        if not isinstance(entry, dict):
            continue
        address = str(entry.get("address", "<unknown address>"))
        resource_type = str(entry.get("type", ""))
        change = entry.get("change")
        if not isinstance(change, dict):
            continue
        raw_actions = change.get("actions")
        if not isinstance(raw_actions, list):
            continue
        actions = [str(a) for a in raw_actions]
        kind = classify(actions)
        totals[kind] = totals.get(kind, 0) + 1
        if kind not in {"destroy", "replace"}:
            continue
        finding = {
            "address": address,
            "type": resource_type,
            "kind": kind,
            "actions": actions,
            "critical": resource_type in CRITICAL_TYPES,
            "replace_paths": change.get("replace_paths") or [],
        }
        if address in allowed:
            suppressed.append(finding)
        else:
            blocking.append(finding)

    return blocking, suppressed, totals, len(changes)


def report(
    blocking: list[dict[str, Any]],
    suppressed: list[dict[str, Any]],
    totals: dict[str, int],
    evaluated: int,
    fatal: str | None = None,
) -> int:
    """Print the verdict and return the process exit code."""
    summary = (
        f"plan: {totals.get('create', 0)} to add, {totals.get('update', 0)} to change, "
        f"{totals.get('destroy', 0)} to destroy, {totals.get('replace', 0)} to replace "
        f"({evaluated} resource change(s) evaluated)"
    )

    for item in suppressed:
        print(f"  ⚠ {item['address']} [{item['kind']}] permitted via --allow")

    if fatal is not None:
        print(f"HALT — {fatal}", file=sys.stderr)
        print(f"       {summary}", file=sys.stderr)
        print("", file=sys.stderr)
        print("Required action: STOP and report. Do not apply.", file=sys.stderr)
        print("  Bootstrap-only exception (audited): --allow-empty-state", file=sys.stderr)
        return EXIT_HALT

    if not blocking:
        if suppressed:
            print(
                f"PASSED — {len(suppressed)} destructive action(s) permitted via --allow. {summary}"
            )
        else:
            print(f"PASSED — no destroy/replace actions. {summary}")
        return EXIT_SAFE

    print(f"HALT — {len(blocking)} resource(s) would be destroyed or replaced.", file=sys.stderr)
    print(f"       {summary}", file=sys.stderr)
    for item in blocking:
        marker = "CRITICAL" if item["critical"] else "destructive"
        print(f"  ✗ [{marker}] {item['address']} — {item['kind']} (actions: {item['actions']})", file=sys.stderr)
        if item["replace_paths"]:
            print(f"      forces replacement: {item['replace_paths']}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Required action: STOP and report. Do not apply.", file=sys.stderr)
    print("  1. Confirm the destruction is intended and approved.", file=sys.stderr)
    print("  2. Re-run with an explicit, audited exception:", file=sys.stderr)
    print("       python3 scripts/plan_gate.py tfplan.json --allow <resource address>", file=sys.stderr)
    print("  3. Record the rationale (ADR in jol-docs) before applying.", file=sys.stderr)
    return EXIT_HALT


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Halt if a Terraform plan destroys or replaces any resource."
    )
    parser.add_argument(
        "plan_json",
        nargs="?",
        default=DEFAULT_PLAN_JSON,
        help=f"plan JSON from `terraform show -json tfplan` (default: {DEFAULT_PLAN_JSON})",
    )
    parser.add_argument(
        "--allow",
        action="append",
        default=[],
        metavar="ADDRESS",
        help="resource address permitted to be destroyed/replaced (repeatable, audited)",
    )
    parser.add_argument(
        "--max-add",
        type=int,
        default=None,
        metavar="N",
        help="refuse a plan that creates more than N resources",
    )
    parser.add_argument(
        "--allow-empty-state",
        action="store_true",
        help="permit a create-heavy plan with no prior state (bootstrap only, audited)",
    )
    args = parser.parse_args(argv)

    data, error = load_plan(Path(args.plan_json))
    if error is not None or data is None:
        print(f"UNEVALUATED — {error}", file=sys.stderr)
        print("           Failing closed: an unproven plan is not a safe plan.", file=sys.stderr)
        return EXIT_UNEVALUATED

    blocking, suppressed, totals, evaluated = evaluate(data, set(args.allow))

    creates = totals.get("create", 0)
    fatal: str | None = None
    if creates > 0 and not args.allow_empty_state and not has_prior_state(data):
        fatal = (
            f"plan was built on an EMPTY state yet proposes {creates} create(s). "
            "This runner cannot see terraform.tfstate; applying would attempt to "
            "re-create resources that already exist."
        )
    elif args.max_add is not None and creates > args.max_add:
        fatal = f"plan proposes {creates} create(s), above the --max-add budget of {args.max_add}."

    return report(blocking, suppressed, totals, evaluated, fatal)


if __name__ == "__main__":
    sys.exit(main())
