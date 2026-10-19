# Changelog

All notable changes to jol-control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/state_gate.py` — STOP gate that refuses `terraform apply` when the state in
  front of the config cannot account for what the config would create: 0-byte state file
  (Terraform writes state atomically and never produces one on its own), state that
  parses but holds zero managed resources, or no state at all while the directory
  declares resources or module blocks. Reads `terraform.tfstate` **and**
  `terraform.tfstate.d/<workspace>/terraform.tfstate`, and classifies a directory as
  "not an apply target" only on positive evidence (a parent `module` block with a
  relative source, or a vendored/quarantined tree) — never on absence of state.
  A root whose backend is declared in `.tf`/`.tpl`/`.backend.hcl` is reported
  UNEVALUATED rather than safe, because local files cannot see remote state.
- `tests/test_state_gate.sh` — 16 self-tests with distinct exit codes
  (0 safe / 1 refused / 2 cannot-check), built on the key shape of a real captured
  Terraform 1.16.1 state document
- `tests/test_drift_gate.py` + `tests/fixtures/drift_detect/` — 11 self-tests for
  `scripts/drift_detect.py`, built on two real captures of `gh repo list
  journeyoflife-org --json name,visibility`: the operator-token view (41 rows, one
  PRIVATE) and the `secrets.GITHUB_TOKEN` view reconstructed from the log of failed run
  37107745958 (39 rows, no private repository visible at all)
- `scripts/validate_agents_table.py` + `tests/test_agents_gate.py` (9 cases) +
  `make agents-gate` — AGENTS.md section 2 is what an agent reads before trusting any claim
  about this organization, and it was checked by nobody. Documentation-only commits were
  excluded from `apply.yml`'s `paths:` filter, so a malformed row could sit on `main` with no
  CI signal at all; `AGENTS.md` is therefore now in that filter and the gate runs in
  `Dev — Validate` on every push to `main`, plus in `compliance-scan.yml` on pull requests and
  the weekly schedule. It requires three non-empty cells per row and a non-empty evidence cell,
  treats escaped `\|` as content rather than a separator, and fails closed: 0 pass / 1
  violation / 2 cannot-check, with a missing header, a missing section, an unreadable file and
  a no-argument invocation all reporting UNEVALUATED rather than success.
  Fixtures are a verbatim capture of the live section and the broken variants are derived from
  it by mutation, reproducing the mistakes an editor actually makes — an unescaped pipe that
  silently adds a cell, a blank evidence column, a header-only table
- `docs/runbooks.md` RB-06 — "Inspect or Change a Repository Ruleset", written from the
  measurements taken while chasing the `.github` merge block: rulesets and classic branch
  protection are separate APIs blind to each other (a `404` from one is not an absence of
  protection), a ruleset `PUT` is a full replace so the current document must be snapshotted
  first, required status checks live inside the `update` rule's parameters rather than as their
  own rule type, and any verification read must be cache-busted because GitHub serves cached
  reads for up to 60 seconds. It records the measured `protect-main` state, that organization
  rulesets cannot even be listed on this plan, and an explicit instruction not to improvise a
  cause for the unresolved block — toggles made while testing must be undone.
- `policy/contact-channels.yml` — authoritative role → address mapping for
  journeyoflife-org (`dev`, `github`, `billing`, `security`, `privacy`). Splits the
  channels into an **admin plane** (billing/github/dev — GitHub-internal, never
  written into a public file) and a **public plane** (security/privacy — publishable,
  because a data subject cannot exercise a statutory right through a GitHub
  advisory). Records that all five are plus-addressed aliases of one mailbox and
  therefore provide triage, not segregation of duties or an independent failure
  domain; states which artifacts must never be edited (captured evidence, generated
  scanner output, documentation placeholders); and notes that organization email
  settings are not Terraform-managed.
- `docs/drift-findings.md` S1-003 — every contact address published across the fleet
  is undeliverable. `journeyoflife.org` has a **null MX** (`MX 0 .`, RFC 7505) on
  afternic parking nameservers, `journeyoflife.eu` has no MX, `journeyoflife.lt` does
  not resolve. 112 + 5 occurrences over 74 files in 27 repositories, including 28
  `SECURITY.md` files directing researchers to a hard-bouncing address and
  `jol-devops/monitoring/alertmanager/alertmanager.yaml` configuring an email receiver on
  it (and `smtp.journeyoflife.org` resolving to the same domain-parking addresses as the
  apex, i.e. no SMTP server). Private vulnerability reporting was also enabled on 0 of the
  40 public repositories, so the organization had no working vulnerability intake at all —
  see Fixed.
- `docs/threat-model.md` T-13 (unreachable security/DPO contacts, Availability) and
  risk acceptance **RA-04** for publishing role aliases while no domain mail exists
- `docs/drift-findings.md` S2-005 — the git-identity half of the migration, recorded as it was
  learned: `POST /user/emails` answers `404` even with the `user:email` scope so account
  addresses are UI-only, `required_signatures` and `enforce_admins` are both live on `main`,
  `--global` identity is the wrong scope on a three-organization host, and a commit authored
  by an address that is not a verified email on the key's account is **refused at push**
  (GH006), not merely unverified. Contains two same-day corrections, including the retraction
  of this entry's own earlier conclusion
- `policy/contact-channels.yml` gained an `identity_migration` block: the order of
  operations, the two-authenticated-accounts hazard, and the host state as verified
- `policy/contact-channels.yml` → `role_mapping` — every address actually published in the
  estate with its replacement or an explicit `delete`/`leave alone` verdict, so sweeping the
  remaining 24 repositories is a lookup rather than 24 fresh judgement calls. Addresses absent
  from the table must raise a question, not an invented channel.
- `docs/drift-findings.md` S1-004 + `docs/threat-model.md` T-14 — the advertised donation path
  is a parked domain: `https://journeyoflife.org/donate` answers 200 with a 114-byte redirect to
  `/lander` and `journeyoflife.eu` is Hostinger-parked, so donors reach a third-party ad page
  served under the organization's own name. A fleet-wide search found **no** real donation
  endpoint anywhere, and this change deliberately did not guess one — owner decision required
