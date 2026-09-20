#!/usr/bin/env bash
# ==============================================================================
# Simulation Helper: Verify Automated JIT Expiry
# Validates that an unrevoked temporary IAM user is deleted after lease expiration
# Executed on the HOST using the EC2 instance role
# ==============================================================================

set -euo pipefail

EXPIRY_FILE="${1:-/opt/identity-lab/expiry-test.txt}"

if [ ! -f "$EXPIRY_FILE" ]; then
  echo "[FAIL] Expiry test record file not found at: $EXPIRY_FILE" >&2
  exit 1
fi

IAM_USERNAME=$(grep '^IAM_USERNAME=' "$EXPIRY_FILE" | cut -d'=' -f2-)
LEASE_ID=$(grep '^LEASE_ID=' "$EXPIRY_FILE" | cut -d'=' -f2-)
EXPECTED_EXPIRY=$(grep '^EXPECTED_EXPIRY=' "$EXPIRY_FILE" | cut -d'=' -f2-)

if [ -z "$IAM_USERNAME" ]; then
  echo "[FAIL] Failed to extract IAM_USERNAME from $EXPIRY_FILE" >&2
  exit 1
fi

echo "=== Verifying Automated Lease Expiry for IAM User ==="
echo "  IAM User:        $IAM_USERNAME"
echo "  Vault Lease ID:  $LEASE_ID"
echo "  Expected Expiry: $EXPECTED_EXPIRY"
echo

# Ensure temporary credentials are not set so check runs via instance role
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

USER_STATUS=$(aws iam get-user --user-name "$IAM_USERNAME" 2>&1 || true)

if echo "$USER_STATUS" | grep -q "NoSuchEntity"; then
  echo "[PASS] IAM user $IAM_USERNAME has been automatically deleted by Vault upon lease expiry."
  exit 0
else
  echo "[FAIL] IAM user $IAM_USERNAME still exists in AWS IAM (Response: $USER_STATUS)."
  echo "       Note: Ensure the 15-minute lease duration has completely elapsed."
  exit 1
fi
