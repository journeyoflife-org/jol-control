#!/usr/bin/env bash
# RB-08/RB-09: one command that answers "is the state backup actually protected?"
#
# Why this exists instead of an alert: this host has no functioning push channel. Verified
# 2026-10-27 - nothing listens on :9093 and no alertmanager container exists, the configured Slack
# webhook is the literal string PLACEHOLDER, journeyoflife.org publishes a null MX so the
# security-email receiver hard-bounces (finding S1-003), and Prometheus scrapes only itself. A
# notification into that chain would look like coverage and deliver nothing (finding S2-016). Until
# a real channel exists, the honest control is a pull that is cheap enough to run constantly and
# strict enough to be trusted.
#
# Exit codes, same convention as every other gate here:
#   0  a snapshot exists, is fresh, and is provably on a different physical disk
#   1  stale, missing, or on the same disk as the state - act now
#   2  UNEVALUATED - a fact needed for the verdict could not be read. Never a pass.
set -uo pipefail

REPO="${REPO:-/opt/jol/repos/jol-control}"
DEST="${DEST:-/mnt/jol-backup/jol-state-backup}"
KEYDIR="${KEYDIR:-$HOME/.config/age}"
RECIPIENT_FILE="${RECIPIENT_FILE:-$KEYDIR/offdisk-recipient.txt}"
MAX_AGE_H="${MAX_AGE_H:-24}"
ATTEST_MAX_H="${ATTEST_MAX_H:-720}"   # a custody attestation older than 30 days is not evidence
ATTESTED="${ATTESTED:-$KEYDIR/offhost-attested}"

rc=0
note() { printf '  %-26s %s\n' "$1" "$2"; }
bad()  { printf '  %-26s %s\n' "$1" "$2"; rc=1; }
unk()  { printf '  %-26s %s\n' "$1" "$2"; [ "$rc" -lt 2 ] && rc=2; }

echo "state backup status ($DEST, freshness limit ${MAX_AGE_H}h)"

NEWEST="$(find "$DEST" -maxdepth 1 -type f -name '*.age' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -z "$NEWEST" ]; then
  bad "newest snapshot" "NONE in $DEST - is $DEST mounted? (findmnt -T $DEST)"
else
  NOW="$(date +%s)"; THEN="$(stat -c %Y "$NEWEST")"; age_h=$(( (NOW - THEN) / 3600 ))
  if [ "$age_h" -lt "$MAX_AGE_H" ]; then
    note "newest snapshot" "$(basename "$NEWEST") (${age_h}h old)"
  else
    bad "newest snapshot" "$(basename "$NEWEST") is ${age_h}h old (> ${MAX_AGE_H}h) - the guard is not running"
  fi
fi

# The device separation claim lives in the sidecar the backup wrote. Trust the record, then check it
# is still true of the live mount, because a stale sidecar describes the disk as it was.
INFO="${NEWEST:+$NEWEST.info}"
if [ -n "$INFO" ] && [ -s "$INFO" ]; then
  dcheck="$(sed -n 's/^device-check  *: //p' "$INFO")"
  case "$dcheck" in
    verified-different*) note "sidecar device-check" "$dcheck" ;;
    unevaluated*)        unk  "sidecar device-check" "$dcheck" ;;
    "")                  unk  "sidecar device-check" "absent - snapshot predates the field" ;;
    *)                   bad  "sidecar device-check" "$dcheck" ;;
  esac
  case "$(sed -n 's/^recovery-key-decrypted: //p' "$INFO")" in
    yes) note "recovery key decrypted" "yes, at backup time" ;;
    no)  note "recovery key decrypted" "no - routine run, only the recipient was supplied" ;;
    *)   unk  "recovery key decrypted" "not recorded in this sidecar" ;;
  esac
else
  [ -n "$NEWEST" ] && unk "sidecar" "missing for $(basename "$NEWEST") - cannot confirm the expected md5"
fi

# Independently re-derive the separation rather than believing the file.
if [ -n "$NEWEST" ]; then
  sd="$(lsblk -no PKNAME "$(findmnt -no SOURCE --target "$NEWEST")" 2>/dev/null | head -1)"
  ld="$(lsblk -no PKNAME "$(findmnt -no SOURCE --target "$REPO/terraform.tfstate")" 2>/dev/null | head -1)"
  if [ -z "$sd" ] || [ -z "$ld" ]; then
    unk "device separation" "could not resolve disks ($sd / $ld)"
  elif [ "$sd" = "$ld" ]; then
    bad "device separation" "SAME disk ($sd) - a device failure takes state and backup"
  else
    note "device separation" "state=$ld backup=$sd"
  fi
fi

# Custody: the key must be somewhere other than the machine holding the ciphertext. This is the part
# no local check can prove - all a script can see is that a copy is not HERE.
if [ -s "$RECIPIENT_FILE" ]; then
  note "second recipient" "$(sed -n '1p' "$RECIPIENT_FILE" | cut -c1-18)…"
  if [ -d "$DEST/keys" ] && [ -n "$(ls -A "$DEST/keys" 2>/dev/null)" ]; then
    note "key copies here" "this host AND $DEST/keys"
  else
    note "key copies here" "this host only"
  fi
  # Custody is proven only by the challenge round-trip in offhost_rehearsal.sh: a nonce encrypted to
  # the recipient was recovered on another machine. It is a dated record, so it can expire - which is
  # what makes 0 reachable without letting it become a permanent green light.
  if [ -s "$ATTESTED" ]; then
    aw="$(sed -n 's/^attested=//p' "$ATTESTED")"
    arec="$(sed -n 's/^recipient=//p' "$ATTESTED")"
    ats="$(date -u -d "$aw" +%s 2>/dev/null || echo 0)"
    if [ "$arec" != "$(sed -n '1p' "$RECIPIENT_FILE" | tr -d ' \t')" ]; then
      bad "off-machine custody" "attested for a DIFFERENT recipient - re-run the rehearsal"
    elif [ "$ats" -le 0 ]; then
      unk "off-machine custody" "attestation timestamp unreadable: '$aw'"
    else
      aage_h=$(( ( $(date -u +%s) - ats ) / 3600 ))
      if [ "$aage_h" -lt "$ATTEST_MAX_H" ]; then
        note "off-machine custody" "attested ${aage_h}h ago (limit ${ATTEST_MAX_H}h): challenge recovered elsewhere"
      else
        bad "off-machine custody" "attestation is ${aage_h}h old (> ${ATTEST_MAX_H}h) - rehearse again"
      fi
    fi
  else
    [ "$rc" -eq 0 ] && unk "off-machine custody" "NOT PROVEN - run RB-09 step 5, then: scripts/offhost_rehearsal.sh attest <token>"
  fi
else
  bad "second recipient" "no $RECIPIENT_FILE - backups are refused until one exists (RB-09 step 3)"
fi

# The guard's own last word, if this user may read the journal.
last="$(journalctl --no-pager -t state-backup-guard -n 1 2>/dev/null | tail -1 | sed 's/.*state-backup-guard\[[0-9]*\]: //')"
if [ -n "$last" ]; then note "last guard verdict" "$last"; else unk "last guard verdict" "journal unreadable for $(id -un)"; fi

echo
case "$rc" in
  0) echo "HEALTHY: fresh, on a different disk. (Off-machine custody still needs RB-09 step 5.)" ;;
  2) echo "UNEVALUATED: a fact above could not be read. This is NOT a pass - resolve it, do not re-run and hope." ;;
  *) echo "ACTION REQUIRED: a check above failed." ;;
esac
exit "$rc"
