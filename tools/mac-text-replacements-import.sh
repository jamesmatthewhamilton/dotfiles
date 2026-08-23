#!/usr/bin/env bash
#
# Add macOS text replacements from a CSV: shortcut,phrase
#   "ily","i love you"
#
# Additive only. A shortcut that already exists is skipped, never modified.
# Safe to re-run: if the keyboard daemon holds the write lock the transaction
# fails cleanly and nothing is written.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../bash/common/logger.sh
source "${SCRIPT_DIR}/../bash/common/logger.sh"

die() { printf "${ERROR}%s\n" "$*" >&2; exit 1; }
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

DB="${HOME}/Library/KeyboardServices/TextReplacements.db"
if [[ "${1:-}" == "--db" ]]; then DB="${2:?--db needs a path}"; shift 2; fi
CSV="${1:-}"

[[ -n "$CSV" ]] || die "Usage: ${0##*/} [--db PATH] <csv-file>"
[[ -r "$CSV" ]] || die "CSV not readable: $CSV"
[[ -f "$DB"  ]] || die "Database not found: $DB"

# sqlite3's CSV reader handles quoting, embedded commas and newlines.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STAGE="${WORK}/stage.db"
LOG="$(sqlite3 "$STAGE" 2>&1 <<EOF
CREATE TABLE csv_in(shortcut TEXT, phrase TEXT);
.mode csv
.import '$(esc "$CSV")' csv_in
EOF
)" || die "Could not read CSV: $CSV"

# .import warns but still imports, so treat any output as fatal.
[[ -z "$LOG" ]] || die "Malformed CSV -- every row must have exactly 2 columns:
$LOG"

BAD="$(sqlite3 "$STAGE" "SELECT '  row '||rowid FROM csv_in
        WHERE shortcut IS NULL OR phrase IS NULL
           OR TRIM(shortcut) = '' OR TRIM(phrase) = '';")"
[[ -z "$BAD" ]] || die "Malformed CSV -- empty or NULL field:
$BAD"

q() { sqlite3 "$STAGE" "ATTACH DATABASE '$(esc "$DB")' AS tgt; $1"; }

TAKEN="SELECT 1 FROM tgt.ZTEXTREPLACEMENTENTRY t
        WHERE t.ZSHORTCUT = c.shortcut AND t.ZWASDELETED = 0"

while read -r s; do
    [[ -n "$s" ]] && printf "${INFO}%s: already present -- skipped\n" "$s"
done < <(q "SELECT DISTINCT c.shortcut FROM csv_in c
              JOIN tgt.ZTEXTREPLACEMENTENTRY t
                ON t.ZSHORTCUT = c.shortcut AND t.ZWASDELETED = 0
             WHERE t.ZPHRASE = c.phrase;")

while read -r s; do
    [[ -n "$s" ]] && printf "${WARNING}%s: shortcut in use with a different phrase -- skipped\n" "$s"
done < <(q "SELECT DISTINCT c.shortcut FROM csv_in c
              JOIN tgt.ZTEXTREPLACEMENTENTRY t
                ON t.ZSHORTCUT = c.shortcut AND t.ZWASDELETED = 0
             WHERE t.ZPHRASE <> c.phrase;")

# Rows move as hex so quotes, newlines and emoji survive intact.
mapfile -t NEW < <(q "
  SELECT hex(c.shortcut) || '|' || hex(c.phrase) FROM csv_in c
   WHERE c.rowid IN (SELECT MIN(rowid) FROM csv_in GROUP BY shortcut)
     AND NOT EXISTS ($TAKEN);")
if [[ ${#NEW[@]} -eq 1 && -z "${NEW[0]}" ]]; then NEW=(); fi
if [[ ${#NEW[@]} -eq 0 ]]; then printf "${SUCCESS}Nothing to add.\n"; exit 0; fi

# Z_MAX must keep up with Z_PK or Core Data will later allocate a colliding key.
pk="$(q "SELECT MAX((SELECT COALESCE(MAX(Z_PK),0) FROM tgt.ZTEXTREPLACEMENTENTRY),
                    (SELECT COALESCE(Z_MAX,0)     FROM tgt.Z_PRIMARYKEY WHERE Z_ENT = 1));")"
now=$(( $(date +%s) - 978307200 ))   # Core Data epoch: 2001-01-01

SQL="BEGIN IMMEDIATE;"
for r in "${NEW[@]}"; do
    pk=$((pk + 1))
    SQL+="INSERT INTO tgt.ZTEXTREPLACEMENTENTRY
      (Z_PK,Z_ENT,Z_OPT,ZNEEDSSAVETOCLOUD,ZWASDELETED,ZTIMESTAMP,
       ZPHRASE,ZSHORTCUT,ZUNIQUENAME,ZREMOTERECORDINFO)
      VALUES ($pk,1,1,1,0,$now,CAST(x'${r##*|}' AS TEXT),CAST(x'${r%%|*}' AS TEXT),'$(uuidgen)',NULL);"
done
SQL+="UPDATE tgt.Z_PRIMARYKEY SET Z_MAX = $pk WHERE Z_ENT = 1; COMMIT;"

q "$SQL" || die "Write failed -- database busy. Nothing changed; re-run later."

printf "${SUCCESS}Added %d replacement(s).\n" "${#NEW[@]}"
