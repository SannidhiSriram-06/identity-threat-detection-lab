#!/usr/bin/env bash
# ==============================================================================
# Simulation Cleanup Script
# Resets test users and temporary files created during threat simulations
# ==============================================================================

set -uo pipefail

echo "[*] Cleaning up simulation artifacts..."

TEST_USER="lab_contractor"
if id "${TEST_USER}" >/dev/null 2>&1; then
  echo "  [-] Removing demo user: ${TEST_USER}..."
  sudo userdel -r "${TEST_USER}" 2>/dev/null || sudo userdel "${TEST_USER}" 2>/dev/null || true
fi

echo "[+] Cleanup completed successfully."