- `docs/drift-findings.md` — a measurement-traps section recording that rulesets and legacy
  branch protection are invisible to each other (`.github` main looks unprotected through the
  legacy API but is enforced by ruleset `protect-main` with signatures, linear history, merge and
  deletion blocks, code-owner review at zero required approvals, and an always-on admin bypass),
  that `github_branch_protection` must be summed across both its state resources, and that an
  unquoted heredoc silently executes backticked prose
- `docs/drift-findings.md` S1-009 — **seven governance-tier repositories have branch protection
  in state and none on GitHub.** `terraform.tfstate` (serial 306) holds 39
  `github_branch_protection` instances across 39 distinct repositories, but
  `jol-compliance-evidence`, `jol-iac`, `jol-incident-response`, `jol-payments-scope`,
  `jol-privacy`, `jol-secrets` and `jol-status` are empty (`size=0`, `409 Git Repository is
  empty`), so `GET …/branches/main/protection` answers 404 there: 32 of 41 repositories are
  protected live, and the governance tier's asserted posture (signed commits, linear history,
  force-push and deletion blocks, `enforce_admins`) is in force on only 4 of its 11 members.
  `make drift` cannot see any of this — `scripts/drift_detect.py` compares `name,visibility`
  only. Discovered by refuting someone else's claim of a *duplicate* protection: the tier
  partition in `branch-protection.tf:22,29` is disjoint by construction, and no repository is
  covered twice
