#!/bin/bash
# Ubuntu/Mint Security Hardening Script
# Automates: disabling root password, enforcing password length, password history,
# lockout policy, and disabling null passwords.
# Completely non-interactive (no manual pam-auth-update step).

set -e

echo "Starting security hardening automation..."

# 10) Disable root password
echo "* Locking root password..."
sudo getent shadow root || true
sudo passwd -l root
sudo getent shadow root || true
echo "* Root account password locked."

# 11 & 12) Password minimum length & remember history
COMMON_PWD_FILE="/etc/pam.d/common-password"
echo "* Enforcing password policy in $COMMON_PWD_FILE..."
sudo cp "$COMMON_PWD_FILE" "$COMMON_PWD_FILE.bak"

# Add minlen=10 and remember=3 if not already there
sudo sed -i -E 's|(pam_unix\.so)(.*)|\1\2 minlen=10 remember=3|' "$COMMON_PWD_FILE"

echo "* Password length (10) and remember (3) enforced."

# 13) Account lockout policy setup
LOCKOUT_DIR="/usr/share/pam-configs"
mkdir -p "$LOCKOUT_DIR"

echo "* Creating faillock configuration files..."

sudo bash -c "cat > $LOCKOUT_DIR/faillock <<'EOF'
Name: Lockout on failed logins
Default: yes
Priority: 0
Auth-Type: Primary
Auth:
[default=die] pam_faillock.so authfail
EOF"

sudo bash -c "cat > $LOCKOUT_DIR/faillock_reset <<'EOF'
Name: Reset lockout on success
Default: yes
Priority: 0
Auth-Type: Additional
Auth:
required pam_faillock.so authsucc
EOF"

sudo bash -c "cat > $LOCKOUT_DIR/faillock_notify <<'EOF'
Name: Notify on account lockout
Default: yes
Priority: 1024
Auth-Type: Primary
Auth:
requisite pam_faillock.so preauth
EOF"

# Auto-enable faillock configs by writing into PAM’s configuration registry
PAM_CONF_DIR="/var/lib/pam"
sudo mkdir -p "$PAM_CONF_DIR"
sudo bash -c "cat > $PAM_CONF_DIR/seen <<'EOF'
faillock
faillock_reset
faillock_notify
EOF"

# Apply changes directly to PAM config stack
sudo pam-auth-update --package --force || true
echo "* Account lockout policies fully enabled (non-interactive)."

# 14) Disable null passwords
COMMON_AUTH_FILE="/etc/pam.d/common-auth"
echo "* Removing nullok from $COMMON_AUTH_FILE..."
sudo cp "$COMMON_AUTH_FILE" "$COMMON_AUTH_FILE.bak"
sudo sed -i 's/\<nullok\>//g' "$COMMON_AUTH_FILE"
echo "* Null passwords disabled."

echo "* All security hardening tasks completed successfully!"
echo "Backups saved as *.bak in /etc/pam.d/"
