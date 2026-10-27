# Secret inventory — jol plane (charity)

| Field | Value |
| --- | --- |
| Entity | journeyoflife-org (Catholic charity, owns its hardware) |
| Type | Metadata register. **Never record a secret value here** — values live in `~/.password-store/jol/` (age-encrypted) or the GitHub Actions secret store. |
| Consumed by | `scripts/check_secret_inventory.sh` (run manually or wire into `plan.yml`) |
| Framework basis | ISO 27001:2022 A.5.17, A.8.2, A.5.18; SOC 2 CC6.1/CC6.2/CC6.3; GDPR Art. 5(1)(f), Art. 32 |
| Boundary 1 | This register lists only credentials `jol-control` depends on. Shared human/root credentials appear as reference rows (this plane's dependency), never as merged registers. |

## Register

Columns: `secret_id | vault_path (pass) | tier | type | entity | storage_location | expires | rotation | last_verified | blast_radius | control_id | recovery_path`

| secret_id | vault_path | tier | type | entity | storage_location | expires | rotation | last_verified | blast_radius | control_id | recovery_path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| K1 | jol/github/drift-read-pat | T1 | fine-grained PAT `jol-control-drift-read` | journeyoflife-org | GitHub + Actions secret `ORG_READ_TOKEN` (runbooks.md RB-07) | 2027-01-17 | 90d | 2026-10-20 | org-wide private-repo read | CC6.1 / A.5.17 | re-mint per RB-07; revoke via UI |
| GH-def | (n/a — injected) | T2 | Actions default `GITHUB_TOKEN` | journeyoflife-org | ephemeral per workflow run | never | auto (per-run) | 2026-10-20 | repo-scoped per `permissions:` block | CC6.1 | expires with the run |
| B1b-ref | (gh-managed, not in pass) | T1 | gh OAuth token, account `JourneyOfLife` (interactive apply path) | all-three (shared human credential) | `gh` keyring, active account | 2099-12-31 | manual | 2026-10-20 | org admin on all three controllers | A.8.2 / CC6.2 | revoke via account settings |
| AGE-1 | (raw file, not pass) | T0 | age X25519 identity `~/.config/age/state-backup-key.txt` | all-three | host filesystem, mode 0600 | never | on-compromise | 2026-10-17 | jol state archives + vault | A.8.24 / A.5.30 | sealed 2-of-2 envelopes (pending) |
| AGE-2 | (raw file, not pass) | T0 | ~~age X25519 identity `~/.config/age/state-recovery-20261027.txt`~~ — **DESTROYED 2026-10-27** | journeyoflife-org | **no copy is known to exist anywhere.** Shredded on this host with no off-host copy taken; five other age identities and two session transcripts were tested for the ability to open its backup and all returned zero bytes | never | n/a | 2026-10-27 | was the second custody path for the off-device state backups; that snapshot is now single-custody (AGE-1 opens it, so **no data loss**) | A.8.24 / A.5.30 | **Nothing to recover.** The recipient `age18457pc8jfy8jrz7qhy36mzkxn7x4crvh79nmkqfdcyxnwn9urpyqgajvnj` stays in `snapshots' .info` sidecars as history: those files are encrypted to it and it can never be opened again. Row retained rather than deleted, because deleting the record of a lost key is how the loss is forgotten. See S2-013 |
| AGE-3 | (raw file, not pass) | T0 | age X25519 recovery identity — **to be minted**, second recipient for `terraform.tfstate` backups (runbooks.md RB-08 step 1, retirement via RB-08 step 4) | journeyoflife-org | to be held **off this host**; the public recipient goes in `~/.config/age/offdisk-recipient.txt` so scheduled runs have something honest to encrypt to | never | on-compromise | — | opens the off-device state backups independently | A.8.24 / A.5.30 | mint, copy off-host, then **prove it** with `make retire-key` on AGE-2's replacement before deleting the local half. Until the recipient file exists, `scripts/state_backup_guard.sh` exits 2 and refuses to back up to a single key |

**Recipient semantics, stated so these rows are not misread.** RB-08 encrypts to AGE-1 **and** the
current recovery recipient (now AGE-3, formerly AGE-2) as two `age` *recipients*. That is **1-of-2**:
either private key alone decrypts the file. It is not threshold secrecy, and it is not the "sealed 2-of-2
envelopes" recorded in AGE-1's `recovery_path`, which refers to a *custody* procedure that is still
pending. Two recipients exist so that the loss of one machine does not destroy both the inventory and
its only key — not so that two parties must collude to read it. Claiming the latter would be an
overstated control. **The single-copy risk on this host is exactly that gap made real:** AGE-2 was
shredded before any off-host copy existed, so the one snapshot encrypted to it is reachable only by
AGE-1, which lives on the same machine — and `state_backup_guard.sh` therefore refuses to run a
scheduled backup until a second recipient is recorded, rather than quietly producing one-key copies.

`expires` semantics: ISO date = hard deadline (`check_secret_inventory.sh` fails CI
within 14 days); `2099-12-31` = no server-side expiry placeholder, enforce by rotation
policy; `never` = root/ephemeral, on-compromise only; `unknown` = finding, not a pass.

## Rules

1. One row per credential; name the row after the account, not the service.
2. Every credential used by this repo without a row here is a review failure.
3. After rotation update `expires` + `last_verified` in the same commit.
4. The vault is backed up as a git bundle per the host backup runbook
   (`/opt/jol/backup/tfstate/vault-<UTC>.bundle`, `umask 077`).
