#!/usr/bin/env bash
#
# apply_chage_from_file.sh
#
# Usage:
#   ./apply_chage_from_file.sh user.txt            # dry-run (default)
#   ./apply_chage_from_file.sh --dry-run user.txt  # same as above
#   sudo ./apply_chage_from_file.sh --apply user.txt
#
# What it does:
#  - Parses the provided file for "Authorized Administrators:" and "Authorized Users:"
#  - Extracts usernames (handles lines like: "chowe (you)")
#  - Excludes any username marked with "(you)" or the current invoking user
#  - For each remaining username that exists on the system, runs:
#       chage -m 2 -M 90 -W 7 <username>
#    (or prints the command in dry-run mode)
#
set -o errexit
set -o pipefail
set -o nounset

if [ $# -lt 1 ]; then
  echo "Usage: $0 [--dry-run|--apply] <user-file>"
  exit 2
fi

MODE="dry-run"
FILE=""

# parse args
if [ "$1" = "--apply" ]; then
  MODE="apply"
  FILE="${2:-}"
elif [ "$1" = "--dry-run" ]; then
  MODE="dry-run"
  FILE="${2:-}"
else
  FILE="$1"
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "Error: user file not found. Provide path to the user.txt file."
  echo "Usage: $0 [--dry-run|--apply] <user-file>"
  exit 2
fi

# verify chage exists (needed for apply)
if [ "$MODE" = "apply" ] && ! command -v chage >/dev/null 2>&1; then
  echo "Error: chage not found. Install util-linux (chage) or run on a system with chage."
  exit 1
fi

# helper trim
trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

# Parse file
declare -a parsed_users
declare -A mark_you
section="none"
while IFS= read -r rawline || [ -n "$rawline" ]; do
  line="$(trim "$rawline")"
  [ -z "$line" ] && continue

  # detect section headers
  if printf '%s\n' "$line" | grep -qi '^Authorized Administrators:'; then
    section="admins"; continue
  elif printf '%s\n' "$line" | grep -qi '^Authorized Users:'; then
    section="users"; continue
  fi

  # skip password lines
  if printf '%s\n' "$line" | grep -qi '^[[:space:]]*password[:]' ; then
    continue
  fi

  if [ "$section" = "admins" ] || [ "$section" = "users" ]; then
    # Extract first token that looks like a unix username
    # capture username and whether it contains "(you)"
    # examples: "chowe (you)" -> username=chowe, you=yes
    username="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z0-9._-]+).*/\1/')"
    if [ -n "$username" ]; then
      parsed_users+=("$username")
      if printf '%s' "$line" | grep -qi '(you)'; then
        mark_you["$username"]="1"
      fi
    fi
  fi
done < "$FILE"

# Determine current effective user (who invoked script)
CURRENT_USER="$(whoami 2>/dev/null || echo "")"

# Build final list: exclude any marked as (you) and exclude current invoker
declare -a targets
declare -A seen
for u in "${parsed_users[@]}"; do
  # skip duplicates
  if [ -n "${seen[$u]+x}" ]; then
    continue
  fi
  seen["$u"]=1

  # exclude if marked as you
  if [ -n "${mark_you[$u]+x}" ]; then
    echo "Skipping '$u' because it is marked as (you) in file."
    continue
  fi
  # exclude if equals current invoker
  if [ -n "$CURRENT_USER" ] && [ "$u" = "$CURRENT_USER" ]; then
    echo "Skipping '$u' because it matches the current user ($CURRENT_USER)."
    continue
  fi

  targets+=("$u")
done

if [ ${#targets[@]} -eq 0 ]; then
  echo "No target users found to modify (after excluding 'you' and current user). Exiting."
  exit 0
fi

echo
echo "Mode: $MODE"
echo "Parsed ${#parsed_users[@]} user(s) from '$FILE'."
echo "Will process ${#targets[@]} user(s): ${targets[*]}"
echo

missing=0
applied=0

for u in "${targets[@]}"; do
  # verify user exists in /etc/passwd
  if ! getent passwd "$u" >/dev/null; then
    echo "User '$u' does NOT exist on this system. Skipping."
    missing=$((missing+1))
    continue
  fi

  cmd=(chage -m 2 -M 90 -W 7 "$u")
  if [ "$MODE" = "dry-run" ]; then
    echo "[DRY-RUN] Would run: ${cmd[*]}"
  else
    echo "Applying: ${cmd[*]}"
    if "${cmd[@]}"; then
      echo "  -> Success for $u"
      applied=$((applied+1))
    else
      echo "  -> FAILED for $u"
    fi
  fi
done

echo
echo "Summary:"
echo "  Total parsed from file: ${#parsed_users[@]}"
echo "  Targets considered: ${#targets[@]}"
echo "  Missing (not on system): $missing"
if [ "$MODE" = "apply" ]; then
  echo "  Successfully applied chage to: $applied user(s)"
fi

echo
if [ "$MODE" = "dry-run" ]; then
  echo "Dry-run mode: nothing changed. When ready run with --apply and with sudo."
  echo "Example: sudo ./apply_chage_from_file.sh --apply user.txt"
fi

exit 0
