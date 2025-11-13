#!/usr/bin/env bash
#
# check_users.sh
# Usage: ./check_users.sh authorized_list.txt
#
# - Parses the file format provided by the user.
# - Compares against system users (non-system accounts).
# - Checks admin (sudo/admin/wheel) group membership and reports mismatches.
# - Does not change anything on the system (only prints checks and suggestions).
#

set -o errexit
set -o pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <authorized-list.txt>"
  exit 2
fi

AUTHFILE="$1"
if [ ! -f "$AUTHFILE" ]; then
  echo "File not found: $AUTHFILE"
  exit 2
fi

# Get UID_MIN from /etc/login.defs if possible, fallback to 1000
UID_MIN=$(awk '/^UID_MIN/ {print $2; exit}' /etc/login.defs 2>/dev/null || true)
if ! [[ "$UID_MIN" =~ ^[0-9]+$ ]]; then
  UID_MIN=1000
fi

# determine admin group to check (common on Ubuntu/Mint: sudo; older Debian: admin; some systems: wheel)
if getent group sudo >/dev/null; then
  ADMIN_GRP="sudo"
elif getent group admin >/dev/null; then
  ADMIN_GRP="admin"
elif getent group wheel >/dev/null; then
  ADMIN_GRP="wheel"
else
  ADMIN_GRP=""   # no admin-like group found
fi

# helper: trim whitespace
trim() {
  local var="$*"
  # remove leading/trailing whitespace
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

# Parse the authorized file into two arrays: authorized_admins and authorized_users
declare -a AUTH_ADM
declare -a AUTH_USERS

section="none"
while IFS= read -r rawline || [ -n "$rawline" ]; do
  line="$(trim "$rawline")"
  # Skip empty lines
  [ -z "$line" ] && continue

  # detect headings
  if printf '%s\n' "$line" | grep -qi '^Authorized Administrators:'; then
    section="admins"
    continue
  elif printf '%s\n' "$line" | grep -qi '^Authorized Users:'; then
    section="users"
    continue
  fi

  # skip password lines or lines that start with "password:"
  if printf '%s\n' "$line" | grep -qi '^[[:space:]]*password[:]' ; then
    continue
  fi

  # Only process lines when in a valid section
  if [ "$section" = "admins" ] || [ "$section" = "users" ]; then
    # Extract username token (stop at first whitespace or '(' ), allow typical unix username chars
    # Examples:
    #   "chowe (you)" -> "chowe"
    #   "miles" -> "miles"
    # If line contains other words, take the first token that matches username pattern.
    user=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z0-9._-]+).*/\1/')
    # Validate we got a plausible username
    if [ -n "$user" ]; then
      if [ "$section" = "admins" ]; then
        AUTH_ADM+=("$user")
      else
        AUTH_USERS+=("$user")
      fi
    fi
  fi
done < "$AUTHFILE"

# make sets unique (bash associative arrays)
declare -A set_admin set_user
for u in "${AUTH_ADM[@]}"; do set_admin["$u"]=1; done
for u in "${AUTH_USERS[@]}"; do set_user["$u"]=1; done

# get system users (non-system) using UID >= UID_MIN (exclude nobody/65534)
mapfile -t SYSTEM_USERS < <(awk -F: -v min="$UID_MIN" '$3>=min && $3!=65534 {print $1}' /etc/passwd | sort -u)

# get members of admin group (if present)
ADMIN_MEMBERS=""
if [ -n "$ADMIN_GRP" ]; then
  # getent group returns: groupname:x:GID:user1,user2,...
  grp_line="$(getent group "$ADMIN_GRP" || true)"
  # extract 4th field (members)
  ADMIN_MEMBERS=$(printf '%s' "$grp_line" | awk -F: '{print $4}')
  # it might be empty or comma-separated
fi

IFS=',' read -r -a ADMIN_MEM_ARR <<< "$ADMIN_MEMBERS"

# Useful helper functions to test membership
in_array() {
  local needle="$1"; shift
  for e in "$@"; do
    [ "$e" = "$needle" ] && return 0
  done
  return 1
}

# Build sets for system users and for authorized combined
declare -A set_system set_authorized
for u in "${SYSTEM_USERS[@]}"; do set_system["$u"]=1; done
for u in "${!set_admin[@]}"; do set_authorized["$u"]=1; done
for u in "${!set_user[@]}"; do set_authorized["$u"]=1; done

# Start reporting
echo "===== AUTHORIZED LIST (parsed) ====="
echo "Administrators:"
for u in "${!set_admin[@]}"; do printf "  - %s\n" "$u"; done
echo "Authorized standard users:"
for u in "${!set_user[@]}"; do printf "  - %s\n" "$u"; done
echo

