# Drift Findings Register

This register tracks drift between Terraform state, configuration, and live GitHub state.

**Priority:** S0 (Stop-Work) > S1 (Fix Before Apply) > S2 (Fix Soon)

**Index.** Entries stay in the order they were discovered, because each carries the evidence
timestamp and the corrections applied to it at the time; numbers never change once other
documents cite them. In numeric order:

| ID | Subject | Status |
|---|---|---|
| S1-001 | Private repos cannot have branch protection without GitHub Pro | fixed |
| S1-002 | Drift detection reported "cannot see" as "does not exist", and a blind run as passing | checker fixed; CI still cannot evaluate |
| S1-003 | Every published contact address in the fleet is undeliverable | open; intake and org defaults fixed, 24 repos to sweep |
| S1-004 | The published donation path is a domain-parking lander | partially closed; affordance removed, capability absent |
| S1-005 | `.github` code-owner review unsatisfiable — diagnosis later overtaken | superseded by S1-007 |
| S1-006 | Shared workflow library scanned its own definition repo; one workflow uncallable | fixed; consumer proof owed |
| S1-007 | `.github` PRs report `blocked` with nothing left to satisfy | open; escalated, needs merge box or Support |
| S1-008 | Hand-set rulesets re-impose the review controls `solo_mode` removed, 19 of 40 repos | open; invisible to Terraform and drift |
| S2-001 | Required status check contexts do not match reality | fixed |
| S2-002 | Teams referenced in config do not exist | fixed (bindings still decorative) |
| S2-003 | State is local, not remote | open, RA-03 accepted |
| S2-004 | AGENTS.md cited a resolved state mismatch as current truth | fixed |
| S2-005 | Git identity migration: authorship needs a verified account email | closed by decision |
| S2-006 | Dependabot labels referenced by jol-hub do not exist | open |

Two undated sections are folded in where they arose: *Measurement traps* (how three readings
here went wrong) and *Process slip* (an edit made from a stale clone).

---

## S0 — Stop-Work / Critical

*None currently.*

---

## S1 — Fix Before Apply / BLOCKING

### S1-001: Private repos cannot have branch protection without GitHub Pro

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** `jol-dr` is private, but config declared `tier: governance` which requires branch protection. GitHub API returns 403 for branch protection on private repos without GitHub Pro.  
**Impact:** Apply would fail with 403 when trying to create branch protection for jol-dr.  
**Resolution:** Modified `branch-protection.tf` to exclude private repos from `governance_repos` and `standard_repos` locals.  
**Files changed:** `branch-protection.tf`

### S1-002: Drift detection reported "cannot see" as "does not exist", and a blind run as passing

**Discovered:** 2026-10-09  
**Status:** FIXED (checker) — residual OPEN: CI still cannot evaluate, see remediation  
**Finding:** The scheduled Compliance Scan failed from run 37107745958 (2026-10-03) with
`in_defined_not_github: ["jol-dr"]`. Nothing was missing. `gh api
repos/journeyoflife-org/jol-dr` returns `visibility=PRIVATE`, `gh repo list
journeyoflife-org --limit 500` on this host returns 41 rows (40 managed + `.github`), and
`make drift` reported `NO DRIFT — All 40 repos match`. CI runs the same script with
`secrets.GITHUB_TOKEN`, which enumerates only public repositories, so the fleet's single
private repository was absent from its view and the checker concluded absence from
ignorance. Worse than the false alarm: the same script returned **exit 0** whenever the
listing came back empty or `gh` failed outright, so a fully blind run reported the control
as passing — a fabricated compliance record, not a missing one.  
**Impact:** A weekly control that was red for six days for the wrong reason, and that could
have been green for no reason at all. Any genuine absence (a deleted or never-created repo)
produced byte-identical output to a permissions artefact, so the control could neither warn
reliably nor pass honestly.  
**Resolution:** `scripts/drift_detect.py` now emits three verdicts with distinct exit codes
— 0 evaluated-and-clean, 1 genuine drift, 2 unevaluated. A private-blind or truncated
enumeration, an empty listing, a failed `gh` call, an unreadable allow-list, and an internal
crash all map to 2. Each declared absence is confirmed by a direct `gh api` lookup, and a
repository that answers a lookup while missing from the listing makes the run UNEVALUATED
rather than DRIFT. `compliance-scan.yml` annotates exit 2 as `Drift detection UNEVALUATED`
with the remedy inline, and `validate-repos` runs the new 11-test self-test on every PR.  
**Evidence:** `tests/fixtures/drift_detect/live_host_user_token.json` (real capture, 41 rows,
one PRIVATE) and `ci_github_actions_token.json` (the Actions-token view, 39 rows, no private
visible) — `python3 tests/test_drift_gate.py` → `PASSED — 11 drift-gate tests, 0 failures.`  
**Residual and remediation:** the scheduled job remains UNEVALUATED until it gets a token
that can read the organization. Minimum-scope option: a fine-grained PAT with
*Organization → Members: Read* and repository read access restricted to the org, stored as
`secrets.ORG_READ_TOKEN`, referenced by the drift step in place of `secrets.GITHUB_TOKEN`.
Alternative: run drift on this host (where such a credential already exists) and ship the
JSON report. Until one of those is in place, no CI run of this control may be cited as
evidence that the allow-list matches the organization.  
**Files affected:** `scripts/drift_detect.py`, `tests/test_drift_gate.py`,
`tests/fixtures/drift_detect/`, `.github/workflows/compliance-scan.yml`, `Makefile`

### S1-003: Every published contact address in the fleet is undeliverable — the domains take no mail

**Discovered:** 2026-10-15  
**Status:** OPEN — contact sweep in progress. **Vulnerability intake FIXED**
(private vulnerability reporting enabled on 40/40 public repositories, 2026-10-15).
**Org defaults MERGED** — journeyoflife-org/.github PR #7, squash commit `c01de1b`,
rewriting `SECURITY.md`, `SUPPORT.md` and `CODE_OF_CONDUCT.md`; verified on `main`
that all three now contain **0** `@journeyoflife.org` / `@journeyoflife.lt` addresses.
The merge needed an administrator bypass — see S1-005. Queue is the **24 repositories
that ship their own `SECURITY.md`** with a dead address, because a repository file
overrides the default. `jol-auth` is excluded from this pass: another session holds it
on `remediation/batch-0-s1` with 39 uncommitted files.  
**Finding:** Not state drift but the same class of defect as S2-002: configuration and
documentation assert things that do not exist. 74 files across 27 repositories publish
role mailboxes on three domains, and DNS says none of them can receive mail:

```
journeyoflife.org   dig MX → "0 ."            RFC 7505 null MX: the domain explicitly
                                              disavows mail. NS = ns3/ns4.afternic.com,
                                              i.e. a parked domain listed for sale.
                  112 occurrences (9 are placeholders, 103 are real contact claims)
                  roles: security(61) dpo(6) noreply(5) engineering(5) conduct(5)
                       privacy(4) platform(4) ops(3) ciso(3) dev(2) compliance(2)
                       alertmanager(2) admin(2) infra(1) incident(1) errors(1) api(1)
journeyoflife.eu    no MX at all. NS = horizon/orbit.dns-parking.com (parked). This is
                  the product domain; 0 mail contacts published on it today.
journeyoflife.lt    no NS records; the domain does not resolve. 5 occurrences, all in
                  jol-core (SECURITY.md ×4 → security@, CODE_OF_CONDUCT.md ×1 → conduct@)
```

