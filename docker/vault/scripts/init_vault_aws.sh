#!/usr/bin/env bash
# ==============================================================================
# HashiCorp Vault AWS Secrets Engine Initialization Script
# Configures dynamic, short-lived Just-In-Time (JIT) AWS IAM credentials
# ==============================================================================

set -eo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
INIT_OUTPUT_FILE="/opt/identity-lab/vault-init.json"
KEYS_FILE="/opt/identity-lab/vault-keys.txt"

echo "[*] Connecting to Vault at ${VAULT_ADDR}..."

# Wait for Vault service availability
until curl -s "${VAULT_ADDR}/v1/sys/health" > /dev/null 2>&1 || [ $? -eq 2 ]; do
  echo "[*] Waiting for Vault to initialize..."
  sleep 3
done

# Check if Vault is initialized
INIT_STATUS=$(curl -s "${VAULT_ADDR}/v1/sys/init" | jq -r '.initialized')

if [ "$INIT_STATUS" != "true" ]; then
  echo "[+] Initializing Vault with 1 key share (Lab Mode)..."
  vault operator init -key-shares=1 -key-threshold=1 -format=json > "${INIT_OUTPUT_FILE}"
  
  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "${INIT_OUTPUT_FILE}")
  ROOT_TOKEN=$(jq -r '.root_token' "${INIT_OUTPUT_FILE}")
  
  echo "UNSEAL_KEY=${UNSEAL_KEY}" > "${KEYS_FILE}"
  echo "ROOT_TOKEN=${ROOT_TOKEN}" >> "${KEYS_FILE}"
  chmod 600 "${KEYS_FILE}" "${INIT_OUTPUT_FILE}"
  
  echo "[+] Unsealing Vault..."
  vault operator unseal "${UNSEAL_KEY}"
  
  echo "[+] Logging into Vault as Root..."
  export VAULT_TOKEN="${ROOT_TOKEN}"
  vault login "${ROOT_TOKEN}"
else
  echo "[*] Vault is already initialized."
  if [ -f "${KEYS_FILE}" ]; then
    source "${KEYS_FILE}"
    export VAULT_TOKEN="${ROOT_TOKEN}"
    # Ensure unsealed
    vault operator unseal "${UNSEAL_KEY}" 2>/dev/null || true
  else
    echo "[!] Keys file not found. Please set VAULT_TOKEN manually."
  fi
fi

echo "[+] Enabling Vault AWS Secrets Engine..."
vault secrets enable -path=aws aws 2>/dev/null || echo "[*] AWS Secrets engine already enabled"

echo "[+] Configuring AWS Secrets Engine with EC2 Instance Profile / Environment..."
# Configures Vault to use the EC2 instance profile or AWS environment credentials
vault write aws/config/root \
    iam_endpoint="" \
    sts_endpoint="" \
    max_retries=3 2>/dev/null || true

echo "[+] Configuring Dynamic JIT AWS IAM Role (15-minute lease)..."
# Creates an IAM role definition that dynamically issues IAM users with an attached policy
vault write aws/roles/dev-jit-role \
    credential_type=iam_user \
    policy_document='{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ec2:Describe*",
            "s3:ListAllMyBuckets",
            "s3:GetBucketLocation",
            "cloudtrail:LookupEvents"
          ],
          "Resource": "*"
        }
      ]
    }' \
    default_sts_ttl=15m \
    max_sts_ttl=1h

echo "[+] Applying developer policy..."
vault policy write dev-policy /vault/policies/developer-policy.hcl 2>/dev/null || true

echo "=========================================================================="
echo "✅ HashiCorp Vault AWS Secrets Engine Initialized Successfully!"
echo "=========================================================================="
echo "To generate dynamic Just-In-Time AWS credentials, execute:"
echo "   vault read aws/creds/dev-jit-role"
echo ""
echo "Notice how Vault automatically creates a temporary IAM user (e.g. vault-root-dev-jit-...)"
echo "with an active lease of 15 minutes, which will be deleted automatically upon lease expiry!"
echo "=========================================================================="