- `docs/drift-findings.md` — measurement traps 6–8: a confident report that an action was taken
  is not a measurement (six claims in one turn, every one contradicted by `gh pr view`,
  `git cat-file` and a re-scan); a `Bearer`-token `curl` against `github.com` HTML cannot
  discriminate token scope, because HTML answers 404 for a private repository even to a token
  that reads it through the API; and a workflow run whose name matches a reusable workflow is
  not proof that a caller resolved it (`jol-docs`' green `compliance-check` is its own file)
- `docs/runbooks.md` RB-07 — "Mint or Rotate `ORG_READ_TOKEN`", the read-only fine-grained PAT
  the CI drift job needs to see private repositories. Carries the scope table with the consequence
  of each wrong row (resource owner, **All repositories**, Metadata/Contents read, Members read,
  90-day expiry, name pattern), the pre-filled token form, verify-before-store commands that prove
  the token can enumerate `jol-dr` **before** it is saved as a secret, the CI proof that a name
  read-back cannot substitute for, the failure signature that separates `401 Bad credentials` (the
  credential value) from `403 Resource not accessible by personal access token` (the scope), an
  inventory table whose `expires_at` must be transcribed from Settings because `GET
  /orgs/journeyoflife-org/personal-access-tokens` answers `404` from this host, and the degradation
  note: removing the secret returns the job to an honest UNEVALUATED, never to green

### Changed
- `.github/workflows/compliance-scan.yml`: the drift step binds `secrets.ORG_READ_TOKEN ||
  secrets.GITHUB_TOKEN` instead of the runner token alone, and its exit-2 annotation now points at
  RB-07 rather than telling the operator to create a credential that already exists. The fallback
  is what keeps this honest: an unset or expired secret degrades the job to UNEVALUATED, never to a
  pass and never to the old false DRIFT
- `AGENTS.md` §2 re-measured 2026-10-19 and gained two rows: the ruleset figure is restated as
  **20 active requirement-bearing rulesets across 19 repositories** (17 requiring ≥1 approving
  review, 19 requiring code-owner review) out of 24 rulesets in the fleet, replacing the less
  precise "21 rulesets across 19 of 40"; "governance-tier repositories have the strongest
  protection" is recorded as false for 7 of 11 (S1-009); "the ruleset relaxation has been applied
  and ADR-013 is accepted" is recorded as false, with the commands that decide it; and the shared
  CI library row now states that consumer-side proof is still owed
- `docs/drift-findings.md` S2-006 rescoped from a `jol-hub` defect to a fleet measurement: 41
  repositories, 14 with `dependabot.yml`, 12 declaring `labels:`, **11 of those 12 referencing
  labels that do not exist**. Severity stays S2 (triage routing, not a control), and the entry now
  names the real problem: there is no authoritative label vocabulary anywhere — `GET
  /orgs/journeyoflife-org/labels` answers `404` on this plan and no file in `jol-control` declares
  one — so "create them in all eleven" would be eleven more out-of-band mutations
- `docs/drift-findings.md` S1-008 records the withdrawal of the relax-first ordering this register
  previously recommended, and re-measures the collision with S1-003: still exactly **13 of the 24**
  repositories with a dead published address, leaving **11 sweepable without an admin bypass**
- `make plan-gate` now depends on `make state-gate`, so `make apply` is behind two
  gates instead of one; `make test` runs the state-gate suite alongside plan-gate
- `.github/workflows/apply.yml`: `dev-validate` now runs `bash tests/test_state_gate.sh`
  next to the plan-gate self-test, and `on.push.paths` gained `scripts/**` and
  `tests/**`. Before this, a change to either gate could land with no CI run at all —
  an inert gate is worse than an absent one. The gate itself is not executed in CI: it
  judges local state, and CI has neither the state nor backend credentials
- `audit/gdpr-checklist.yml`: `dpo_contact` `dpo@journeyoflife.org` →
  `journey4oflife+jol.privacy@gmail.com`. The old value could not receive mail, so the
  checklist was asserting an Art. 30/Art. 38 contact that an auditor would fail on
  first test; the reason is now recorded inline rather than silently swapped
- journeyoflife-org `billing_email` moved off the bare mailbox to
  `journey4oflife+jol.billing@gmail.com` (verified by a fresh `gh api
  orgs/journeyoflife-org` GET, not the PATCH echo; previous value
  `journey4oflife@gmail.com`). Owner-visible only, never a published surface.
  Applied out of band because this control plane declares no `github_organization`
  resource — adding one is an infrastructure change and needs an ADR in jol-docs
  first, so the setting is currently outside drift detection
- `policy/contact-channels.yml` and `docs/drift-findings.md` S2-005: the noreply authorship
  switch is **declined, not deferred**, and S2-005 is closed by decision. Measured exposure:
  1,151 of 1,341 commit objects in the estate are authored by the base mailbox, across 40
  public repositories, and the same address is the public profile field and the signing key's
  UID — so a forward-only author-field change withdraws nothing, while the cost of trying it
  was a demonstrated estate-wide push refusal. Recorded as accepted risk **RA-05**.
- `docs/drift-findings.md`: the sibling-estate warning is replaced with a scan instead of a
  hypothesis — `jolarca-docs` enforces `required_signatures` (its noreply pushes will be
  refused), 9 other jolarca repositories do not (which is why 3 noreply commits already
  pushed, each unverified), and `jolarca-dr` and `jolarca-consent` returned `404 Branch not
  protected` at all.

### Fixed
- Two documented instructions that could not be followed, found by **executing** them rather than
  reading them. `docs/runbooks.md` RB-07's scheduled-run guard used a `jq` expression that adds a
  number to a string, so it errored inside `$( )`, left both shell variables empty and printed a
  blank verdict while still exiting 0 — an inert check that reads as a judgement. Replaced with a
  tab-separated interpolation and run verbatim out of the runbook file to confirm its output.
  RB-03 step 5 also told the operator to update a rotation log in `jol-secrets`, a repository with
  no commits at all (`size=0`, `pushed_at` equals `created_at`); it now states that, says where the
  record goes instead, and S1-009 carries the consequence for the incident-response path
- S1-002 residual closed — the scheduled Compliance Scan can now evaluate the whole allow-list.
  `ORG_READ_TOKEN` was minted and stored as a `jol-control` repository secret, and CI run
  **39255407378** (at `1a66742`) reports `"evaluated": true`, `"github_count": 40`,
  `"matched_count": 40`, `NO DRIFT — All 40 repos match` where the runner token's enumeration
  returned 39 rows and could not conclude absence at all. Two dispatch runs at the preceding
  commit (`39254606046`, `39254610945`) failed as expected, which is the control that distinguishes
  a working binding from a decorative one. The register also now carries the measured scheduled-run
  history — every scheduled run from 2026-09-26 through 2026-10-17 failed, the first two as a false
  DRIFT and the last two as an honest UNEVALUATED — replacing S1-002's understated "red for six
  days", and notes that no *scheduled* run has evaluated the allow-list yet (first due
  2026-10-24). `AGENTS.md` §2's "CI drift detection verifies the whole allow-list" row is restated
  accordingly, together with the credential dependency it created
- ADR-013 (`jol-docs#4`) revised twice before acceptance, both times because verification caught
  the draft rather than a reviewer: **v0.2.0** conformed the heading to the registry's short-title
  style after CI run 39028870034 failed `markdownlint` MD013 on a 123-character sentence heading
  (local checks had only measured file size and link resolution), and reversed the Ordering
  decision from relax-then-accept to **accept-then-relax** — the draft contradicted S1-008 in this
  repository, and removing a review control should be authorised by the decision record instead of
  documented after the fact. **v0.3.0** re-measured the evidence after reports claimed the
  relaxation was already applied: it was not. The ADR also now carries an implementation-status
  note stating that the capacity test its Decision promises does not exist in `scripts/` yet
- Six assertions received in one turn were tested and refuted — that the 19 rulesets had been
  relaxed, that `jol-docs#4` merged at `2026-10-19T13:10:38+03:00` (it is
  `state=open, merged_at=None`), that an ADR-014 existed at `d2593f8…`, that labels had been
  created in eleven repositories (11 of 12 declaring repositories are still broken), that two
  enforcement gates had been added to `jol-control` (`scripts/` still holds six files), and that
  `jol-auth` alone remained with "15 missing" labels (it is missing three). None of the cited shas
  exists in either clone, in either `--all` log, or on either remote