**Impact:** Three separate failures, all silent. (1) 28 repositories ship a `SECURITY.md`
instructing a vulnerability researcher to mail `security@journeyoflife.org`; that message
is rejected at SMTP time. The fallback was not switched on either — at discovery **0 of
the 40 public repositories had private vulnerability reporting enabled** (verified
2026-10-15: `gh api repos/journeyoflife-org/<repo>/private-vulnerability-reporting` →
`{"enabled":false}` for all 40; the endpoint 404s on the private `jol-dr`, which is
expected since it is only offered for public repositories). So the organization had **no
working intake channel for vulnerability reports at all**, and the 90-day disclosure clock
ran against a path that never delivered anything. That half is now closed (see remediation
(a)). (2) The GDPR DPO and
data-subject contact (`dpo@`, `privacy@`) is unreachable, which makes Art. 30(1)(a) and
Art. 38(1)(a) records assert a control that cannot be exercised — an auditor who tests it
fails it, and per AGENTS.md §6 that discounts the rest of the evidence pack. (3) 
`jol-devops/monitoring/alertmanager/alertmanager.yaml` configures an email receiver on the
same dead domain, and its relay host does not exist either: `smtp.journeyoflife.org`
resolves to `13.248.169.48` / `76.223.54.146` — the *same* AWS Global Accelerator parking
addresses as the `journeyoflife.org` apex, i.e. a domain-parking web service, not an SMTP
server on port 587. Corrected wording, because the first draft of this entry overstated it:
alerting is **not** "firing into a null MX" on this host — no Alertmanager is running here
at all (`ss -ltn` shows no `:9093`; the `jol-prometheus` container mounts only
`prometheus.yml` and a data volume, with no Alertmanager process or config). Whether it
runs on another host is **not verified from this machine**. The defensible statement is
that the receiver as written can never deliver anywhere it runs, and that this repository's
evidence pack does not claim an operational paging control (`audit/*.yml` reference
Dependabot and vulnerability alerts, which are GitHub features, not alerting) — so this is
an unbuilt control with an impossible config, not a broken running one. Either way it must
not be cited as incident-detection evidence until it is deployed and a test alert is
observed arriving.  
**Interim resolution (this repository):** `audit/gdpr-checklist.yml` `dpo_contact`
corrected from the dead `dpo@journeyoflife.org` to the reachable privacy channel, with
the reason recorded inline. `policy/contact-channels.yml` added as the single authority
for which role address goes where: admin-plane channels (billing, github, dev) stay
GitHub-internal and are never published, public-plane channels (security, privacy) may
be. `docs/threat-model.md` gained T-13 and risk acceptance RA-04 stating the trade-off:
a plus-addressed alias discloses the base mailbox, but the base mailbox is already
public on the GitHub profile and is the author of every commit in the fleet, so the
marginal loss is small against the gain of an address that actually receives mail.  
**Remediation path:** (a) **DONE 2026-10-15** — private vulnerability reporting enabled on
all 40 public repositories, each confirmed by an independent read-back. Two traps cost a
round of blind retries, and they belong in this register because they will recur:
  - the verb is **`PUT`**, not `PATCH`. `PATCH …/private-vulnerability-reporting` returns
    `404 {"message":"Not Found"}` even with `permissions.admin = true`, with preview
    headers, and with a real JSON boolean — GitHub answers 404 for an unmatched route on
    this endpoint instead of 405. A 404 here means *wrong verb*, not *no permission*, and
    the generic body gives no hint.
  - the read-back is **cacheable**. `GET …/private-vulnerability-reporting` immediately
    after a `204 No Content` still returned `{"enabled":false}` because GitHub serves
    `Cache-Control: private, max-age=60`. A verification run has to be cache-busted (append
    an unknown query parameter) or wait out the TTL, otherwise a change that landed looks
    like a change that was silently discarded — which is the exact failure shape of the
    `two_factor_requirement_enabled` write in this organization's history.
(b) stand up MX + SPF on
`journeyoflife.eu` and publish real `security@`, `privacy@`, `billing@`, `dpo@` mailboxes
there; (c) sweep the 26
remaining repositories from `policy/contact-channels.yml`, one signed-commit PR per
repository; (d) treat `jol-devops` alerting as **unbuilt, not broken**: pick a real relay,
point the receiver at the security channel, deploy it, and prove it with a test alert that
is observed arriving — until then no control may cite alerting; (e) stop citing any
contact-dependent control as `implemented` until the address is
re-tested. Do **not** edit the historical artifacts listed in
`policy/contact-channels.yml → contact_surface_rules.evidence_artifacts_are_immutable`; (f)
**the git-identity half of the migration is blocked and cannot be automated** — see S2-005.  
**Evidence:** `dig +noall +answer MX journeyoflife.org` → `journeyoflife.org. 3584 IN MX 0 .`;
`dig +short NS journeyoflife.org` → `ns3.afternic.com. ns4.afternic.com.`;
`dig +short MX journeyoflife.eu` → empty with `dig +short NS journeyoflife.eu` →
`horizon.dns-parking.com. orbit.dns-parking.com.`; `dig +short NS journeyoflife.lt` →
empty. `gh api orgs/journeyoflife-org` → `billing_email=journey4oflife@gmail.com`,
`email=null`; `gh api user/emails` → one entry, `primary=true`, `verified=true`,
`visibility=public`; `gh api repos/journeyoflife-org/jol-core --jq .billing_email` → null
and null for all 41 repos, so repository-level billing is not in use.
Post-remediation evidence for (a), reproducible:
`for r in $(gh api "orgs/journeyoflife-org/repos?per_page=100"
--jq '.[]|select(.visibility=="public")|.name'); do printf "%s %s\n" "$r"
"$(gh api "repos/journeyoflife-org/$r/private-vulnerability-reporting?cb=$RANDOM"
--jq .enabled)"; done` → 40 lines, all `true`, no `false`.
Occurrence counts from `grep -rEho "[A-Za-z0-9._%+-]+@journeyoflife\.(org|eu|lt)"
/opt/jol/repos` excluding generated scanner output and staging copies, 2026-10-15.  
**Files affected:** `audit/gdpr-checklist.yml`, `policy/contact-channels.yml` (new),
`docs/threat-model.md`, `docs/drift-findings.md`

### S1-004: The published donation path is a domain-parking lander, and no donation endpoint exists anywhere in the fleet

