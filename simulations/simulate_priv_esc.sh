#!/usr/bin/env bash
# ==============================================================================
# Simulation 2: Linux Privilege Escalation Attempt
# MITRE ATT&CK: T1548.003 (Sudo and Sudo Caching)
# Triggers Wazuh Rules 100200 & 100201 (Sudo violations)
# ==============================================================================

set -uo pipefail

# Ensure script runs as root so su - lab_contractor executes without interactive password prompt
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=========================================================================="
echo "🎯 SIMULATING PRIVILEGE ESCALATION ATTEMPTS"
echo "MITRE ATT&CK: T1548.003 (Sudo and Sudo Caching)"
echo "=========================================================================="

TEST_USER="lab_contractor"

# 1. Setup unprivileged low-rights user if not present
if ! id "${TEST_USER}" >/dev/null 2>&1; then
  echo "[+] Creating unprivileged lab user: ${TEST_USER}..."
  useradd -m -s /bin/bash "${TEST_USER}" 2>/dev/null || true
  echo "${TEST_USER}:LabDemoPass123!" | chpasswd 2>/dev/null || true
fi

echo ""
echo "[Step 1/3] Simulating unauthorized sudo execution as unprivileged user..."
# The user is deliberately NOT in sudoers. Attempting sudo triggers auth failure log in auth.log
for i in {1..4}; do
  echo "  [Violation ${i}] User ${TEST_USER} running: sudo -l"
  su - "${TEST_USER}" -c "echo 'WrongPass' | sudo -S -l" 2>/dev/null || true
  sleep 0.5
done

echo ""
echo "[Step 2/3] Executing unprivileged attempt to read /etc/shadow (activity simulation)..."
su - "${TEST_USER}" -c "cat /etc/shadow" 2>/dev/null || echo "  [Expected Error] Permission denied accessing /etc/shadow"

echo ""
echo "[Step 3/3] Executing unprivileged SUID binary search (activity simulation)..."
su - "${TEST_USER}" -c "find / -perm -4000 -type f 2>/dev/null | head -n 10" || true

echo ""
echo "=========================================================================="
echo "✅ Privilege Escalation Simulation Complete!"
echo "Wazuh Alerts Expected:"
echo "  - Rule 100200 (Level 7) per attempt: Sudo authentication failure / user NOT in sudoers"
echo "  - Rule 100201 (Level 12) after 3 within 60s: Multiple Privilege Escalation attempts detected"
echo "Check Wazuh Dashboard at: https://<EC2-IP> -> Security Events"
echo "=========================================================================="