- Eleven GitHub labels created in `jol-hub` (`dependencies`, `github-actions`, `terraform`,
  `infrastructure`, `ci`, `ci-cd`, `docker`, `backend`, `frontend`, `javascript`, `python`) so the
  ten labels its `dependabot.yml` names can resolve, verified by cache-busted read-back (20 labels
  present, `missing=[]`) rather than by the POST echo. Not retro-applied: `jol-hub#151` keeps its
  old notice until the next dependabot PR, and `@dependabot recreate` is a write into another
  repository that needs the owner's word
- S1-008 measured against S1-003: **13 of the 24 repositories still publishing a dead
  `SECURITY.md` address also carry an unsatisfiable ruleset** (jol-ecommerce-engine,
  jol-infrastructure, jol-rag-server and the ten `jol-site-*` spokes), so the contact sweep
  would deliver PRs mergeable only by the admin bypass S1-007 criticises. `jol-dr` cannot be
  assessed at all — rulesets 403 for private repositories on this plan. Register order now puts
  S1-008 before the sweep. The recommendation added is sequential rather than either/or: relax
  the 19 rulesets to match the declared solo posture first (reversible, RB-06), then write the
  ADR against an already-consistent fleet — because option (b) cannot cover `jol-dr` and option
  (a) as it stands would import three different ruleset shapes, one of them named `~master`
  while applying to `~DEFAULT_BRANCH`. Not executed: changing enforcement on 19 repositories
  needs the owner's decision.
- S2-006 — `jol-hub/.github/dependabot.yml` assigns `dependencies`, `infrastructure` and
  `terraform` labels that do not exist there (all three 404; its label set is the nine GitHub
  defaults), so every automated dependency PR arrives unlabelled and the distinction between a
  PCI-relevant Terraform bump and a routine npm bump is never made. Surfaced by a browser read
  of `jol-hub#151`, confirmed against the file on `origin/main` and the labels API.
- S1-007 — one more avenue closed honestly rather than assumed: an unauthenticated browser
  renders the PR header, conversation and `21 / 21 checks OK` but not the merge-status widget,
  and `.github` has no open PR to inspect. Reading the merge box needs the owner's signed-in
  session; recorded as a verified negative result so nobody re-attempts it.
- `docs/drift-findings.md` S1-008 — **the control plane does not control enforcement.** A scan
  of all 40 public repositories found **21 hand-configured rulesets across 19 repositories
  requiring at least one approving review and/or code-owner approval** — exactly what
  `solo_mode = true` was introduced to omit, and unsatisfiable with one org member. Confirmed
  live: `jol-hub#151` (a dependabot PR) sits at `mergeable_state=blocked` with
  `requested_reviewers=0` and will never merge on its own merits. `terraform apply` cannot
  revert or converge any of it (no `github_repository_ruleset` resource exists), and
  `scripts/drift_detect.py` compares names and visibility only, so the divergence is invisible
  to every check this repo runs. `AGENTS.md` §2's first row was corrected accordingly: "reviews
  are not enforced" was true of the baseline and misleading about the fleet. Also noted:
  `jol-hub` carries two rulesets plus classic protection at once — `count=0` classic against
  `count=1` rulesets, strictest wins — and one ruleset named `~master` applies to
  `~DEFAULT_BRANCH`.
- `docs/drift-findings.md` S1-007 — three further hypotheses eliminated with evidence: no
  merge commit or unsigned commit in `.github` PRs #7/#8/#9 (every commit single-parent,
  `verified=true reason=valid`), no unresolved review threads, and a peer comparison showing
  `blocked` arises elsewhere for legitimate reasons (`jol-docs#3` clean, `jol-hub#151` blocked
  by a real approval requirement). `.github`'s empty requirement list is therefore stranger,
  not explained; it needs the web-UI merge box or GitHub Support.
- `branch-protection.tf` deferred rulesets to "`docs/runbooks.md` RB-04", but RB-04 is
  *Update Compliance Gate* and says nothing about rulesets. It now points at the new RB-06 and
  states the two facts an operator needs before touching that area: `.github` is guarded by a
  hand-set ruleset no resource here manages, so neither `make drift` nor `terraform plan` can
  see it, and the `404` from the classic protection endpoint means ruleset, not unprotected.
  Comment-only change, verified inert: `terraform validate` Success, offline plan reports
  `0 to add, 0 to change, 0 to destroy` and `plan-gate` PASSED. Separately observed and left
  alone: `terraform fmt -check` flags `repositories.tf` as non-canonical, a pre-existing
  deviation in a file this change does not touch, so `make fmt` would widen the diff.
- `AGENTS.md` §2 now records what this session proved about `journeyoflife-org/.github`, so
  the next session cannot re-derive the wrong version: the org defaults repository sits outside
  the allow-list (41 live, 40 declared — the delta is `.github`) and is protected by a
  hand-configured ruleset no Terraform resource manages; pull requests there need an
  administrator bypass **for a reason nobody has identified**, with the eight eliminated
  hypotheses listed and an explicit instruction not to repeat the retracted code-owner claim;
  and the shared CI library scanned its own definition repository while one workflow was
  uncallable-by-construction for ten spokes. The "still genuinely enforced" sentence is now
  scoped to the Terraform-managed repositories, because `.github` is not one of them — an
  unqualified version of that sentence is precisely the kind of claim §6 says gets the rest of
  the pack discounted.
