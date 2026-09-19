#!/usr/bin/env bash
# ==============================================================================
# Simulation 2: Linux Privilege Escalation Attempt
# MITRE ATT&CK: T1548 (Abuse Elevation Control Mechanism), T1078 (Valid Accounts), T1003.008 (/etc/shadow)
# Triggers Wazuh Rules 100200, 100201, 100202 (Sudo violations & shadow access)
# ==============================================================================

set -uo pipefail

echo "=========================================================================="
echo "🎯 SIMULATING PRIVILEGE ESCALATION ATTEMPTS"
echo "MITRE ATT&CK: T1548.003 (Sudo and Sudo Caching), T1003.008 (/etc/shadow)"
echo "=========================================================================="

TEST_USER="lab_contractor"

# 1. Setup unprivileged low-rights user if not present
if ! id "${TEST_USER}" >/dev/null 2>&1; then
  echo "[+] Creating unprivileged lab user: ${TEST_USER}..."
  sudo useradd -m -s /bin/bash "${TEST_USER}" 2>/dev/null || true
  echo "${TEST_USER}:LabDemoPass123!" | sudo chpasswd 2>/dev/null || true
fi

echo ""
echo "[Step 1/3] Simulating unauthorized sudo execution as unprivileged user..."
# The user is deliberately NOT in sudoers. Attempting sudo triggers auth failure log!
for i in {1..4}; do
  echo "  [Violation ${i}] User ${TEST_USER} running: sudo -l"
  su - "${TEST_USER}" -c "echo 'WrongPass' | sudo -S -l" 2>/dev/null || true
  sleep 0.5
done

echo ""
echo "[Step 2/3] Simulating unauthorized attempt to dump /etc/shadow..."
su - "${TEST_USER}" -c "cat /etc/shadow" 2>/dev/null || echo "  [Expected Error] Permission denied accessing /etc/shadow (Logged)"

echo ""
echo "[Step 3/3] Simulating malicious SUID binary search and environment manipulation..."
su - "${TEST_USER}" -c "find / -perm -4000 -type f 2>/dev/null | head -n 10" || true

echo ""
echo "=========================================================================="
echo "✅ Privilege Escalation Simulation Complete!"
echo "Wazuh Alerts Expected:"
echo "  - Rule 100200 / 5402: Sudo authentication failure / user NOT in sudoers"
echo "  - Rule 100201 (Level 12): Multiple Privilege Escalation attempts detected"
echo "  - Rule 100202: Suspicious file access (/etc/shadow)"
echo "Check Wazuh Dashboard at: https://<EC2-IP> -> Modules -> MITRE ATT&CK -> T1548"
echo "=========================================================================="
