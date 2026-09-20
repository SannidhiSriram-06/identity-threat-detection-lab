#!/usr/bin/env bash
# ==============================================================================
# HashiCorp Vault AWS Secrets Engine Initialization Script
# Configures dynamic, short-lived Just-In-Time (JIT) AWS IAM credentials
# Executed on HOST against the vault-identity-lab container
# ==============================================================================

set -euo pipefail

INIT_OUTPUT_FILE="${VAULT_INIT_FILE:-/opt/identity-lab/vault-init.json}"

v() {
  docker exec \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="${VAULT_TOKEN:-}" \
    vault-identity-lab vault "$@"
}

echo "[*] Waiting for Vault service availability at http://127.0.0.1:8200..."
until curl -s http://127.0.0.1:8200/v1/sys/init | jq -e '.initialized != null' >/dev/null 2>&1; do
  sleep 2
done

INIT_STATUS=$(curl -s http://127.0.0.1:8200/v1/sys/init | jq -r '.initialized')

if [ "$INIT_STATUS" != "true" ]; then
  echo "[+] Initializing Vault with 1 key share / threshold 1..."
  mkdir -p "$(dirname "$INIT_OUTPUT_FILE")"
  v operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_OUTPUT_FILE"
  chmod 600 "$INIT_OUTPUT_FILE"

  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_OUTPUT_FILE")
  ROOT_TOKEN=$(jq -r '.root_token' "$INIT_OUTPUT_FILE")

  echo "[+] Unsealing Vault..."
  v operator unseal "$UNSEAL_KEY" >/dev/null
  export VAULT_TOKEN="$ROOT_TOKEN"
else
  echo "[*] Vault is already initialized."
  if [ -f "$INIT_OUTPUT_FILE" ]; then
    UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_OUTPUT_FILE")
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_OUTPUT_FILE")
    export VAULT_TOKEN="$ROOT_TOKEN"

    SEAL_STATUS=$(curl -s http://127.0.0.1:8200/v1/sys/seal-status | jq -r '.sealed')
    if [ "$SEAL_STATUS" = "true" ]; then
      echo "[+] Unsealing Vault..."
      v operator unseal "$UNSEAL_KEY" >/dev/null
    else
      echo "[*] Vault is already unsealed."
    fi
  else
    echo "ERROR: Initialization file $INIT_OUTPUT_FILE not found." >&2
    exit 1
  fi
fi

# Enable AWS Secrets Engine if not already enabled
if ! v secrets list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
  echo "[+] Enabling AWS secrets engine at aws/..."
  v secrets enable -path=aws aws
else
  echo "[*] AWS secrets engine already enabled at aws/"
fi

# Configure root credentials to fall back to EC2 instance role
echo "[+] Configuring AWS root credentials (EC2 instance role)..."
v write aws/config/root region=us-east-1

# Configure lease TTL for dynamic IAM users
echo "[+] Configuring AWS secrets engine lease TTL (15m lease, 1h max)..."
v write aws/config/lease lease=15m lease_max=1h

# Create dev-jit-role (credential_type=iam_user)
echo "[+] Configuring dynamic JIT role: dev-jit-role..."
v write aws/roles/dev-jit-role \
  credential_type=iam_user \
  policy_document='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:Describe*",
          "s3:ListAllMyBuckets"
        ],
        "Resource": "*"
      }
    ]
  }'

# Create secops-jit-role (credential_type=iam_user)
echo "[+] Configuring dynamic JIT role: secops-jit-role..."
v write aws/roles/secops-jit-role \
  credential_type=iam_user \
  policy_document='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "cloudtrail:LookupEvents",
          "iam:ListUsers"
        ],
        "Resource": "*"
      }
    ]
  }'

# Write policies via the /vault/policies container mount
echo "[+] Writing Vault access policies..."
v policy write dev-policy /vault/policies/dev-policy.hcl
v policy write secops-policy /vault/policies/secops-policy.hcl

echo ""
echo "=== Vault AWS Lease Configuration ==="
v read aws/config/lease

echo ""
echo "=== Vault AWS Configured Roles ==="
v list aws/roles

echo ""
echo "✅ HashiCorp Vault AWS Secrets Engine Initialized Successfully!"
