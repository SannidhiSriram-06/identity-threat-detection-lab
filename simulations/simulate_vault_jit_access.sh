#!/usr/bin/env bash
# ==============================================================================
# Simulation 3: Dynamic Just-In-Time (JIT) AWS Credential Generation & Auditing
# Demonstrates zero standing privileges using HashiCorp Vault AWS Secrets Engine
# and CloudTrail attribution of temporary IAM user activities
# ==============================================================================

set -eo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

echo "=========================================================================="
echo "🎯 SIMULATING JUST-IN-TIME (JIT) AWS CREDENTIAL WORKFLOW"
echo "Vault Server: ${VAULT_ADDR}"
echo "=========================================================================="

# Check Vault token
if [ -z "${VAULT_TOKEN:-}" ]; then
  if [ -f "/opt/identity-lab/vault-keys.txt" ]; then
    source "/opt/identity-lab/vault-keys.txt"
    export VAULT_TOKEN="${ROOT_TOKEN}"
  fi
fi

echo "[Step 1/3] Requesting dynamic, short-lived AWS IAM credentials from Vault..."
CREDS_JSON=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" vault-identity-lab \
  vault read -format=json aws/creds/dev-jit-role)

ACCESS_KEY=$(echo "${CREDS_JSON}" | jq -r '.data.access_key')
SECRET_KEY=$(echo "${CREDS_JSON}" | jq -r '.data.secret_key')
LEASE_ID=$(echo "${CREDS_JSON}" | jq -r '.lease_id')
LEASE_DURATION=$(echo "${CREDS_JSON}" | jq -r '.lease_duration')

echo "  [+] Generated Temporary Access Key ID: ${ACCESS_KEY}"
echo "  [+] Lease ID: ${LEASE_ID}"
echo "  [+] Lease Duration: ${LEASE_DURATION} seconds (15 minutes)"

echo ""
echo "[Step 2/3] Demonstrating AWS API operation under temporary identity..."
# Verify identity using STS GetCallerIdentity
AWS_ACCESS_KEY_ID="${ACCESS_KEY}" \
AWS_SECRET_ACCESS_KEY="${SECRET_KEY}" \
aws sts get-caller-identity || true

echo ""
echo "[Step 3/3] Demonstrating automated lease revocation (Zero Standing Privileges)..."
echo "  [+] Revoking lease explicitly (or wait 15 minutes for automated expiration)..."
docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" vault-identity-lab \
  vault lease revoke "${LEASE_ID}"

echo "  [+] Verifying credential is now revoked in AWS IAM..."
sleep 2
AWS_ACCESS_KEY_ID="${ACCESS_KEY}" \
AWS_SECRET_ACCESS_KEY="${SECRET_KEY}" \
aws sts get-caller-identity 2>&1 || echo "  [Success] Credentials invalid/revoked as expected!"

echo ""
echo "=========================================================================="
echo "✅ Just-In-Time Credential Simulation Complete!"
echo "CloudTrail / Wazuh Ingestion:"
echo "  - CreateUser and CreateAccessKey events logged by Vault root identity"
echo "  - Ephemeral API actions attributed to dynamic user name"
echo "  - DeleteAccessKey / DeleteUser logged upon lease revocation"
echo "=========================================================================="