**Discovered:** 2026-10-15  
**Status:** PARTIALLY CLOSED — the defective published affordance is being removed
(`.github` PR #8, opened 2026-10-15, `mergeState=BLOCKED` by S1-005). The underlying
capability gap **remains open**: the organization still cannot accept a donation online.
Those are different findings and only the first is a governance defect.  
**Finding:** Three public surfaces advertise `https://journeyoflife.org/donate` as the way to
support the mission: `.github/SUPPORT.md`, `.github/FUNDING.yml` (which GitHub renders as the
organization's funding link on every repository) and
`.github/ISSUE_TEMPLATE/config.yml`. The domain does not host the project:

```
curl https://journeyoflife.org/donate  -> 200, content-type text/html, 114 bytes:
  <!DOCTYPE html><html><head><script>window.onload=function(){window.location.href="/lander"}</script></head></html>
curl https://journeyoflife.eu/         -> <title>Parked Domain name on Hostinger DNS system
dig NS journeyoflife.org               -> ns3.afternic.com / ns4.afternic.com   (registrar parking)
dig MX journeyoflife.org               -> "0 ."                                  (null MX, RFC 7505)
```

A search of every repository under `/opt/jol/repos` for a real payment or donation endpoint
(donorbox, buy-me-a-coffee, stripe pay links, paypal donate, librepay) returned **only**
third-party notices inside `node_modules/` and `.venv/` metadata — no organization donation
URL exists. So the link was never wired to anything, and both candidate domains are parked.
**Impact:** donation intake is broken while being advertised, and donors who follow it land on
a parking page that serves third-party advertising and links **under the organization's own
name and path** — a phishing surface the organization does not control and cannot audit. For a
charitable mission platform handling donor records described in its own `SECURITY.md` as
PCI-DSS in scope, publishing a redirect into an uncontrolled ad lander is a reputational and
fraud-exposure finding, not a cosmetic one. It also contradicts the `SUPPORT.md` framing that
support is best-effort but the mission is real: a reporter or donor following a published link
gets a page for sale.  
**Why this was not fixed in the sweep:** inventing a replacement URL in a public file is worse
than leaving a known-broken one. The correct destination — a hosted donate page, a payment
provider URL, or removal of the link from `FUNDING.yml` until one exists — is an owner and
finance decision.  
**Remediation, and what was decided:** the owner authorized **removal** on 2026-10-15, executed
in journeyoflife-org/.github PR #8 — the `custom:` entry is deleted from
`.github/FUNDING.yml` with the evidence and the re-add condition written into the file, the
"Support the mission" contact link is removed from `.github/ISSUE_TEMPLATE/config.yml`
(three contact links remain, YAML re-validated), and the `SUPPORT.md` row now states plainly
that no online donation channel is published. `github: [journeyoflife-org]` was deliberately
left untouched: it answers 200 rather than 404, and whether it presents real sponsor tiers was
**not** verified, since GitHub serves a page shell either way. When a genuine endpoint exists,
change all three files together so the Sponsor button, the support table and the issue-form
sidebar cannot disagree, and re-fetch the target to prove it returns the intended page rather
than a redirect.  
**Evidence that no donation path exists in code either (added same day):**
`jol-hub/frontend/apps/master-site/src/app/donate/page.tsx:5` carries the comment
`/* DonationWidget deferred — requires I18nProvider from [locale]/ layout */` and renders
only an `<h1>Paramos forma</h1>` — the route exists, the widget is never mounted.
`packages/ui/src/components/composite/donation-widget/DonationWidget.types.ts:8` declares
only `onConfigure?: (selection) => void`: no provider, no submit, no form action.
`master-site/.env.local` configures a Bitrix placeholder and no site domain, and
`jol-infrastructure/.staging/fix-master-donate{,2}.py` removed a no-op `onConfigure` — the
signature of a widget dressed up as implemented. **So the recommendation is to remove the
donate reference, not repoint it**: `journeyoflife.eu` is parked too, which would trade one
parking page for another. GitHub renders the parked URL as the organization's Sponsor button
on every repository, and for a charitable platform advertising a donation path that collects
nothing is worse than publishing none.  
**Evidence:** `curl -s -L https://journeyoflife.org/donate`, `curl -s -L https://journeyoflife.eu/`,
`dig +short NS/MX journeyoflife.org`, `grep` across `/opt/jol/repos` for payment-provider URL
shapes (hits confined to vendored dependency metadata).  
**Files affected:** `.github/SUPPORT.md`, `.github/FUNDING.yml`,
`.github/ISSUE_TEMPLATE/config.yml` (all in `journeyoflife-org/.github`)

### Measurement traps found while verifying S1-003 and S1-004

Two of my own readings were wrong; both are recorded so the next operator does not repeat
them, and neither changed the enforcement state of anything.

1. **A `404 Branch not protected` does not mean unprotected.**
   `GET /repos/journeyoflife-org/.github/branches/main/protection` returns 404, which reads as
   "this repository has no protection". It does: an **active ruleset** named `protect-main`
   (id 22978013) enforces `required_signatures`, `required_linear_history`, `deletion`,
   `non_fast_forward`, `update`, and a `pull_request` rule with
   `require_code_owner_review: true`, thread resolution and squash-only merges, with
   `required_approving_review_count: 0`. Rulesets and legacy branch protection are separate
   APIs and each is blind to the other, so the fleet must be audited through
   `GET /repos/{owner}/{repo}/rulesets` as well as `…/branches/{branch}/protection`. The same
   ruleset carries `bypass_actors: [{actor_type: RepositoryRole, actor_id: 5 (admin),
   bypass_mode: always}]` and `current_user_can_bypass: always` — the single member bypasses
   every rule, which is exactly the limitation `/.github/CHANGELOG.md` already declared on
   2026-09-12.
2. **Count state per resource, not per first match.** An earlier message from this session
   claimed 11 branch protections in state against a documented 39. Wrong, and retracted: the
   `github_branch_protection` resource appears **twice** (`governance` = 11 instances,
   `standard` = 28), total **39**, with 40 `github_repository` instances — consistent with
   S1-001 excluding the private repo. `AGENTS.md` was right; the number in this register was
   never in error. A loop that prints one summary line per matching entry and is read as a
   single total produces this mistake.
3. **Never feed text containing backticks through an unquoted heredoc.** Writing the
   `.github/CHANGELOG.md` entry with `<<PY` instead of `<<'PY'` let bash execute every
   `` `code span` `` as a command substitution: the pushed entry lost all file names and
   domains and read "lives on , which has a null MX record (, RFC 7505)". Detected by reading
   the file after the write rather than trusting the "inserted" message; repaired in commit
   `4f06ed1` on the PR branch. Any generator that writes markdown must use a quoted delimiter
   and then assert backtick balance and the presence of expected literals.
4. **Correlation is not the merge blocker.** Nine failing checks were present whenever a
   merge was blocked, so the checks looked like the cause — and the first draft of
   `S1-005` said so in a public PR comment. Removing the failures left the block intact.
   `mergeable_state=blocked` names a *review* deficiency, not a check failure, and
   `allowed_merge_methods` / `update` parameters matter more than the presence of red
   checks. Read the enum's meaning before writing a cause into a merge comment.
5. **A reusable workflow's own `push`/`pull_request` triggers do not apply to callers**, so
   filtering them in the library is safe for consumers — but a self-referential path entry
   (`- '.github/workflows/security-scan.yml'`) makes the library re-scan the definition repo
   whenever the library itself is edited, which is precisely the failure being fixed.
6. **A confident report that an action was taken is not a measurement.** This session received
   assertions that the 19 rulesets had been relaxed, that `jol-docs#4` had merged at
   `2026-10-19T13:10:38+03:00`, that an ADR-014 existed (sha `d2593f8…`), that labels had been
   created across eleven repositories, that two enforcement gates had been added, and that
   `dependabot.yml` label work was done except for `jol-auth` "15 missing". Re-checked against
   the live API, every one was false — and the shas do not exist as objects in either clone, in
   either repo's `--all` log, or on either remote (`gh api repos/…/git/commits/<sha>` → 404).
   The cheapest decisive tests were `gh pr view --json state,mergedAt`, `git cat-file -t`, and
   re-running the scan. Treat an upstream report as a hypothesis that costs four commands to
   confirm; acting on it as fact would have marked S1-008 closed while 19 repositories still
   demanded an approval nobody can give.
7. **`curl` with a `Bearer` token against `github.com` HTML is not a token-scope test.** A GET
   of `https://github.com/journeyoflife-org/jol-dr` returns `404` both anonymously and with the
   `gh` token, while `gh api repos/journeyoflife-org/jol-dr` returns the repository with
   `private=true`. Proven: the HTML probe cannot discriminate scope. Inferred (labelled as
   inference): GitHub's HTML endpoints authenticate by session cookie, so lychee's token may or
   may not be applied to `github.com` URLs depending on its sender configuration — which is also
   why the same link passed link-check on 2026-10-13 and fails on 2026-10-17, an interval this
   register cannot yet explain.
8. **A workflow run whose name matches a reusable workflow is not proof that a caller resolved
   it.** `jol-docs` shows a green `compliance-check` run dated 2026-10-17, which looks exactly
   like consumer-side proof that `workflow_call` now works. It is not: that file is `jol-docs`'
   own `.github/workflows/compliance-check.yml` defining the job "Document control & ADR/RoPA
   coverage", and `grep -rn 'journeyoflife-org/.github/.github/workflows'` finds no library call
   in `jol-docs` or `jol-hub`. The ten real spokes have not run CI since 2026-09-22.

### S1-005: .github's ruleset requires a code-owner review that a single-member organization cannot give

**Discovered:** 2026-10-15  
**Status:** OPEN — worked around by recorded admin bypass. **The diagnosis in this entry
was overtaken by evidence: the code-owner rule was not what blocked the merge.** See
S1-006 and S1-007; the parameter is retained as changed (it was a real defect) but it did
not restore a non-bypass merge path.  
**Finding:** `journeyoflife-org/.github` `main` is guarded by ruleset `protect-main`
(id 22978013) with `require_code_owner_review: true`, while this repository's
`CODEOWNERS` resolves `*` to `@journeyoflife-org/security @journeyoflife-org/devops` and
`/SECURITY.md` to `@journeyoflife-org/security`. Both teams exist, and their only member
is the account that authors the change. GitHub does not accept the author's own approval
as code-owner review, so with one member the requirement is **unsatisfiable**, not merely
unmet: `gh pr merge` returns *"the base branch policy prohibits the merge"* no matter what
the PR contains. PR #7 (the contact-channel fix) could only land with `--admin`.
`.github/CHANGELOG.md` predicted this on 2026-09-12 — *"Code-owner review is declarative,
not substantive… A second identity must be invited to the organization and added to the
`security` and `devops` teams before this control can be evidenced"* — and the same entry
states *"The bypass is not an approved merge path."* The second identity exists
(`IterVitae`) but is refused by the organization's secure-2FA requirement, so the deadlock
is total.  
**Impact:** every future change to the organization-wide security, support and conduct
documents requires a recorded policy bypass, which is the shape of an audit finding: a
control that is asserted, cannot be satisfied, and is routinely overridden. Note the
contrast — Terraform-managed repositories run `solo_mode = true` and omit review
requirements entirely, so only this hand-configured ruleset is stricter than the
declared posture, and it is not managed by any IaC in `jol-control`.  
**Remediation, pick one (both are owner decisions):**
(a) align the ruleset with `solo_mode` — set `require_code_owner_review` false and keep
`required_signatures`, `required_linear_history`, `deletion`, `non_fast_forward` and
squash-only; or (b) make the control real — invite a second identity, bring it into
compliance with the org's 2FA requirement, add it to `security` and `devops`, and stop
bypassing. Option (b) is the solo-mode exit documented in `docs/solo-mode-exit.md`. In
either case the ruleset should end up declared in Terraform rather than hand-set, so drift
detection can see it.  
**Evidence:** `gh api repos/journeyoflife-org/.github/rulesets/22978013 --jq '.rules[]'`;
`git show HEAD:.github/CODEOWNERS`; `gh api orgs/journeyoflife-org/teams`;
`gh api orgs/journeyoflife-org/memberships/JourneyOfLife` → `admin, active`;
`gh pr view 7` → `state=MERGED mergedAt=2026-10-15T17:55:31Z mergeCommit=c01de1b`;
bypass recorded as a comment on PR #7.  
**Files affected:** `journeyoflife-org/.github` ruleset (out of band, not in Terraform)

### S1-008: Hand-set rulesets re-impose the review controls `solo_mode` removed, on 19 of 40 repositories

**Discovered:** 2026-10-16  
**Status:** OPEN — the declared baseline and the enforced state diverge silently. **Decision
drafted as ADR-013 (`Proposed`, open as `jol-docs#4`, still unmerged as of 2026-10-19); no
enforcement changed yet.** Re-measured 2026-10-19: unchanged in substance — see the paragraph
below.  
**Finding:** `solo_mode = true` exists precisely so this organization can operate with one
member: `branch-protection.tf:39,53` omit `required_pull_request_reviews` entirely, and
AGENTS.md §2 states that reviewers and CODEOWNERS are not enforced. That is true of the
Terraform-managed **classic** protection — and separately contradicted by hand-configured
**rulesets** on nearly half the fleet. Scanning all 40 public repositories: **21 rulesets
across 19 repositories require at least one approving review, code-owner approval, or both.**

| repository | ruleset | approving reviews | code owner |
|---|---|---|---|
| jol-compliance | `Protect main branch` / `protect-main` | 1 / 1 | false / **true** |
| jol-hub | `protect-main` / `~master` | 1 / 1 | **true** / false |
| jol-domain-taxonomy, jol-ecommerce-engine, jol-hermes-agents, jol-llm, jol-rag-server | `protect-main` | 1 | true |
| jol-site-basilica, -cathedral, -cemetery-care, -deanery, -diocese, -funeral, -orthodox, -other-church, -parish, -protestant | `protect-main` | 1 | true |
| jol-deploy, jol-infrastructure | `protect-main` | 0 | true |

Neither mechanism can satisfy these: the sole org member cannot approve their own change, and
no second member exists. Confirmed live on **jol-hub#151**, a dependabot PR sitting at
`mergeable=true, mergeable_state=blocked` with `commits=1, requested_reviewers=0` — it will
stay blocked forever. Two further details: jol-hub carries **two** rulesets plus classic
protection simultaneously, and its classic protection says `count=0` while the rulesets say
`1`, so the strictest silently wins; and one ruleset is named `~master` while its include
pattern is `~DEFAULT_BRANCH`, which reads like a ref pattern typed into the name field.

**Why Terraform cannot fix this:** there is no `github_repository_ruleset` resource in this
baseline — `branch-protection.tf` says rulesets are deliberately deferred — so `terraform
apply` will neither revert nor converge them, and `scripts/drift_detect.py` compares repository
names and visibility only. The divergence is therefore permanent and invisible to every check
this repository currently runs, which is the definition of an ungoverned control surface.
**Consequence for the evidence pack:** any statement of the form "reviews are not enforced
because we run in solo mode" is now incomplete: as enforced, **approvals are required on 19
repositories and nobody can give them**, so the real merge path across half the fleet is an
administrator bypass. That is worse than either extreme — a control nobody can satisfy is not
an enforced control, it is an undocumented exception.
**Remediation:** decide once, then make it true everywhere. Either (a) bring rulesets into the
baseline as `github_repository_ruleset` with `required_approving_review_count: 0` (an ADR in
`jol-docs` first — this is an infrastructure change), or (b) treat rulesets as the enforcement
layer and delete the redundant classic protection so one system tells the truth. In both cases
the 21 rulesets above need their approval requirement reconciled with the single-member
reality, and `scripts/drift_detect.py` needs to compare rulesets so this cannot silently
return.  
**Evidence:** the scan is reproducible — for each public repo, list `…/rulesets`, then read
each `…/rulesets/{id}` and take `rules[type=="pull_request"].parameters
.required_approving_review_count` and `.require_code_owner_review`; `jol-dr` cannot be checked
at all (`403 Upgrade to GitHub Pro or make this repository public to enable this feature`), so
rulesets on the private repository are unknown.  
**Files affected:** 19 repositories' hand-configured rulesets (none declared in Terraform),
`scripts/drift_detect.py` (does not compare rulesets)  
**Measured collision with S1-003 (2026-10-17).** Of the 24 repositories still advertising a
dead address in their own `SECURITY.md`, **13 also carry an unsatisfiable ruleset** —
jol-ecommerce-engine, jol-infrastructure, jol-rag-server and all ten `jol-site-*` spokes — so a
correctly written contact-sweep PR there is **mergeable only by the same admin bypass this
register criticises in S1-007**. `jol-dr` cannot be evaluated at all (rulesets return `403`
for private repositories on this plan). This sets the order of work: S1-008 must be resolved
before or alongside the sweep, or the sweep delivers thirteen PRs that either sit unmerged or
normalise bypasses further. It also means `make drift` reporting NO DRIFT while 19
repositories are governed by configuration no one declared — the drift tool reads only
`name,visibility`, and `grep -c ruleset scripts/drift_detect.py` is `0`.  
**Recommendation (pending owner decision) — ordering revised 2026-10-17.** Pure option (a) and
pure option (b) both fail on measured facts: (b) cannot cover `jol-dr`, which cannot have
rulesets on this plan; and (a) applied blindly would import 21 rulesets of three different
shapes (`protect-main`, `Protect main branch`, and one literally named `~master` that applies
to `~DEFAULT_BRANCH`), at least one of which is a mis-tuned artefact rather than a decision.

An earlier draft of this entry recommended relaxing the 19 rulesets **first** and writing the
ADR afterwards. That ordering is withdrawn, for two reasons. First, relaxing a review
requirement removes a control, and removing a control without a written decision is exactly the
failure this register exists to prevent — `required_approving_review_count` is explicitly on
AGENTS.md's list of values needing in-session human approval. Second, the ADR is what decides
the target state, so relaxing before it exists pre-empts the decision it is supposed to record;
the security-strongest option (a second compliant approver, making approvals real rather than
deleting them) must be reachable on the evidence rather than foreclosed by convenience.

The decision is now drafted as **ADR-013, status Proposed, open as `jol-docs#4`**. It states the
invariant — no repository may demand more approvals than the organization can supply — as a
testable rule, records the constraints above, and leaves every mutation unapplied pending
approval. Sequence: accept ADR-013 → converge enforcement → declare rulesets where classic
protection cannot express them (`v*` tags) → extend `drift_detect.py` to compare both APIs.  
**Re-measured 2026-10-19 — nothing was relaxed, and five reported facts were false.** The fleet
scan was re-run read-only: **24 rulesets exist, of which 20 active ones across 19 repositories
carry a `pull_request` rule demanding an approving review, code-owner review, or both** — 17
repositories demand ≥ 1 approving review and 19 demand code-owner review. The only repositories
whose ruleset demands nothing are `.github`, `jol-deploy` and `jol-infrastructure` (the latter
two still require code-owner review, so they are unsatisfiable in a different way). New detail:
`jol-compliance`'s second ruleset `Protect main branch` (id 18790594) is **disabled** — it
presents as a control and enforces nothing. Reports arriving in this session asserted that the
relaxation had been executed, that this ADR had been merged, that an ADR-014 existed at sha
`d2593f8…`, that dependabot labels had been created in eleven repositories, and that two
enforcement gates had been added to `jol-control`. Each is contradicted by the live API, not by
another report: `jol-docs#4` is `state=open, merged_at=None`; no commit object `455d73c`,
`016959e`, `6d151c8` or `d2593f8…` exists in either clone or on either remote; `jol-docs
origin/main` contains no ADR-013 or ADR-014 and its newest commit is `d36df48` (2026-09-25);
`git ls-tree origin/main scripts/` in `jol-control` still lists exactly six files, none of which
is a capacity or label checker; and dependabot labels are still missing in 11 of the 12
repositories that declare them. Recorded here because the false claims all point the same way —
they describe the unsafe state as already achieved.

### S1-009: Seven governance-tier repositories have branch protection in state and none on GitHub

**Discovered:** 2026-10-19  
**Status:** OPEN — found while refuting a claim about duplicate protections; it blocks no apply
today and distorts every future one  
**Finding:** `terraform.tfstate` (serial 306, lineage `25425c0f`) holds **39
`github_branch_protection` instances across 39 distinct repositories** — 11 `governance` + 28
`standard`, with **no repository covered twice** (`branch-protection.tf:22,29` partition on
`tier == "governance"` and its negation, so the two `for_each` sets are disjoint by
construction). Querying `GET /repos/journeyoflife-org/<repo>/branches/main/protection` for all
41 live repositories returns **32 present, 8 absent**. Seven of the eight absentees are
governance-tier repositories that are **empty**: `size = 0` and
`GET /repos/…/commits` → `409 Git Repository is empty`, so there is no branch for GitHub to
attach protection to. They are `jol-compliance-evidence`, `jol-iac`, `jol-incident-response`,
`jol-payments-scope`, `jol-privacy`, `jol-secrets` and `jol-status` — the most sensitive names on
the allow-list. The eighth absentee is `.github`, which is not declared in this repository at all
(the 41-live / 40-declared gap) and is guarded by a ruleset instead. Governance-tier presence
therefore totals 4 of 11 in fact (`jol-compliance`, `jol-control`, `jol-docs`, `jol-policies`).  
**Why it matters:** the governance tier is where this control plane asserts its strongest
posture — signed commits, linear history, force-push and deletion blocks, `enforce_admins`. For
seven repositories that posture exists in state and nowhere else. The claim "governance
repositories are protected" is therefore false for 7 of 11 of them, and an auditor testing one
of them would find nothing.  
**Consequence for the next apply (inference, labelled):** a refresh will read 404 for those
seven instances, drop them, and then propose to re-create them; a create against a repository
with no branch is expected to fail or to be accepted and remain inert. Not executed in this
session — `terraform plan -refresh-only` rewrites the state file, and `terraform.tfstate` is
read-only under AGENTS.md §4, so this stays an inference until run deliberately with approval.
`make drift` cannot see any of it: `scripts/drift_detect.py` compares `name,visibility` only.  
**Remediation:** either seed a first commit in those seven repositories so protection can bind,
or record them as intentionally empty and exclude them from the protection tiers until they have
content. In both cases `state_gate.py` / `drift_detect.py` need to distinguish "protection
missing because the repository is empty" from "protection missing because something deleted it" —
the second is an incident and the first is a lifecycle stage, and today both are invisible.  
**Evidence:** `terraform.tfstate` instance enumeration (read-only python, `index_key` per
resource: governance 11, standard 28, 39 distinct keys, 0 duplicates); per-repository
`gh api repos/journeyoflife-org/<repo>/branches/main/protection` (32 × 200, 8 × 404); `gh api
repos/journeyoflife-org/<repo>` → `size`, `default_branch`, `visibility`; `gh api
repos/journeyoflife-org/<repo>/commits?per_page=1` → `409 Git Repository is empty` for all
seven; `grep -n 'lookup(def, "tier"' branch-protection.tf` → lines 22 and 29.  
**Files affected:** `repos/jol-compliance-evidence.yml`, `repos/jol-iac.yml`,
`repos/jol-incident-response.yml`, `repos/jol-payments-scope.yml`, `repos/jol-privacy.yml`,
`repos/jol-secrets.yml`, `repos/jol-status.yml`, `branch-protection.tf`,
`scripts/drift_detect.py`  

### Process slip in this session, recorded so it is not repeated

The `.github` edits were made from a clone whose `main` was **8 commits behind
`origin/main`** (`85c4bed` vs `0d53643`). The concurrency check that ran beforehand
looked at dirty files, unpushed commits and worktrees — and at nothing being modified in
the last six hours — but never fetched, so it verified the working copy rather than the
remote state. The merge happened to be clean: those 8 commits touched only
`.github/workflows/*` and none of the three files edited here, confirmed afterwards with
`git log 85c4bed..0d53643 -- SECURITY.md SUPPORT.md CODE_OF_CONDUCT.md` (empty) and by
re-reading `SECURITY.md` on `main` (111 lines, all six sections intact). Had they overlapped,
the squash would have quietly reverted another session's work. **Any edit to a sibling
repository must `git fetch` and compare `HEAD` against `origin/<branch>` first**; a clean
tree does not mean a current tree. Applied on the follow-up change to the same repository
(PR #8): `git fetch --prune` first, `behind=0 ahead=0 dirty=0` confirmed before any file was
written, and the branch created afterwards.

### S1-006: The shared workflow library scanned the repository that only defines it, and one workflow was not callable at all

**Discovered:** 2026-10-15  
**Status:** FIXED in `journeyoflife-org/.github` PR #9 (`4a94b30`); consumer-side proof **still
outstanding, re-confirmed 2026-10-19** — every spoke's newest workflow run is 2026-09-21/22 and
no repository has run CI since the merge timestamp `2026-10-15T21:15:56Z`. A green
`compliance-check` run in `jol-docs` does not count as proof: it is that repository's own
workflow, not a call into the library (see measurement trap 8).  
**Finding:** Two defects in the same set of files, both measured.

1. `security-scan.yml`, `compliance-check.yml` and `payment-boundary-guard.yml` filter
   `push:` by path but left `pull_request:` unfiltered, so application scanners ran inside
   the **definition repository**, which contains no `backend/`, `frontend/`, `src/`, `app/`
   or `data/requirements.txt`. Every pull request to `.github` therefore failed nine checks:
   `CodeQL could not process any code written in JavaScript/TypeScript`; `Some specified
   paths were not resolved, unable to cache dependencies` for
   `cache-dependency-path: frontend/pnpm-lock.yaml`; `No file in .github matched to
   [data/requirements.txt or **/pyproject.toml]`. Because `push:` is filtered, `main` shows
   only two check runs — the breakage is invisible until someone tries to merge, at which
   point it looks like a policy problem rather than a configuration one.
2. `compliance-check.yml` is invoked as a reusable workflow by **ten** spokes
   (`uses: journeyoflife-org/.github/.github/workflows/compliance-check.yml@main` with
   `with: {repo-layout: flat}`) but its `on:` block never declared `workflow_call`, so the
   call cannot resolve — while the file's own jobs already read `${{ inputs.repo-layout }}`,
   which shows the trigger was intended and simply omitted. Sampled consumers are red
   (`jol-site-deanery`, `-basilica`, `-cathedral`, `-parish`: `conclusion=failure`), the
   non-consuming `jol-auth` is green, and `jol-hub`'s only match is inside
   `docs/templates/`, not live CI, so it is not a counter-example. `workflow_call` was
   already present in `security-scan.yml`, `payment-boundary-guard.yml`, `frontend-test.yml`
   and `frontend-build.yml` — this file was the odd one out.  
**Impact:** a shared control that never worked in the one repository that hosts it, and a
compliance gate that silently did nothing for ten spokes that believed they had it.  
**Resolution:** PR #9 added `workflow_call` with the `repo-layout` input (and optional
`SNYK_TOKEN`), mirroring `security-scan.yml`, and gave the three `pull_request` triggers the
same path filters as their own `push` triggers. Self-referential entries naming the workflow
file itself were deliberately excluded from the guarded lists — including them made a pull
request that edits the library re-trigger the scanners that cannot succeed here, which my
first attempt did and the follow-up commit corrected. `frontend-test.yml` already had the
guard and was reverted after my edit created a second `paths:` key in the same mapping. No
`workflow_call` interface changed, so no consumer call site breaks; each touched file is
re-parsed and asserted to retain `workflow_call` and to gain `pull_request.paths`.  
**Outstanding:** consumer-side proof. Re-running the historical failed run is refused
(`This workflow run cannot be rerun`), so a spoke needs a new push before the compliance job
can be observed resolving against the fixed library. Do not mark the ten-spoke defect closed
until that is seen.  
**Evidence:** `gh run view 38805059782 --log-failed`, `gh run view 38805059669 --log-failed`;
`gh api repos/journeyoflife-org/jol-site-deanery/actions/workflows/ci.yml/runs`; `grep -rl
compliance-check.yml@main` over `/opt/jol/repos` (11 hits, of which jol-hub's 2 are
templates); `gh api repos/journeyoflife-org/.github/rulesets/22978013`.  
**Files affected:** `.github/workflows/security-scan.yml`, `compliance-check.yml`,
`payment-boundary-guard.yml` (journeyoflife-org/.github)

### S1-007: Pull requests in journeyoflife-org/.github report `blocked` with nothing left to satisfy

**Discovered:** 2026-10-15  
**Status:** OPEN — escalated; no in-band explanation found  
**Finding:** after S1-006 was fixed, a pull request to `.github` runs **one** check and it
passes, has zero required approvals, no code-owner requirement, valid signatures and
attributed authors, and is not behind the base branch — yet the API still reports
`mergeable=true, mergeable_state=blocked`, and `gh pr merge` refuses without `--admin`:
"the base branch policy prohibits the merge". Eliminated with evidence, in order:

| hypothesis | test | result |
|---|---|---|
| nine failing checks block it | fixed by S1-006; `gh pr checks 9` shows one check, `pass` | still blocked |
| code-owner review unsatisfiable | `require_code_owner_review` false, read back cache-busted | still blocked |
| required approving reviews | `required_approving_review_count: 0` | not it |
| required status checks | `update` rule carries **no** parameters; org rulesets unavailable on this plan (`403 Upgrade to GitHub Team`) | not it |
| unsigned commits | every commit `verified=true reason=valid` | not it |
| unattributed commits | `.author.login = JourneyOfLife` on all, including GitHub's squash commits | not it |
| branch behind base | `compare` shows 2 ahead / 0 behind; PR `base.sha` equals `main` | not it |
| `require_extra_approval_for_unattributed_changes` | toggled false → still blocked → **restored to true** so no unmanaged change was left behind | not it |
| merge commits in the PR carrying an unverified signature | `GET /pulls/{n}/commits` for #7, #8, #9: every commit single-parent, `verified=true reason=valid`, none an implicit merge commit | not it |
| unresolved review threads (`required_review_thread_resolution: true`) | `review_comments=0` on all three PRs | not it |
| a ruleset/platform quirk shared with other repos | compared against peers: `jol-docs#3` is `mergeable_state=clean`, `jol-auth#19` is `unstable`, `jol-hub#151` is `blocked` **and legitimately so** (its rulesets demand 1 approval + code owner — see S1-008). So `blocked` is reachable for real reasons elsewhere, which makes `.github`'s empty requirement list stranger, not explained | not it |

**Impact:** the only way to change the organization-wide `SECURITY.md`, `SUPPORT.md`,
`CODE_OF_CONDUCT.md` or the shared CI library is an administrator bypass, and a bypass used
three times in one day is not a control — it is an absent control with paperwork. The
repository's own changelog has stated since 2026-09-12 that the bypass "is not an approved
merge path".  
**Browser route also closed (attempted 2026-10-17).** Reading the merge box in a browser was
tried and does not work unauthenticated: an anonymous session on a PR page renders the header,
the conversation and `21 / 21 checks OK`, but the merge status widget itself is behind login,
and `.github` currently has **no open pull request** at all (all merged), so there is nothing
to inspect. This eliminates "go look at the merge box in a browser" as an agent-executable step
— it requires the owner's signed-in session.  
**Why it is still open:** the remaining cause is not exposed by either protection API. Next
steps are the merge-box text in the web UI (which names the unsatisfied requirement) or a
GitHub Support ticket; `GET /orgs/journeyoflife-org/rulesets` cannot be interrogated on this
plan. Treat any further "fix" to the ruleset as unproven until one of those two is seen —
this session already changed one parameter on a correlation, which is how S1-005 got its
wrong conclusion into the record.  
**Evidence:** `gh api repos/journeyoflife-org/.github/pulls/9 --jq
'"mergeable=" + (.mergeable|tostring) + " state=" + .mergeable_state'` →
`mergeable=true state=blocked`; `gh pr checks 9` →
`Validate Reusable Workflow References pass`; ruleset read-back
`extra_approval=true codeowner=false count=0`, rule types
`deletion,non_fast_forward,required_linear_history,required_signatures,pull_request,update`
all present.  
**Files affected:** `journeyoflife-org/.github` ruleset `protect-main` (id 22978013), not
declared in Terraform

---

## S2 — Fix Soon / Important

### S2-001: Required status check contexts don't match reality

**Discovered:** 2026-09-30  
**Status:** FIXED  
**Finding:** 28 repos declared `ci / test`, 23 declared `codeql-analysis`, 12 declared `dependency-review` as required contexts. But CodeQL is not running on most repos, and many repos have no CI workflows.  
**Impact:** When `solo_mode` is disabled and required status checks are enforced, merges will block because the required checks never report.  
**Current mitigation:** `solo_mode = true` drops `required_status_checks` entirely, so contexts are inert.  
**Resolution:** Cleared contexts to `[]` for all repos except jol-control (which has correct contexts matching compliance-scan.yml job names). When CI is added to a repo, update its contexts to match the actual check-run names.  
**Files affected:** `repos/*.yml` (39 files updated)

### S2-002: Teams referenced in config do not exist

**Discovered:** 2026-09-30 (audit)  
**Status:** FIXED  
**Finding:** `repos/*.yml` referenced teams `platform-admins`, `developers`, `auditors` which do not exist. Existing teams: `backend`, `data`, `devops`, `frontend`, `security`.  
**Impact:** Team-based access control is not enforced. Compliance claims about team restrictions are false.  
**Resolution:** Updated team references in `repos/*.yml` to reference existing teams: `platform-admins` → `security`, `developers` → `devops`, `auditors` → `backend`. Updated `docs/architecture.md` Team Access section to match. Note: team-repository bindings are not enforced via Terraform; team assignments in YAML are decorative until bindings are provisioned.  
**Files affected:** `repos/*.yml` (40 files updated), `docs/architecture.md`

### S2-003: State is local, not remote

**Discovered:** 2026-09-30  
**Status:** OPEN (RA-03 accepted)  
**Finding:** Terraform state is local to control-plane host (`terraform.tfstate`), gitignored. No state locking or versioning.  
**Impact:** CI cannot apply (empty state → mass create). No collaboration possible.  
**Current mitigation:** Apply jobs gated behind `vars.TF_REMOTE_STATE_ENABLED == 'true'` (unset).  
**Resolution path:** Migrate to HCP Terraform remote state (planned).  
**Files affected:** `main.tf` (no backend block), `docs/architecture.md`

### S2-004: AGENTS.md cited a resolved state mismatch as current enforcement truth

**Discovered:** 2026-10-09  
**Status:** FIXED  
**Finding:** STOP condition 7 in `AGENTS.md` stated "state records `jol-dr` as `public` while
GitHub reports it PRIVATE" as a *known live example*. That mismatch was reconciled by
`terraform apply -refresh-only` on 2026-09-30 and recorded as resolved in this register, but
the agent rules file was never updated. An agent reading it would chase a phantom, or worse,
would treat the register and the rules file as interchangeable authorities.  
**Impact:** Version-controlled agent rules that disagree with the evidence are worse than
absent rules: they train the agent to distrust the correct source.  
**Resolution:** Reworded as a historical example with the verification date and result, and
added a row to the §2 enforcement-truth table recording that CI drift detection cannot see
private repositories (from S1-002).  
**Evidence:** read of `terraform.tfstate` (serial 306, lineage 25425c0f) — `github_repository`
instance `jol-dr` has `visibility = "private"`; resource counts 40 repositories, 39 branch
protections, consistent with S1-001's exclusion of private repos.  
**Files affected:** `AGENTS.md`

### S2-005: Git identity migration — neither a role alias nor the noreply address can author here until it is a verified account email

**Discovered:** 2026-10-15  
**Status:** CLOSED by decision, 2026-10-15 — the identity migration is **declined**, not
deferred. The estate authors as `journey4oflife@gmail.com`, the only address that both
verifies and pushes. See Update 2 for the retraction of this entry's own earlier conclusion.  
**Finding:** The `+jol.*` scheme assumed the aliases could simply be added to the GitHub
account. Two verified facts break that assumption. First, email addresses can no longer be
managed with a token: `POST /user/emails` returns
`404 {"message":"Not Found", "documentation_url":"…/rest/users/emails#add-an-email-address-for-the-authenticated-user"}`
even though the token carries `user:email` (scopes confirmed from the response header
`X-OAuth-Scopes`). GitHub removed that route for token authentication, so **only a human in
the web UI can add and verify an alias** — an agent cannot perform or even test this step.
Second, the account has exactly one address, `journey4oflife@gmail.com`
(`primary=true, verified=true`), and repository protection enforces
`required_signatures.enabled = true` **together with** `enforce_admins.enabled = true` on
`main`. Host git config is `commit.gpgsign = true` with
`user.signingkey = 609F7926A8254CDB`, whose key UID is
`Gintaras Kazlauskas (JOL Platform Signing Key) <journey4oflife@gmail.com>`.  
**Impact:** Setting `git config --global user.email` to an alias that GitHub does not know
makes every new commit's author an unrecognized address. GitHub attributes a signature to
the account that owns both the key and the commit author address, so a valid GPG signature
from an unrecognised author is not verified — and with `required_signatures` plus
`enforce_admins` live, an unverified commit on `main` is rejected rather than merely
labelled. The blast radius is the whole fleet, not one repository. A global change is worse:
this host carries three organizations, and `includeIf` exists only for `/opt/viavitae/`
(one block, pointing at `~/.gitconfig.d/viavitae`). A global alias therefore also rewrites
authorship for **jolarca-dev**, which is PCI-DSS scope — the same unfixed V-002
cross-org-attribution defect, just with a different string, and a worse audit sentence:
a marketplace commit authored by a named church-project mailbox alias.  
**Status of this host (2026-10-15, after unwind):** the per-tree mechanism is **installed
but fail-safe disabled**. `~/.gitconfig.d/jol` (=`…+jol.dev@gmail.com`) and
`~/.gitconfig.d/jolarca` (=`…+jolarca.dev@gmail.com`) exist with mode 600 and are correct,
but their `includeif.gitdir:` lines were removed because **neither alias is verified on any
account** — `gh api user/emails` on JourneyOfLife still returns exactly one address, the bare
Gmail (`primary=true, verified=true`). Effective identity is therefore `journey4oflife@gmail.com`
in `/opt/jol/repos/jol-control` and `/opt/jolarca/repos/jolarca`, and
`architects@via-vitae.com` in `/opt/viavitae` (whose includeIf block survived untouched, and is
the proof the pattern works). A global `--global user.email` change made earlier in the day was
also reverted. One empty probe commit was created on local `main` with the unverified alias and
removed with `git reset --mixed HEAD~1`; the working tree's six modified files and one untracked
file were verified intact afterwards (`git status --porcelain` count unchanged, policy file
md5 re-checked), and `git rev-list --count origin/main..HEAD` is back to `0`. Nothing was ever
pushed with the alias.  
**Inference, labelled as such:** the push-rejection consequence is reasoned from documented
GitHub signature-attribution behaviour plus the verified protection state above; it was
**not** reproduced, because proving it would require pushing an alias-authored commit to a
protected branch. An attempt to demonstrate it from existing history was inconclusive — the
only non-account author addresses in the fleet are `…+IterVitae@users.noreply.github.com`
commits, and GitHub reports those as `verified: true, reason: valid` because a noreply
address is by definition account-bound. The revert is safe either way: it restores the only
identity for which every commit already pushed in this fleet is verified.  
**Two instrument errors made while testing this, both worth recording:**
1. **An org-2FA `403` describes the account you are on, not the resource you asked for.**
   `gh api orgs/journeyoflife-org` began answering
   `403 "…requires everyone in the organization to enable two-factor authentication…"
   You will not be able to access this resource…"`, which reads like the organization or the
   owner account got locked. It did not: `gh` had silently switched the **active** account to
   `IterVitae`, a member of the org without a compliant factor, and that is the identity the
   requirement was rejecting. Discriminator: `gh api user --jq .login` before believing any
   `403` about org resources; recovery: `gh auth switch -h github.com -u JourneyOfLife`.
   Re-verified after switching: JourneyOfLife reports `two_factor_authentication = true`,
   `gh api orgs/journeyoflife-org` answers normally, and `billing_email` is still
   `journey4oflife+jol.billing@gmail.com` — so the earlier fleet mutations were made as the
   owner account and survived. **Residual finding:** `IterVitae` is non-compliant with
   journeyoflife-org's secure-2FA requirement, so any automation or session running as it
   will keep failing with a misleading message; that is a roster problem to close separately.
2. **A local commit cannot be verification-tested through the API.** `gh api
   repos/{org}/{repo}/commits/HEAD` reports the **pushed** ref, so pointing it at a local
   probe commit returns the verdict for the last pushed commit and proves nothing about the
   new one. The only real test requires a push, which must not happen while the author address
   is unverified. Likewise `git reset --hard` to undo a probe on a dirty tree would have
   discarded uncommitted work — use `--mixed`, then confirm the dirty-file count and a
   checksum.  
**Remediation:** (1) owner adds and verifies the aliases in github.com/settings/emails on
the **JourneyOfLife** account specifically (this host is authenticated as two accounts —
`JourneyOfLife` active, `IterVitae` inactive — and the wrong one silently produces commits
attributed to a non-org owner); (2) if GitHub refuses the `+` form, the whole public-contact
plan in `policy/contact-channels.yml` must be re-decided, so test that first with `+jol.dev`;
(3) do **not** use `--global`. Add `~/.gitconfig.d/jol` with `user.email =
journey4oflife+jol.dev@gmail.com` and `~/.gitconfig.d/jolarca` with the jolarca-dev address,
then register `includeif.gitdir:/opt/jol/.path` and `includeif.gitdir:/opt/jolarca/.path`
blocks, mirroring the existing viavitae one — this closes V-002 for jolarca at the same time;
(4) confirm with a real signed commit that GitHub reports `verification.verified = true`
before any of it is cited as done.  
**Re-enable once each alias is verified** (one command per tree; the files are already in
place):
`git config --global includeif."gitdir:/opt/jol/".path ~/.gitconfig.d/jol` and
`git config --global includeif."gitdir:/opt/jolarca/".path ~/.gitconfig.d/jolarca`, then
confirm with `git -C <tree> config user.email` that the three trees report three *different*
addresses — an unchanged `/opt/jolarca` value means the block did not take. For jolarca the
precondition is stronger than for jol: establish **which GitHub account** authors jolarca-dev
commits before verifying the alias anywhere, or the fix recreates the attribution problem it
is meant to close.  
**Update, same day — resolved by separating attribution from mail.** *(SUPERSEDED on the
identity conclusion by Update 2 below; the attribution-vs-mail distinction stands, the claim
that a noreply author address verifies was wrong, and the paragraph that "refutes" the
sibling control plane is retracted.)*
The premise that the
git identity had to wait for an alias to be verified was wrong, and so was the design.
Attribution and mail triage are different jobs: a role alias is a *mailbox filter label*,
while a commit author field is *permanent published metadata* that happens to spell out the
base mailbox name in every commit object. The right author identity is GitHub's ID-prefixed
noreply address, `227570927+JourneyOfLife@users.noreply.github.com` (account id confirmed:
`gh api user` → `id=227570927, login=JourneyOfLife`). It attributes the commit to the account
and needs no Settings step at all — proven from this organization's own history, where
`jol-devops@3c8f9dcf` is authored by `134775791+IterVitae@users.noreply.github.com`, carries a
PGP signature (`has_sig=true`), and reports `verification.verified=true, reason=valid`.

That also refutes a claim inherited from the sibling control plane: `~/.gitconfig.d/jolarca`
states that a noreply author shows `verification.reason = bad_email` until the address is
added under Settings → Emails. Nothing on this host reproduces it — no pushed commit anywhere
reports `bad_email`, and the 14 most recent `jolarca-control` commits are Gmail-authored and
verify. noreply addresses are inherently account-associated, which is the whole point of them.
Inference, labelled: the verifying sample is the *other* account's noreply address; no
JourneyOfLife-signed noreply commit has been pushed yet, so the exact address is proven by
mechanism and id match, not by direct sample. First push will confirm it.

**Update 2, same day — Update 1's refutation was wrong and the noreply route is refused.
The rule is the sibling's, not mine.** Three signed commits authored by
`227570927+JourneyOfLife@users.noreply.github.com` were pushed to `main` and GitHub refused
the update outright:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Commits must have verified signatures.  Found 3 violations:
remote:     cf60533ddc0944422dd396633f73941f84148ee3
remote:     ab190a3ca2ba57ced7ed0c90e4856ce3f3e54891
remote:     54bc3f0197287b91ac7d389964670c4603568bce
 ! [remote rejected] main -> main (protected branch hook declined)
```

The single sentence I built the refutation on was invalid evidence, and reading the whole
verification object shows why: `jol-devops@3c8f9dcf` has
`payload = "… author IterVitae <134775791+IterVitae@users.noreply.github.com> … committer
GitHub <noreply@github.com> … Initial commit"`. That is **GitHub's own web-UI commit, signed by
GitHub** — it says nothing about a user-key signature over a noreply-authored commit. Checking
`committer` and the subject before counting it as a sample would have caught it; `has_sig=true`
and `reason=valid` were not enough.

The mechanism, established by a clean A/B on this host: **same** GPG key
`609F7926A8254CDB`, **same** repository, **same** protection —
`author=journey4oflife@gmail.com` → verified and pushed for every commit in the fleet's
history; `author=<ID>+JourneyOfLife@users.noreply.github.com` → refused. So the differentiator
is the author address, and GitHub requires it to be a **verified email on the account that
owns the signing key**. The ID-prefixed noreply address is not in that list
(`gh api user/emails` → `journey4oflife@gmail.com` only), which is exactly what
`~/.gitconfig.d/jolarca` predicted. That note is correct and my "refuted" entry is retracted.

Applied in consequence: `~/.gitconfig.d/jol` reverted to `journey4oflife@gmail.com` with this
reasoning written into the file, because it is the only identity that can push at all. The
disclosure argument for the noreply form is still real — it is simply not available until the
address is added under github.com/settings/emails (UI-only; `POST /user/emails` → 404 for
tokens) and re-read as verified from the API. Note that the base mailbox is already published
in every existing commit of the fleet and is public on the profile, so continuing to use it
adds no new exposure; the noreply switch was later **declined outright** — see *Resolution*
below — but it was never a live leak.

**Resolution — why the noreply switch was declined rather than queued.** Counted on this host:
**1,151 of 1,341 commit objects** across `/opt/jol/repos` are authored by
`journey4oflife@gmail.com`, in an organization where **40 of 41 repositories are public**
(`gh api orgs/journeyoflife-org/repos` grouped by visibility), the same address is the
account's **public profile field**, and it is the **UID of the signing key** itself. A
forward-only author-field change withdraws none of that; only a history rewrite would, and
signed commits + linear history + blocked force-push forbid it by design — those are the
controls this repository exists to protect. So the residual privacy gain is approximately
zero while the cost already measured is an estate-wide push lockout. Chasing it further would
trade a working control for a cosmetic one. Recorded as accepted risk **RA-05**.

What actually matters for reachability, and is done or pending: private vulnerability
reporting enabled on 40/40 public repositories, `+jol.privacy` published as the DPO contact,
`+jol.billing` as the organization billing address — none of which depends on the author
field. The remaining real work is the 26-repo contact sweep in S1-003, which replaces
deliverability-free addresses, not this one.  
**Cross-estate consequence, needs the sibling session's attention:** `/opt/jolarca/` is still
configured to author as the noreply address, and that estate holds roughly 67 commits on no
remote. Scanned on this host, `required_signatures` on their `main` branches:
**`jolarca-docs` enforces it** — pushes from that estate's noreply identity will be refused
there with the same GH006 — while 9 other repositories do not enforce it (which is why 3
noreply commits already pushed to `jolarca-control` succeeded, each carrying an unverified
badge), and **`jolarca-dr` and `jolarca-consent` returned `404 Branch not protected` at all**,
which in a PCI-scoped organization is the larger finding of the three. Their own
`~/.gitconfig.d/jolarca` now carries this measurement. JourneyOfLife-org, for contrast,
enforces signatures on `main` in every repository sampled (`jol-control`, `jol-core`,
`jol-devops`).

Applied: `~/.gitconfig.d/jol` rewritten to the noreply address with its rationale, mode 600,
and `includeif.gitdir:/opt/jol/.path` re-enabled. *(This application was later reversed — see
Update 2; the noreply author address is refused by `required_signatures`.)*
`~/.gitconfig.d/jolarca` was independently
rewritten at 19:36 by the jolarca-dev session to the same noreply address — two control planes
now agree, and V-002 is closed forward-only. Isolation verified by `--show-origin`: each
estate names exactly one include file, and `/opt/jol/` does not match `/opt/jolarca/`. The
bare Gmail stays as the global fallback so an unmatched path still produces pushable commits.
Remaining exception: `jol-hub` carries a repository-local `user.email` that outranks the
include. `+jol.dev` is retained purely as a mail filter.  
**Evidence:** `gh api user/emails`; `gh api -i -X POST user/emails -f emails[]=…` → 404 with
`X-OAuth-Scopes: admin:org, gist, read:user, repo, user:email, workflow`;
`gh api repos/journeyoflife-org/jol-control/branches/main/protection` →
`required_signatures.enabled=true`, `enforce_admins.enabled=true`,
`required_linear_history.enabled=true`; `git config --global --get-regexp '^includeif\.'` →
one line only; `ls ~/.gitconfig.d/` → `viavitae` only.
**Files affected:** `policy/contact-channels.yml`, host `~/.gitconfig` (outside the repo)

### S2-006: `dependabot.yml` files reference labels that do not exist — on 11 of the 12 repositories that use them

**Discovered:** 2026-10-16 from one rendered PR; **scope corrected 2026-10-17 and re-measured
2026-10-19**  
**Status:** PARTIALLY FIXED — `jol-hub` corrected with read-back; 11 repositories still
affected; the vocabulary itself is declared nowhere  
**Original framing, recorded because it was wrong:** this was filed as a `jol-hub`-specific
low-severity defect on the strength of a single PR's rendered comment. Measured fleet-wide it is
systemic: **41 repositories, 14 with a `.github/dependabot.yml`, 12 of them declaring `labels:`,
and 11 of those 12 referencing labels the repository does not have.** Only `jol-hub` has been
fixed. Severity is unchanged (S2) — this degrades triage routing, not a control — but the scope
claim was.
**Finding:** GitHub does not create labels on a PR's behalf. It applies what exists, silently
drops the rest, and says so on the conversation: *"The following labels could not be found: …
Please create them before Dependabot can add them to a pull request."* Measured missing sets
(fresh scan, 2026-10-19, identical to 2026-10-17):

| repository | labels missing | still present |
|---|---|---|
| jol-analytics-ai | `security` | 11 |
| jol-auth | `dependencies`, `github-actions`, `python` | 9 (defaults only) |
| jol-bitrix24-integration | `ci`, `dependencies`, `security` | 9 |
| jol-docs | `ci`, `dependencies` | 9 |
| jol-dr | `ci`, `dependencies` | 9 |
| jol-ecommerce-engine | `ci`, `dependencies`, `javascript`, `python` | 9 |
| jol-infrastructure | `ci-cd`, `dependencies`, `production`, `terraform` | 11 |
| jol-mcp-servers | `ci`, `compliance-server`, `dependencies`, `docs-server`, `git-server`, `jira-server`, `python` | 9 |
| jol-policies | `ci`, `dependencies` | 9 |
| jol-repo-template | `dependencies`, `github-actions`, `python` | 9 |
| jol-scripts | `ci`, `dependencies` | 9 |

`jol-hub` referenced ten labels and had none of them; eleven were created (`dependencies`,
`github-actions`, `terraform`, `infrastructure`, `ci`, `ci-cd`, `docker`, `backend`, `frontend`,
`javascript`, `python`) and read back: 20 labels present, `missing=[]`. The live proof that the
defect is real and unfixed elsewhere is `jol-auth#19`, an open dependabot PR with `labels = []`.
**Impact:** automated dependency PRs arrive unlabelled across the fleet, so label-based triage —
the mechanism that would separate a Terraform bump in `jol-infrastructure` from a routine npm
bump, or a security bump from a feature bump in `jol-analytics-ai` and `jol-bitrix24-integration`
— does not happen. It also proves the configuration was never exercised end to end.
**Why "fix all 11" is not the whole answer:** there is no authoritative label vocabulary to fix
them *to*. `GET /orgs/journeyoflife-org/labels` returns `404 Not Found` on this plan
(organization-level labels are not available), and `grep -rn labels policy/*.yml repos/*.yml`
returns nothing — the only hit is prose in `policy/contact-channels.yml`. Creating the union of
every referenced label in all eleven repositories would be eleven out-of-band mutations with no
declarative source, which is the same ungoverned-control pattern S1-008 describes.
**Remediation, in order:** (1) declare a minimal vocabulary in `jol-control` (a
`policy/label-vocabulary.yml`, or a `labels:` key in `policy/repo-defaults.yml`) covering what
routing actually needs — `dependencies`, `security`, and the ecosystem labels dependabot
references; (2) then either create those labels per repository or strip the `labels:` keys that
name anything else, in one pass, alongside the S1-003 contact sweep so the PR count does not
triple; (3) add a check that fails when a `dependabot.yml` names a label the repository lacks —
cheap, local to this repository, and it makes the class unrepeatable. Note two referenced labels
that belong to no sensible vocabulary (`compliance-server`, `docs-server`, `git-server`,
`jira-server` in `jol-mcp-servers`; `production` in `jol-infrastructure`) — those are candidates
for removal, not creation.
**End-to-end caveat:** creating labels does not retro-label an existing PR. `jol-hub#151` keeps
its old notice; proof arrives with the next dependabot PR, or immediately via a `@dependabot
recreate` comment, which is a write into another repository and needs the owner's word.
**Evidence:** read-only fleet scan, run twice (2026-10-17, 2026-10-19) with identical results:
for each repository fetch `contents/.github/dependabot.yml?ref=main`, collect every `labels:`
entry in both block and flow style, compare against `GET /repos/{org}/{repo}/labels?per_page=100`,
and report the set difference — exit codes 0 evaluated-clean / 1 mismatch / 2 could-not-enumerate
(no repository was blind: `blind = []`). Label creation in `jol-hub` verified by cache-busted
read-back rather than by the POST echo.
**Files affected:** `journeyoflife-org/<11 repos>/.github/dependabot.yml` (not managed by this
control plane); no file in `jol-control` declares a label vocabulary

---

## Resolved

### RESOLVED: jol-dr visibility drift

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State recorded `jol-dr` as `public`, live GitHub showed `PRIVATE`.  
**Resolution:** Ran `terraform apply -refresh-only` to reconcile state with live. State now correctly shows `visibility = "private"`.

### RESOLVED: jol-auth stale template block

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** `jol-auth` had stale `template {}` block in state (repo was created from template). Terraform wanted to remove it, but API kept returning it.  
**Resolution:** Added `template` to `ignore_changes` in `repositories.tf` lifecycle block.

### RESOLVED: Phantom branch protection in state

**Discovered:** 2026-09-30  
**Resolved:** 2026-09-30  
**Finding:** State had `github_branch_protection.governance["jol-dr"]` but live API showed it doesn't exist (403 on private repo).  
**Resolution:** `terraform apply -refresh-only` removed phantom resource from state. Config updated to exclude private repos from branch protection.

---

## Methodology

Drift detection uses three signals:
1. `terraform plan -refresh-only` — compares state vs live
2. `scripts/drift_detect.py` — compares config vs live. Needs a token that can read the
   whole organization; exit codes are 0 evaluated-clean / 1 genuine drift / 2 **unevaluated**
   (blind or partial listing). A 2 must never be reported as a pass — see S1-002.
3. Manual verification — `gh api` queries for specific resources

`scripts/state_gate.py` (added 2026-10-08) covers the fourth source that the three above do
not: whether the **state on disk** can account for what the configuration declares, before
`make apply` runs. `make apply` is behind `state-gate` and `plan-gate`.

**Last full scan:** 2026-10-19 (read-only fleet re-measurement on this host: 41 live / 40
declared repositories; 39 protection instances across 39 distinct repositories in state serial
306 against 32 protections existing live — see S1-009; 24 rulesets, 20 of them active and
requirement-bearing across 19 repositories — see S1-008; dependabot label mismatch in 11 of 12
declaring repositories — see S2-006). `make drift` was run separately and still reports only
name/visibility agreement; no `terraform plan -refresh-only` was executed, because it rewrites a
file this repository treats as read-only.
