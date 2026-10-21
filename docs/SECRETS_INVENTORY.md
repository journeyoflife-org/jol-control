# Secret inventory — jol plane (charity)

| Field | Value |
| --- | --- |
| Entity | journeyoflife-org (Catholic charity, owns its hardware) |
| Type | Metadata register. **Never record a secret value here** — values live in the age vault `~/.vault/jol/` (encrypted with the host `vault.sh`, reusing the AGE-1 identity) or the GitHub Actions secret store. |
| Consumed by | `scripts/check_secret_inventory.sh` (run manually or wire into `plan.yml`) |
| Framework basis | ISO 27001:2022 A.5.17, A.8.2, A.5.18; SOC 2 CC6.1/CC6.2/CC6.3; GDPR Art. 5(1)(f), Art. 32 |
| Boundary 1 | This register lists only credentials `jol-control` depends on. Shared human/root credentials appear as reference rows (this plane's dependency), never as merged registers. |

## Register

Columns: `secret_id | vault_path (age vault) | tier | type | entity | storage_location | expires | rotation | last_verified | blast_radius | control_id | recovery_path`

| secret_id | vault_path | tier | type | entity | storage_location | expires | rotation | last_verified | blast_radius | control_id | recovery_path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| K1 | jol/github/drift-read-pat | T1 | fine-grained PAT `jol-control-drift-read` | journeyoflife-org | GitHub + Actions secret `ORG_READ_TOKEN` (runbooks.md RB-07) | 2027-01-17 | 90d | 2026-10-20 | org-wide private-repo read | CC6.1 / A.5.17 | re-mint per RB-07; revoke via UI |
| GH-def | (n/a — injected) | T2 | Actions default `GITHUB_TOKEN` | journeyoflife-org | ephemeral per workflow run | never | auto (per-run) | 2026-10-20 | repo-scoped per `permissions:` block | CC6.1 | expires with the run |
| B1b-ref | (gh-managed, not in pass) | T1 | gh OAuth token, account `JourneyOfLife` (interactive apply path) | all-three (shared human credential) | `gh` keyring, active account | 2099-12-31 | manual | 2026-10-20 | org admin on all three controllers | A.8.2 / CC6.2 | revoke via account settings |
| AGE-1 | (raw file, not pass) | T0 | age X25519 identity `~/.config/age/state-backup-key.txt` | all-three | host filesystem, mode 0600 | never | on-compromise | 2026-10-17 | jol state archives + vault | A.8.24 / A.5.30 | sealed 2-of-2 envelopes (pending) |

`expires` semantics: ISO date = hard deadline (`check_secret_inventory.sh` fails CI
within 14 days); `2099-12-31` = no server-side expiry placeholder, enforce by rotation
policy; `never` = root/ephemeral, on-compromise only; `unknown` = finding, not a pass.

## Rules

1. One row per credential; name the row after the account, not the service.
2. Every credential used by this repo without a row here is a review failure.
3. After rotation update `expires` + `last_verified` in the same commit.
4. The vault is backed up as a git bundle per the host backup runbook
   (`/opt/jol/backup/tfstate/vault-<UTC>.bundle`, `umask 077`).
5. **`pass`/`~/.password-store` is deprecated:** it was never `pass init`'d and the only
   GPG key (`609F7926A8254CDB`) is signing-only `[SC]` with no encryption subkey, so it
   cannot encrypt. The age vault (`~/.vault`) supersedes it; `~/.password-store` holds no
   real secrets.
