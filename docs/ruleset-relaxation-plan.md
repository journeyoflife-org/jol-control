# Ruleset Relaxation Plan (journeyoflife-org)

Owner: architecture (agent-drafted)
Classification: internal
Framework: SOC2 / GDPR / ISO 27001
Status: **DRAFT — NO enforcement has been changed. Execution is gated on ADR-013 acceptance and an explicit owner decision.**
Measured: 2026-11-03 (live `gh api .../rulesets` re-scan; counts drift between audits — re-scan before executing).

## Why this exists

`solo_mode = true` (`terraform.tfvars:16`) makes Terraform omit the review blocks in
`branch-protection.tf`, yet **20 public repositories carry hand-configured rulesets** that
re-impose `required_approving_review_count >= 1` and/or `require_code_owner_review` — the
exact controls `solo_mode` removes. With a single org member (GitHub does not count an
author's own approval), those rules are **unsatisfiable**, so a normal PR can only merge by
admin bypass. This blocks the mise rollout (and any other change) on those repos.

- Invariant (ADR-013, `jol-docs` PR #4, *Proposed*): *no repository may demand more approvals
  than the organization can supply.* Make it a testable rule, not prose.
- Ordering: **accept-then-relax** — removing a review control must be authorized by the
  decision record first, not documented after the fact.
- This is invisible to the control plane: no `github_repository_ruleset` resource exists in
  the baseline, and `scripts/drift_detect.py` reads only `name,visibility`, so `make drift`
  reports NO DRIFT while these repos are governed by undeclared config (see `docs/drift-findings.md` S1-008).

## Live inventory (2026-11-03)

| Repository | Ruleset(s) | Note |
|---|---|---|
| jol-domain-taxonomy | protect-main | |
| jol-infrastructure | protect-main | |
| jol-ecommerce-engine | protect-main, protect-release-tags | tag-protection ruleset is legitimate — leave it |
| jol-hub | protect-main, `~master` | `~master` is stale (default branch is `main`) — remove |
| jol-compliance | Protect main branch, jol-compliance-main-protection, protect-main | 3 overlapping; one disabled — consolidate to one |
| jol-hermes-agents | protect-main | |
| jol-rag-server | protect-main | |
| jol-llm | protect-main | |
| jol-site-basilica / -cathedral / -diocese / -deanery / -parish / -funeral / -cemetery-care / -protestant / -orthodox / -other-church | protect-main | 10 spokes |
| jol-deploy | protect-main | |
| .github | protect-main | shared CI library + S1-007 merge-block mystery — do LAST |
| jol-dr | (403 — private) | rulesets unavailable on this plan; cannot relax via this API |

Total public repos with rulesets: **20**. `jol-dr` is unobservable (private).

## Target state (the declared solo posture)

Relax **only** the `pull_request` rule of each `protect-main` ruleset to match `solo_mode`:
- `required_approving_review_count` → `0`
- `require_code_owner_review` → `false`

**Keep unchanged** (these need no reviewers and are real controls): `required_signatures`,
`required_linear_history`, `deletion` block, `non_fast_forward` block, and the existing
`bypass_actors`. Do not touch `protect-release-tags` (tag protection) or any non-review rule.

## Per-repository procedure — reversible (mechanics live in `docs/runbooks.md` RB-06)

RB-06 already documents the two-API blindness and the GET→mutate→PUT full-replace hazard.
This plan is the batch application of RB-06 across the 20 repos:

1. **Backup** the exact current ruleset JSON out-of-band before any write:
   `gh api repos/journeyoflife-org/<repo>/rulesets/<id> > backup__<repo>__<id>.json`
2. **Edit only** the `pull_request` rule's two parameters (leave every other rule byte-identical).
3. **PUT** the full ruleset back (rulesets are a full-replace; a partial body drops omitted rules).
4. **Read-back with a cache-bust** (`?cb=$RANDOM`) and compare **values, not status** — a 2xx is
   not proof (see the cache/staleness trap). Confirm `required_approving_review_count == 0`
   and `require_code_owner_review == false`, and that signatures/linear/no-force/no-delete survived.
5. **Acceptance test:** open a trivial signed PR and confirm `mergeable_state` is `clean`
   (not `blocked`) with `requested_changers=0` — i.e., it merges on merit, no admin bypass.

**Rollback:** `PUT` the saved `backup__<repo>__<id>.json` back verbatim; read-back to confirm.

## Sequencing & blast radius

1. **One pilot repo first** — a single `jol-site-*` spoke (low impact, no other consumers). Verify steps 4–5.
2. **Batch the remaining spokes** (10) one ruleset per change, each with its own backup + read-back.
3. **Platform repos** (hub, infrastructure, ecommerce-engine, hermes-agents, rag-server, llm,
   domain-taxonomy, compliance, deploy) — consolidate the duplicate/stale rulesets on hub and
   compliance as part of the pass.
4. **`.github` LAST** — it is the shared workflow library and carries the unresolved S1-007
   merge-block; do not batch it with the rest.
5. **`jol-dr`** — out of scope here (private, rulesets 403); handle only after private-repo
   protection is addressed.

## Guardrails

- **No org-level ruleset change** — `GET /orgs/journeyoflife-org/rulesets` returns 403
  ("Upgrade to GitHub Team"); org rulesets are neither readable nor safely writable on this plan.
- **Do not weaken** signed commits, linear history, force-push, or deletion blocks.
- Every change is an auditable, reversible record (backup JSON + before/after read-back),
  satisfying SOC2 CC8 / ISO 27001 change management.
- This document changes **nothing**. Execution begins only after ADR-013 is accepted and the
  owner authorizes the specific repo(s).
