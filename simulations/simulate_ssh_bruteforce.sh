#!/usr/bin/env bash
# ==============================================================================
# Simulation 1: Repeated Failed SSH Authentication Attempts (Username Spray)
# MITRE ATT&CK: T1110.001 (Brute Force: Password Guessing / Username Enumeration)
# Triggers Wazuh Rules 100100 & 100101 via /var/log/auth.log
# ==============================================================================

set -euo pipefail

TARGET_HOST="${1:-127.0.0.1}"
TARGET_PORT="${2:-22}"
ATTEMPTS="${3:-15}"

echo "=========================================================================="
echo "🎯 SIMULATING REPEATED FAILED SSH AUTHENTICATION ATTEMPTS (USERNAME SPRAY)"
echo "Target:   ${TARGET_HOST}:${TARGET_PORT}"
echo "Attempts: ${ATTEMPTS}"
echo "Mode:     Unauthenticated connection attempts generating Invalid user / failed-none events"
echo "=========================================================================="

USER_WORDLIST=("admin" "root" "support" "deploy" "backup" "testuser" "operator" "guest" "developer" "contractor" "sysadmin" "oracle" "postgres" "service" "git")

echo "[+] Executing repeated unauthenticated SSH connection attempts..."
for i in $(seq 1 "${ATTEMPTS}"); do
  idx_u=$(( (i - 1) % ${#USER_WORDLIST[@]} ))
  ATTACK_USER="${USER_WORDLIST[$idx_u]}"

  echo "  [Attempt ${i}/${ATTEMPTS}] Initiating SSH connection with user '${ATTACK_USER}'..."

  # Generates real "Invalid user" or authentication failure entries in /var/log/auth.log
  ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 \
      -p "${TARGET_PORT}" \
      "${ATTACK_USER}@${TARGET_HOST}" 'exit' 2>/dev/null || true

  sleep 0.4
done

echo ""
echo "=========================================================================="
echo "✅ SSH Username Spray Simulation Complete!"
echo "Wazuh Alerts Expected:"
echo "  - Rule 100100 (Level 5): Single SSH authentication failure detected"
echo "  - Rule 100101 (Level 10): Possible SSH Brute Force Attack detected (>=5 in 60s)"
echo "Check Wazuh Dashboard at: https://<EC2-IP> -> Security Events -> SSH Failures"
echo "=========================================================================="

if [ -f /var/log/auth.log ]; then
  COUNT=$(python3 -c '
import datetime, re

now = datetime.datetime.now()
cutoff = now - datetime.timedelta(minutes=2)
count = 0

try:
    with open("/var/log/auth.log", "r", errors="ignore") as f:
        for line in f:
            if not ("Invalid user" in line or "Failed " in line):
                continue
            m = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})", line)
            if m:
                try:
                    t = datetime.datetime.fromisoformat(m.group(1))
                    if t >= cutoff:
                        count += 1
                        continue
                except Exception:
                    pass
            m2 = re.match(r"^([A-Z][a-z]{2}\s+\d+\s+\d{2}:\d{2}:\d{2})", line)
            if m2:
                try:
                    t = datetime.datetime.strptime(f"{now.year} {m2.group(1)}", "%Y %b %d %H:%M:%S")
                    if t >= cutoff:
                        count += 1
                        continue
                except Exception:
                    pass
except Exception:
    pass
print(count)
' 2>/dev/null || grep -c -E "Invalid user|Failed " /var/log/auth.log 2>/dev/null || echo 0)
  echo "Invalid user/Failed lines from the last 2 minutes in /var/log/auth.log: ${COUNT}"
else
  echo "Invalid user/Failed lines from the last 2 minutes in /var/log/auth.log: 0 (/var/log/auth.log not found)"
fi
