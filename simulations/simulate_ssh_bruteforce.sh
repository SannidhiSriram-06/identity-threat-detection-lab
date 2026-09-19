#!/usr/bin/env bash
# ==============================================================================
# Simulation 1: SSH Brute-Force Attack
# MITRE ATT&CK: T1110 (Brute Force) / T1110.001 (Password Guessing)
# Triggers Wazuh Rule 100101 / 5712 (Multiple SSH authentication failures)
# ==============================================================================

set -euo pipefail

TARGET_HOST="${1:-127.0.0.1}"
TARGET_PORT="${2:-22}"
ATTEMPTS="${3:-10}"

echo "=========================================================================="
echo "🎯 SIMULATING SSH BRUTE-FORCE ATTACK"
echo "Target: ${TARGET_HOST}:${TARGET_PORT}"
echo "Attempts: ${ATTEMPTS}"
echo "MITRE ATT&CK: T1110.001 (Password Guessing)"
echo "=========================================================================="

USER_WORDLIST=("admin" "root" "support" "deploy" "backup" "testuser" "operator" "ubuntu" "guest" "developer")
PASSWORD_WORDLIST=("123456" "password" "admin123" "welcome" "toor" "letmein" "spring2026" "qwerty")

# Method 1: Check if hydra is installed, otherwise use sshpass or nc/ssh simulation loop
if command -v hydra >/dev/null 2>&1 && [ "${TARGET_HOST}" != "127.0.0.1" ]; then
  echo "[+] Using THC-Hydra for high-rate dictionary spraying..."
  hydra -L <(printf "%s\n" "${USER_WORDLIST[@]}") -P <(printf "%s\n" "${PASSWORD_WORDLIST[@]}") -s "${TARGET_PORT}" -t 4 "${TARGET_HOST}" ssh || true
else
  echo "[+] Executing rapid credential spray via SSH client..."
  for i in $(seq 1 "${ATTEMPTS}"); do
    idx_u=$(( i % ${#USER_WORDLIST[@]} ))
    idx_p=$(( i % ${#PASSWORD_WORDLIST[@]} ))
    ATTACK_USER="${USER_WORDLIST[$idx_u]}"
    ATTACK_PASS="${PASSWORD_WORDLIST[$idx_p]}"

    echo "  [Attempt ${i}/${ATTEMPTS}] Trying credentials ${ATTACK_USER}:${ATTACK_PASS}..."
    
    # Generate authentic SSH auth failure log in auth.log
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=2 \
        -p "${TARGET_PORT}" \
        "${ATTACK_USER}@${TARGET_HOST}" 'exit' 2>/dev/null || true
    
    sleep 0.4
  done
fi

echo ""
echo "=========================================================================="
echo "✅ SSH Brute Force Simulation Complete!"
echo "Wazuh Alert Expected:"
echo "  - Rule 100101 (Level 10): Possible SSH Brute Force Attack detected"
echo "  - Mitre Technique: T1110.001"
echo "Check Wazuh Dashboard at: https://<EC2-IP> -> Security Events -> SSH Failures"
echo "Or inspect auth log on host: sudo tail -n 20 /var/log/auth.log"
echo "=========================================================================="