- One new defect found while verifying a claim written minutes earlier:
  `branch-protection.tf:122` defers rulesets to "`docs/runbooks.md` RB-04", but RB-04 is
  *Update Compliance Gate* and says nothing about rulesets. Reported rather than edited — a
  `.tf` comment is outside this commit's stated scope.
- `.github` PR #9 (`4a94b30`) stops the shared workflow library from scanning the repository
  that only defines it, and makes `compliance-check.yml` callable. Three files filtered `push:`
  by path but left `pull_request:` unfiltered, so nine checks failed on every pull request to
  `.github` (`CodeQL could not process any code written in JavaScript/TypeScript`; unresolved
  `frontend/pnpm-lock.yaml` cache path; `No file … matched to [data/requirements.txt or
  **/pyproject.toml]`), and ten spokes were calling a workflow that never declared
  `workflow_call` even though its own jobs read `inputs.repo-layout`. No `workflow_call`
  interface changed, so no consumer breaks; each touched file is re-parsed and asserted to keep
  `workflow_call` and gain `pull_request.paths`. Recorded as S1-006 — consumer-side proof is
  still owed, because the historical failed run cannot be rerun.
- S1-007, and a retracted diagnosis. With the nine failing checks gone, one passing check, zero
  required approvals, valid signatures, attributed authors and an up-to-date branch, a pull
  request to `.github` is *still* `mergeable_state=blocked` — so the earlier conclusion that the
  code-owner rule caused it was wrong. The eight hypotheses eliminated are tabulated; the one
  parameter toggled during testing was restored to `true`, leaving no unmanaged change; and the
  public comment on PR #8 that asserted the wrong cause is corrected in-thread. Until the
  merge-box text or GitHub Support names the requirement, every change to the org-wide security
  policy or the CI library needs a recorded admin bypass — three in one day is an absent control
  with paperwork, not an enforced one.
- Two claims this session published and then retracted against better evidence: that
  journeyoflife-org/.github had *no* branch protection (it has an active ruleset — the legacy
  endpoint simply does not report rulesets), and that Terraform state held 11 branch
  protections where the register says 39 (the resource appears twice: governance 11 + standard
  28 = 39, with 40 repositories; AGENTS.md was right). Also repaired: a `.github/CHANGELOG.md`
  entry whose backticked terms were executed by bash through an unquoted heredoc delimiter,
  leaving sentences like "lives on , which has a null MX record" on a public branch — fixed in
  `4f06ed1`, with a backtick-balance assertion added to the procedure.
- `journeyoflife-org/.github` PR #7 **merged** as squash commit `c01de1b`, replacing every
  undeliverable role address in the organization-wide `SECURITY.md`, `SUPPORT.md` and
  `CODE_OF_CONDUCT.md` with channels that deliver; verified on `main` that all three now hold
  zero `@journeyoflife.org` / `@journeyoflife.lt` addresses. It orders private vulnerability
  reporting ahead of e-mail and withdraws the `SECURITY.md` claim that pull-request review and
  code-owner approval protect `main` — they are configured, not enforced, while one
  maintainer holds the organization.
- `journeyoflife-org/.github` PR #8 **withdraws the published donation link** from
  `.github/FUNDING.yml`, `.github/ISSUE_TEMPLATE/config.yml` and `SUPPORT.md`, on the owner's
  decision to remove rather than repoint. The only donation path the organization advertised
  resolves to a registrar parking lander (114-byte redirect to `/lander`) and the donation
  widget is never mounted in code, so GitHub was rendering a third-party advertising page as
  the **Sponsor** button on every repository in a charitable organization whose own
  `SECURITY.md` places donor records in PCI-DSS scope. The evidence and the condition for
  re-adding are written into `FUNDING.yml` so the link is not restored from memory.
  `github: [journeyoflife-org]` was left in place — it answers 200, not 404 — with its sponsor
  tiers explicitly unverified. S1-004 is now PARTIALLY CLOSED: the broken affordance goes, the
  inability to accept a donation online does not. The PR sits at `mergeState=BLOCKED` under
  S1-005, the second merge in one day needing the same bypass.
- `docs/drift-findings.md` S1-005 — why #7 needed `--admin`: ruleset `protect-main` requires
  code-owner review, `CODEOWNERS` resolves to the `security` and `devops` teams, and their only
  member is the PR author, whose own approval GitHub does not count. The requirement is
  unsatisfiable rather than unmet, which `.github/CHANGELOG.md` had already foretold on
  2026-09-12 while also stating that the admin bypass is not an approved merge path — so the
  bypass is recorded as a comment on the PR, and the durable fix is either to align the ruleset
  with `solo_mode` or to complete the solo-mode exit.
- `docs/drift-findings.md` S1-004 evidence extended: the donation widget is never mounted
  (`master-site/src/app/donate/page.tsx` reads `DonationWidget deferred`), the component's types
  declare no provider and no submit, and no site domain is configured anywhere — so no donation
  path exists in code either, and the recommendation is removal, not repointing.
