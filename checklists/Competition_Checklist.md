# CyberPatriot Linux Competition Checklist
*For Ubuntu 22 & Linux Mint 21 (Mint-only notes included)*

## PRIORITY
- [ ] Open README and identify authorized users/software.
- [ ] Complete all Forensics Questions before system changes.
- [ ] Disable root SSH login:
  ```bash
  sudo gedit /etc/ssh/sshd_config
  # PermitRootLogin no
  ```
- [ ] Enable/disable SSH as directed:
  ```bash
  sudo apt install openssh-server -y
  sudo systemctl stop ssh
  sudo systemctl disable ssh
  ```
- [ ] Remove unauthorized users:
  ```bash
  cat /etc/passwd
  sudo deluser <user> --remove-home
  ```
- [ ] Remove admin rights:
  ```bash
  sudo deluser <user> sudo
  sudo deluser <user> admin
  ```
- [ ] Add authorized users to correct groups:
  ```bash
  sudo gpasswd -a <user> <group>
  ```
- [ ] Change weak passwords:
  ```bash
  passwd <user>
  ```
- [ ] Fix permissions:
  ```bash
  sudo chmod 640 /etc/shadow
  ```
- [ ] Enable daily updates:
  ```text
  Mint: GUI → Software & Updates → Updates → Daily
  Ubuntu: sudo apt update && sudo apt upgrade -y
  ```

---

## PASSWORD POLICIES
- [ ] Set minimum password length:
  ```bash
  sudo gedit /etc/pam.d/common-password
  # Add: pam_pwquality.so retry=3 minlen=10
  ```
- [ ] Configure password aging:
  ```bash
  sudo gedit /etc/login.defs
  # PASS_MIN_DAYS 2
  # PASS_MAX_DAYS 90
  # PASS_WARN_AGE 7
  ```
- [ ] Remove null passwords:
  ```bash
  sudo gedit /etc/pam.d/common-auth
  # Remove 'nullok'
  ```
- [ ] Add lockout policy:
  ```bash
  sudo pam-auth-update
  # or manually: pam_tally2.so deny=5 onerr=fail unlock_time=1800
  ```

---

## FIREWALL
- [ ] Enable UFW:
  ```bash
  sudo apt install ufw -y
  sudo ufw enable
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw status verbose
  ```

---

## NETWORK & KERNEL
- [ ] Enable SYN cookies:
  ```bash
  sudo gedit /etc/sysctl.conf
  # net.ipv4.tcp_syncookies=1
  sudo sysctl --system
  ```
- [ ] Disable IP forwarding:
  ```bash
  # net.ipv4.ip_forward=0
  ```
- [ ] Disable IPv6 (if allowed):
  ```bash
  # net.ipv6.conf.all.disable_ipv6=1
  ```
- [ ] Prevent IP spoofing:
  ```bash
  echo "nospoof on" | sudo tee -a /etc/host.conf
  ```
- [ ] Address Space Randomization:
  ```bash
  sudo gedit admin:///etc/sysctl.conf
  # kernel.randomize_va_space=0
  kernel.randomize_va_space=2
  ```
---

## REMOVE UNAUTHORIZED SOFTWARE / FILES
- [ ] Remove hacking tools:
  ```bash
  sudo apt purge nmap netcat wireshark john hydra -y
  sudo apt autoremove -y
  ```
- [ ] Remove media files:
  ```bash
  sudo find /home -type f \( -iname "*.mp3" -o -iname "*.mp4" -o -iname "*.jpg" -o -iname "*.ogg" \) -delete
  ```
- [ ] Remove unauthorized software:
  ```bash
  sudo apt purge -y doona xprobe
  sudo rm /usr/games/pyrdp-master.zip || true
  ```
- [ ] Disable unused services:
  ```bash
  sudo systemctl disable --now nginx || true
  sudo systemctl disable --now vsftpd || true
  sudo systemctl disable --now squid || true
  ```

---

## REQUIRED SOFTWARE
- [ ] Install required packages:
  ```bash
  sudo apt update
  sudo apt install x2goserver clamav ufw libpam-cracklib bum -y
  ```

---

## USERS & GROUPS
- [ ] Check users:
  ```bash
  cat /etc/passwd
  ```
- [ ] Check sudo group:
  ```bash
  grep 'sudo' /etc/group
  ls /etc/sudoers.d
  ```
- [ ] Remove unauthorized sudo access:
  ```bash
  sudo deluser <user> sudo
  sudo deluser <user> admin
  sudo deluser <user> --remove-home
  ```
- [ ] Create groups & add users (example):
  ```bash
  sudo addgroup spider || true
  sudo gpasswd -M may,peni,stan,miguel spider || true
  ```

---

## SYSTEM MAINTENANCE
- [ ] Update system:
  ```bash
  sudo apt update && sudo apt full-upgrade -y
  ```
- [ ] Update Firefox/Thunderbird:
  ```bash
  sudo apt install --only-upgrade firefox thunderbird
  ```

---

## FORENSICS QUICK COMMANDS
- [ ] Base64 decode: https://www.base64decode.org/
- [ ] Locate media:
  ```bash
  locate '*.mp3' || true
  locate '*.ogg' || true
  ```
- [ ] Find user ID:
  ```bash
  id -u <user>
  ```
- [ ] Search all home directories:
  ```bash
  cd /home && sudo ls -Ra
  ```
- [ ] Detect backdoor process (example):
  ```bash
  ss -tlnp
  ps -ef | grep python
  ```
- [ ] Extract hidden message from image:
  ```bash
  cat override.txt | base64 -d || true
  steghide extract -p <passphrase> -sf stanlee.jpg || true
  md5sum message.txt || true
  ```

---

## DISABLE GUEST ACCOUNT
- [ ] Disable guest login:
  ```bash
  sudo gedit /etc/lightdm/lightdm.conf
  # allow-guest=false
  ```

---

## FINAL CHECK
- Unauthorized users deleted
- Authorized users configured
- Weak passwords fixed
- Updates applied
- SSH configured properly
- Firewall enabled
- Root login disabled
- Password policies set
- IP forwarding off
- No hacking/media files
- README fully followed
- Forensics questions completed before system changes

---

## PENALTIES
1. VSFTP service stopped/removed: -5 pts  
2. Important files removed from public FTP directories: -5 pts