echo "===== SYSTEM (non-system) USERS (UID >= $UID_MIN) ====="
for u in "${SYSTEM_USERS[@]}"; do printf "  - %s\n" "$u"; done
echo

# 1) Missing authorized users (present in authorized list but not on system)
echo "===== MISSING AUTHORIZED ACCOUNTS ====="
missing=0
for u in "${!set_authorized[@]}"; do
  if [ -z "${set_system[$u]+x}" ]; then
    printf "MISSING: authorized user '%s' is NOT present on the system\n" "$u"
    missing=$((missing+1))
  fi
done
[ $missing -eq 0 ] && echo "No authorized users are missing."
echo

# 2) Extra accounts on system that are not authorized (ignore system accounts)
echo "===== EXTRA (UNAUTHORIZED) ACCOUNTS FOUND ON SYSTEM ====="
extra=0
for u in "${SYSTEM_USERS[@]}"; do
  if [ -z "${set_authorized[$u]+x}" ]; then
    printf "EXTRA: system user '%s' is present but NOT in the authorized lists\n" "$u"
    extra=$((extra+1))
  fi
done
[ $extra -eq 0 ] && echo "No unexpected non-system users found."
echo

# 3) Privilege checks (admins must be in admin group; regular users should not be in admin group)
echo "===== PRIVILEGE (ADMIN GROUP) CHECKS ====="
if [ -z "$ADMIN_GRP" ]; then
  echo "No admin-like group (sudo/admin/wheel) found on this system to check membership."
else
  echo "Checking membership of group '$ADMIN_GRP'..."
  # Build admin group member set
  declare -A set_admingrp
  for m in "${ADMIN_MEM_ARR[@]}"; do
    m="$(trim "$m")"
    [ -n "$m" ] && set_admingrp["$m"]=1
  done

  # a) Each authorized admin present on system should be in admin group
  bad_admins=0
  for u in "${!set_admin[@]}"; do
    if [ -n "${set_system[$u]+x}" ]; then
      if [ -z "${set_admingrp[$u]+x}" ]; then
        printf "PRIV-MISMATCH: authorized admin '%s' exists but is NOT in '%s'.\n" "$u" "$ADMIN_GRP"
        bad_admins=$((bad_admins+1))
      fi
    fi
  done
  [ $bad_admins -eq 0 ] && echo "All present authorized admins are in '$ADMIN_GRP'."

  # b) Each authorized standard user present should NOT be in admin group
  bad_users=0
  for u in "${!set_user[@]}"; do
    if [ -n "${set_system[$u]+x}" ]; then
      if [ -n "${set_admingrp[$u]+x}" ]; then
        printf "PRIV-MISMATCH: authorized standard user '%s' is in '%s' (should NOT be).\n" "$u" "$ADMIN_GRP"
        bad_users=$((bad_users+1))
      fi
    fi
  done
  [ $bad_users -eq 0 ] && echo "No authorized standard users are in '$ADMIN_GRP'."

  # c) Any admin-group member who is not in the authorized admin list
  unapproved_admins=0
  for m in "${!set_admingrp[@]}"; do
    if [ -z "${set_admin[$m]+x}" ]; then
      printf "EXTRA-PRIV: '%s' is a member of '%s' but is NOT in the authorized admins list.\n" "$m" "$ADMIN_GRP"
      unapproved_admins=$((unapproved_admins+1))
    fi
  done
  [ $unapproved_admins -eq 0 ] && echo "No unapproved members in '$ADMIN_GRP'."
fi
echo

# Summary
echo "===== SUMMARY ====="
echo "Total authorized admins parsed: ${#AUTH_ADM[@]}"
echo "Total authorized users parsed: ${#AUTH_USERS[@]}"
echo "Total non-system users on system: ${#SYSTEM_USERS[@]}"
printf "Missing authorized accounts: %d\n" "$missing"
printf "Extra non-authorized system users: %d\n" "$extra"
if [ -n "$ADMIN_GRP" ]; then
  printf "Admin group to check: %s\n" "$ADMIN_GRP"
else
  echo "No admin-like group available on system."
fi

echo
echo "===== SUGGESTED FIX COMMANDS (examples; run as root or with sudo) ====="
echo "Add a missing user (create home & prompt for password):"
echo "  sudo adduser <username>"
echo "Add an existing user to admin group:"
if [ -n "$ADMIN_GRP" ]; then
  echo "  sudo usermod -aG $ADMIN_GRP <username>"
  echo "Remove a user from admin group:"
  echo "  sudo gpasswd -d <username> $ADMIN_GRP"
else
  echo "  (No admin-like group detected; skip group commands)"
fi
echo "Delete an extra user and remove home:"
echo "  sudo deluser --remove-home <username>"
echo
echo "NOTE: script only reports issues. It does NOT modify users. Carefully review suggestions before running."