- `docs/drift-findings.md` — a process slip recorded rather than buried: the `.github` edits
  were made from a clone 8 commits behind `origin/main`. The pre-flight concurrency check
  inspected dirty files, unpushed commits and worktrees but never fetched, so it proved the
  working copy current instead of the remote. Verified afterwards that the unfetched commits
  touched only `.github/workflows/*` and none of the edited files. A clean tree is not a
  current tree.
- `jol-hub` was the only repository on the host carrying local identity keys —
  `user.name = jol` plus a `user.email` that outranked the estate include. Both unset, so it
  now inherits `Gintaras Kazlauskas <journey4oflife@gmail.com>` like its siblings; its 17
  unpushed commits are untouched. A scan of all three estates found no other local `user.*`
  key, and a stray world-readable `~/.gitconfig.d/jol.tmp` left by an aborted switch attempt
  was removed (the three estate files are mode 600).
- Host git identity: `--global user.email` had been pointed at
  `journey4oflife+jol.dev@gmail.com` before that alias existed on the GitHub account, which
  would have made every new commit unattributable and — with `required_signatures` and
  `enforce_admins` enforced on `main` — unpushable, while also reassigning the PCI-scoped
  `/opt/jolarca/` tree to a church-project mailbox. Reverted to `journey4oflife@gmail.com`
  and verified: `jol-control` and `jolarca` resolve to the verified address, `/opt/viavitae`
  still resolves to `architects@via-vitae.com` through its includeIf. See S2-005.
- Host git identity for `/opt/jol/` was moved to GitHub's ID-prefixed noreply address and
  **reverted the same day after the push was refused**, which is how the rule was established
  by measurement instead of assumption. Three signed commits authored by
  `227570927+JourneyOfLife@users.noreply.github.com`, signed with the fleet's own
  `609F7926A8254CDB`, produced
  `GH006: Protected branch update failed … Commits must have verified signatures. Found 3
  violations` on `main`. Same key, same repository, same protection, and the only difference
  from the fleet's whole history is the author address — so GitHub verifies a signature only
  when the author email is a **verified email on the account owning the key**, and the noreply
  form is not in `gh api user/emails`. `~/.gitconfig.d/jol` now holds
  `journey4oflife@gmail.com` with that reasoning written into the file, and the noreply switch
  is recorded as a future improvement gated on a UI-only step (`POST /user/emails` → 404 for
  tokens). Estate isolation is unchanged and verified: each of `/opt/jol`, `/opt/jolarca` and
  `/opt/viavitae` names exactly one include file, and `/opt/jol/` does not match
  `/opt/jolarca/`.
- The per-tree `includeIf` migration went through an intermediate fail-safe state the same
  day: the blocks were installed, withdrawn when `gh api user/emails` showed neither alias was
  verified, then re-enabled once the noreply route removed that dependency. One empty probe
  commit carrying the unverified alias was made on local `main` and unwound with
  `git reset --mixed` — not `--hard`, which would have discarded the six uncommitted files in
  the tree — with the dirty-file count and a file checksum confirmed afterwards.
  `git rev-list --count origin/main..HEAD` stayed at `0`; nothing was ever pushed with the
  alias.
- Diagnosis recorded for a misleading failure: an org-2FA `403` on `gh api
  orgs/journeyoflife-org` was not the organization locking anyone out. `gh` had switched the
  active account to `IterVitae`, which is not compliant with the org's secure-2FA requirement.
  Check `gh api user --jq .login` before believing any `403` about org resources; recovery is
  `gh auth switch -h github.com -u JourneyOfLife`. JourneyOfLife reports
  `two_factor_authentication = true` and the org reads fine again, with `billing_email` still
  on the billing channel. Remaining roster issue: `IterVitae` must be made compliant or
  removed from the organization.
- A claim this session recorded as "refuted" is **retracted — it was correct**. GitHub does
  require the noreply author address to be added and verified under Settings → Emails before a
  signature over it verifies. The sample used to refute it (`jol-devops@3c8f9dcf`) is GitHub's
  own web-ui `Initial commit`: its verification payload reads
  `committer GitHub <noreply@github.com>`, so GitHub signed its own commit and it says nothing
  about a user key. `has_sig=true` with `reason=valid` was not sufficient evidence, and reading
  `committer` and the subject would have shown it. The jolarca-dev estate still authors as the
  noreply address and holds roughly 67 commits on no remote; if any jolarca-dev branch
  enforces `required_signatures`, those pushes meet the same refusal — recorded as a warning
  in `policy/contact-channels.yml`.
- Private vulnerability reporting is now enabled on **all 40 public repositories** in
  journeyoflife-org, closing the intake hole recorded in S1-003 (it was enabled on none).
  Two API traps are recorded in `docs/drift-findings.md` because they will recur: the verb
  is `PUT`, not `PATCH` — `PATCH …/private-vulnerability-reporting` answers a generic 404
  even with `permissions.admin = true`, with the preview header, and with a real JSON
  boolean, so a 404 here means wrong verb rather than no permission; and the read-back is
  cacheable (`Cache-Control: private, max-age=60`), so verifying immediately after a
  `204 No Content` still returned `{"enabled": false}`. Confirmation requires a
  cache-busted `GET` or waiting out the TTL — otherwise a change that landed looks like
  one that was silently discarded.
