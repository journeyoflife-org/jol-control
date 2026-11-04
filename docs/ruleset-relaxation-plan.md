# Ruleset Relaxation Plan (journeyoflife-org)

Owner: architecture (agent-drafted)
Classification: internal
Framework: SOC2 / GDPR / ISO 27001
Status: **DRAFT — NO enforcement has been changed. Execution is gated on ADR-013 acceptance and an explicit owner decision.**
Measured: first 2026-11-03, re-scanned 2026-11-03T22:05Z per-ruleset `GET /rulesets/{id}`; counts
  drift between audits — re-scan before executing.

## Why this exists

`solo_mode = true` (`terraform.tfvars:16`) makes Terraform omit the review blocks in
`branch-protection.tf`, yet **19 public repositories carry hand-configured rulesets** that
re-impose `required_approving_review_count >= 1` and/or `require_code_owner_review` — the
exact controls `solo_mode` removes. With a single org member (GitHub does not count an
author's own approval), those rules are **unsatisfiable**, so a normal PR can only merge by
admin bypass. This blocks the mise rollout (and any other change) on those repos.
  A 20th repository, `.github`, also carries a `protect-main` ruleset, but its pull-request rule
  sets `approving=0`/`code_owner=false` — so it is **not** review-blocking (its non-merge is the
  separate S1-007). The accurate review-blocking count is therefore **19**.

- Invariant (ADR-013, `jol-docs` PR #4, *Proposed*): *no repository may demand more approvals
  than the organization can supply.* Make it a testable rule, not prose.
- Ordering: **accept-then-relax** — removing a review control must be authorized by the
  decision record first, not documented after the fact.
- This is invisible to the control plane: no `github_repository_ruleset` resource exists in
  the baseline, and `scripts/drift_detect.py` reads only `name,visibility`, so `make drift`
  reports NO DRIFT while these repos are governed by undeclared config (see `docs/drift-findings.md` S1-008).

## Live inventory (re-scanned 2026-11-03)

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
| .github | protect-main | non-review ruleset (`approving=0`/`code_owner=false`); shared CI library + S1-007 merge-block mystery — do LAST |
| jol-dr | (403 — private) | rulesets unavailable on this plan; cannot relax via this API |

Total public repos with rulesets: **20** — but only **19 impose a review/code-owner requirement a
single member cannot satisfy**; `.github` is the 20th and its rule is non-review. `jol-dr` is
unobservable (private).

## Target state (the declared solo posture)

Relax **only** the `pull_request` rule of each `protect-main` ruleset to match `solo_mode`:
- `required_approving_review_count` → `0`
- `require_code_owner_review` → `false`

**Keep unchanged** (these need no reviewers and are real controls): `required_signatures`,
`required_linear_history`, `deletion` block, `non_fast_forward` block, and the existing
`bypass_actors`. Do not touch `protect-release-tags` (tag protection) or any non-review rule.

## Per-repository procedure — reversible (mechanics live in `docs/runbooks.md` RB-06)

RB-06 already documents the two-API blindness and the GET→mutate→PUT full-replace hazard.
This plan is the batch application of RB-06 across the 19 review-blocking repos (`.github` last):

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

## Appendix A — Ready-to-execute procedure (GATED — do NOT run until ADR-013 is accepted)

Worked example for one spoke (`jol-site-basilica`). Re-scan for the id first; never assume it.

```bash
# 1) discover id + confirm which ruleset is the review one
gh api repos/journeyoflife-org/jol-site-basilica/rulesets --jq '.[]|{id,name,enforcement}'
# 2) BACKUP out-of-band (this file is the rollback artifact)
gh api repos/journeyoflife-org/jol-site-basilica/rulesets/<ID> > backup__basilica__<ID>.json
# 3) build relaxed body: change ONLY the two review parameters; strip server fields
jq 'del(.id,.node_id,.url,.html_url,._links,.version,.source,.current_user_can_bypass)
    | .rules |= map(if .type=="pull_request"
        then .parameters.required_approving_review_count=0 | .parameters.require_code_owner_review=false
        else . end)' backup__basilica__<ID>.json > relaxed.json
# 4) PUT full-replace (rulesets are replace, not patch)
gh api -X PUT repos/journeyoflife-org/jol-site-basilica/rulesets/<ID> --input relaxed.json
# 5) read-back with cache-bust; compare VALUES, not status
gh api "repos/journeyoflife-org/jol-site-basilica/rulesets/<ID>?cb=$RANDOM" \
  --jq '.rules[]|select(.type=="pull_request").parameters|{required_approving_review_count,require_code_owner_review}'
# 6) acceptance: a trivial signed PR now reports mergeable_state=clean (not blocked)
# ROLLBACK: gh api -X PUT .../rulesets/<ID> --input backup__basilica__<ID>.json
```

Guards: keep `required_signatures`, `required_linear_history`, `deletion`, `non_fast_forward`, and
`bypass_actors` byte-identical; confirm each survived the full-replace PUT in step 5. Do `.github`
last (S1-007). `jol-dr` cannot be relaxed this way (private → rulesets return 403).

**Verified 2026-11-04:** executed on `jol-site-basilica` (ruleset `23356341`) — PUT + cache-busted
read-back (ac=0, code_owner=false, all 5 rules intact); acceptance PR #11 reached
`mergeable_state=clean` and squash-merged `a48fc08d` with **no admin bypass**. Rule selector is
`.type`, not `.name`. Rollback artifact `basilica_23356341_original_*.json` (sha256 4d0cbd3d…).

## Relaxation campaign — executed (2026-11-04)

ADR-013 accepted (`jol-docs` PR #4 → `af1d47d0`); the per-repo RB-06 relaxation below then ran
under explicit owner authorization. Rollback JSON (+ `sha256`) for every change is in
`/home/jol/.local/share/jol-ruleset-backups/`; restore = PUT the `_original_*`/`_predelete_*`
file back to the same ruleset id.

**Method (each repo):** minimal full-replace `PUT` altering ONLY the `pull_request` rule
(`required_approving_review_count` 1→0, `require_code_owner_review` true→false);
`required_signatures`, `required_linear_history`, `deletion`, `non_fast_forward` and
`bypass_actors` left byte-identical; verified by a cache-busted read-back of the changed VALUES,
then an acceptance PR merged with **no admin bypass** (for jol-hub, proven by its dependabot PRs
reaching `MERGEABLE/CLEAN`).

**Review/code-owner gate removed + merit-merge proven — 17 of 19:** all ten `jol-site-*` spokes
(basilica `23356341`, cathedral `23356345`, cemetery-care `23356356`, deanery `23356349`,
diocese `23356346`, funeral `23356354`, orthodox `23356360`, other-church `23356363`, parish
`23356352`, protestant `23356357`); `jol-ecommerce-engine` protect-main `23356333` (its
`protect-release-tags` `20754411` left intact); `jol-domain-taxonomy` `23356278`;
`jol-hermes-agents` `23356368`; `jol-rag-server` `23356332`; `jol-llm` `23356366`;
`jol-compliance` protect-main `23356340` (other active ruleset `18733439` has a satisfiable
`compliance-lint` status check; `18790594` disabled); and `jol-hub` — protect-main `23356334`
review relaxed **and** the stale `~master` `14827989` (whose `required_status_checks`
`compliance-check`/`ci` match nothing) **deleted**.

**Still blocked by a SEPARATE, non-review gate — 2 of 19 (relax kept, not force-merged):**
`jol-infrastructure` `18809087` has a `required_status_checks` rule whose contexts
`Infrastructure Validation / <job>` don't match the real bare check names (unsatisfiable);
`jol-deploy` `23732532`'s own `Validate Configs` check fails. Both need those required-status-check
contexts corrected/removed — a distinct change with its own owner decision.

`.github` is non-review (its block is the separate S1-007) and `jol-dr` is private/403-unobservable;
neither is among the 19. Appendix A above once used the wrong rule selector; the correct one is
`.type=="pull_request"` (a `.name` selector silently matches nothing). The relaxation was executed
with `.type`.