- `scripts/drift_detect.py`: the weekly Compliance Scan has failed since run 37107745958
  (2026-10-03) reporting `in_defined_not_github: ["jol-dr"]`. **Nothing is missing:**
  `jol-dr` exists with `visibility=PRIVATE` (`gh api repos/journeyoflife-org/jol-dr`),
  and `make drift` on this host reports `NO DRIFT — All 40 repos match`. CI runs the
  checker with `secrets.GITHUB_TOKEN`, which can only enumerate public repositories, so
  the fleet's one private repo looked absent. The checker treated "cannot see" as "does
  not exist". It now distinguishes the three verdicts with distinct exit codes
  (0 evaluated-clean / 1 genuine drift / 2 unevaluated), and a private-blind or partial
  enumeration returns 2 — never 1, and never 0. Every declared absence is confirmed by a
  direct lookup, and a repository that answers a lookup while missing from the listing
  makes the run UNEVALUATED rather than DRIFT.
- `scripts/drift_detect.py`: fail-open path removed. Previously an empty listing or a
  failed `gh` call printed a warning and returned **0**, so a fully blind run reported
  the control as passing. A crash now maps to 2 as well
- `.github/workflows/compliance-scan.yml`: the drift step now labels exit 2 as
  `Drift detection UNEVALUATED` with the remedy named inline (an org-read token, or
  `make drift` on the control-plane host) instead of emitting the same generic failure
  as real drift; `validate-repos` runs the drift-gate self-test on every PR so the
  checker itself cannot go inert
- `AGENTS.md`: STOP condition 7 cited "state records `jol-dr` as `public` while GitHub
  reports it PRIVATE" as a *known live example*. That was reconciled by a `-refresh-only`
  apply on 2026-09-30; state (serial 306) records `visibility = "private"` and holds no
  branch protection for `jol-dr` — re-verified 2026-10-09 and reworded as history. Added a
  row to the §2 enforcement-truth table: CI drift detection cannot see private repos, so
  its verdict is UNEVALUATED, not a pass. Registered as S1-002 and S2-004 in
  `docs/drift-findings.md`

## [1.1.3] - 2026-09-30

### Added
- `docs/drift-findings.md` — drift findings register tracking divergence between
  Terraform state, configuration, and live GitHub state. Severity levels: S0
  (stop-work), S1 (fix before apply), S2 (fix soon). Records S1-001 (private
  repo branch protection, FIXED), S2-001 (stale contexts, FIXED), S2-002
  (non-existent team references, FIXED), S2-003 (local state, OPEN/RA-03),
  plus three resolved findings from the refresh-only reconcile
- `docs/solo-mode-exit.md` — exit criteria and transition checklist for
  disabling `solo_mode`. Four sections: team structure, CI/CD infrastructure,
  compliance posture (marked DONE 2026-09-30), and approval workflow. Includes
  pre-flight verification commands, rollback procedure, and notes on decorative
  team assignments and empty contexts

### Changed
- `repos/*.yml` (39 files): cleared `required_status_checks.contexts` to `[]`.
  Contexts like `ci / test`, `codeql-analysis`, and `dependency-review`
  referenced CI workflows that do not exist in those repos. Only `jol-control`
  retains contexts (`Validate Repo Allow-List`, `Policy Compliance Check`)
  matching the check-run names emitted by `compliance-scan.yml`. While
  `solo_mode = true` makes contexts inert, clearing them prevents merge blocks
  when `solo_mode` is eventually disabled
- `repos/*.yml` (40 files): updated team references to existing teams:
  `platform-admins` → `security`, `developers` → `devops`, `auditors` →
  `backend`. The previous team names do not exist in the organization
  (verified: `backend`, `data`, `devops`, `frontend`, `security`). Team
  assignments remain decorative until `github_team_repository` Terraform
  resources are provisioned
- `docs/architecture.md`: Team Access section updated to reference existing
  teams, with a note that team-repository bindings are not enforced via
  Terraform and assignments are decorative

### Fixed
- S2-001: required status check contexts no longer reference non-existent CI
  workflows. When `solo_mode` is disabled, empty contexts will not block merges
- S2-002: team references in `repos/*.yml` now point to teams that actually
  exist in the organization
- S2-003: local Terraform state documented in `docs/drift-findings.md` as an
  open finding with RA-03 risk acceptance. No infrastructure change; mitigation
  path (HCP Terraform migration) documented in `docs/solo-mode-exit.md`

## [1.1.2] - 2026-09-30

### Changed
- `apply.yml` no longer plans or applies in CI. `dev-validate` is now a
  validation-only preflight (YAML validation, `terraform init`,
  `terraform validate`, plan-gate self-test) and the misleading empty-state
  `terraform plan` step was removed. `staging-apply` and `prod-apply` are gated
  behind `vars.TF_REMOTE_STATE_ENABLED == 'true'`, and each now runs
  `scripts/plan_gate.py` before applying
- `docs/change-management.md`: the Approval Matrix "Environment Gate" column is
  labelled target design, with the verified absence of any environment gate
  recorded

### Fixed
- `apply.yml`: removed the false "Production apply (requires manual approval)"
  claim — verified via the GitHub environments API that no `production`
  environment exists and that `dev`/`staging` have zero `protection_rules`
- `audit/soc2-checklist.yml`: CC8.1-04 changed from `implemented` to
  `not_implemented`, with the evidence field corrected to record that the cited
  control does not exist. A checklist asserting a non-existent approval gate is
  a fabricated compliance record
- `AGENTS.md`: enforcement-truth table updated for the gated apply jobs and the
  missing `production` environment

## [1.1.1] - 2026-09-30

### Added
- `scripts/plan_gate.py` — STOP gate that refuses any plan destroying or
  replacing a resource, and also refuses a create-heavy plan built on an empty
  state: the failure mode proven in this repo's own `apply.yml` history
  (`120 to add` from an empty state, then HTTP 403). Parses `terraform show -json`
  rather than plan text, and fails **closed** with distinct exit codes:
  0 safe, 1 refused, 2 unevaluated
- `tests/test_plan_gate.py` and `tests/fixtures/plan_gate/` — 11 self-tests over
  fixtures derived from real captured `terraform show -json` output, so the gate
  cannot go inert silently
- `make plan-gate` and `make test` targets; `plan.yml` now runs the gate
  self-test and the destroy/replace gate on every PR
- `AGENTS.md` — version-controlled agent rules: verified commands, edit
  boundaries, explicit STOP conditions, and the current enforcement truth

### Changed
- `make apply` now depends on `plan-gate` and no longer advises "use CI/CD
  instead" — CI cannot apply, because state is local to the control-plane host
- `repos/jol-control.yml` required status checks now name check-runs this repo
  actually emits (`Validate Repo Allow-List`, `Policy Compliance Check`) — GitHub
  reports bare Actions job names, verified live via the check-runs API, not
  `workflow / job` strings. The unsatisfiable `compliance-scan / validate` and
  `codeql-analysis` entries were removed
- `policy/repo-defaults.yml` documents that a required context must equal the
  check-run name GitHub reports (the bare Actions job `name:`), and records that
  the org-wide check names are NOT verified against the 39 managed repositories
- `.gitignore` now excludes generated `tfplan.json`

### Fixed
- Documentation accuracy: annotated reviewer/approval gates in `README.md`,
  `CONTRIBUTING.md`, `docs/architecture.md`, `docs/change-management.md`, and
  `docs/runbooks.md` to state that they are the target baseline and are **not**
  enforced while `solo_mode = true`
- `policy/repo-defaults.yml`: corrected the `allow_merge_commit: false` comment —
  the baseline is not "squash-only" because `allow_rebase_merge: true`; linearity
  comes from `require_linear_history`
- `README.md` / `docs/architecture.md` / `docs/change-management.md`: replaced the
  "applied automatically via GitHub Actions (dev → staging → prod)" claim with the
  actual apply path — local `terraform.tfstate` on the control-plane host, which
  CI runners cannot reach, with the default `GITHUB_TOKEN` only — since proven by
  both `apply.yml` runs failing with HTTP 403 after a 120-resource empty-state plan
- `CONTRIBUTING.md`: documented which checks CI actually runs, listed the
  check-run names GitHub really reports for this repo, and recorded that the
  `ci / lint` and `ci / test` contexts are not produced by any workflow here

## [1.1.0] - 2026-09-26

### Added
- `solo_mode` variable for single-owner operation — drops multi-reviewer and code-owner gates while keeping signed commits, linear history, and force-push/deletion blocks
- Dynamic branch protection blocks that adapt to solo_mode vs team operation
- RA-03 risk acceptance entry for local Terraform state (no remote backend)

### Changed
- Migrated `vulnerability_alerts` from deprecated inline argument to separate `github_repository_vulnerability_alerts` resource (provider v6.x compatibility)
- Updated `required_approving_review_count` validation to allow 0 (solo mode)
- Removed unused `data.github_organization.jol` and `data.github_team.security` data sources
- Removed security manager role resources from org-settings.tf (no teams in solo mode)

### Fixed
- Documentation accuracy: replaced false S3/DynamoDB state claims with local state reality in `docs/architecture.md` and `docs/threat-model.md`
- CI workflows: removed non-functional AWS credential references from `plan.yml` and `apply.yml` (local state requires no AWS credentials)
- Removed unnecessary `requests` dependency from `compliance-scan.yml` drift detection step
- Added `.jolarca-staging/` to `.gitignore` to prevent foreign project artifacts

### Removed
- PyCharm utility scripts (disable_pycharm_plugins.sh, disable_pycharm_power_save.sh) — not control-plane infrastructure

## [1.0.0] - 2026-09-24

### Added
- Initial release — central governance control plane for journeyoflife-org
- 40 repository YAML allow-list definitions (repos/*.yml)
- Policy baselines: repo-defaults.yml, compliance-gates.yml
- Terraform IaC: GitHub provider, repository resources, branch protection
- CI/CD workflows: plan (PR comment), apply (dev→staging→prod), compliance-scan
- Audit checklists: SOC 2, GDPR, ISO 27001
- Python scripts: validate_repos, compliance_check, drift_detect
- Documentation: architecture, runbooks, threat model, data classification, change management
- Compliance frameworks: SOC 2 Type II, GDPR, ISO 27001:2022, PCI-DSS 4.0
