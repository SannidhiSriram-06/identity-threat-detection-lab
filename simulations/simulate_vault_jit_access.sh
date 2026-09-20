#!/usr/bin/env bash
# ==============================================================================
# Simulation: Dynamic Just-In-Time (JIT) AWS Credential Generation & Auditing
# Demonstrates zero standing privileges using HashiCorp Vault AWS Secrets Engine
# Executed on the HOST
# ==============================================================================

set -euo pipefail

INIT_FILE="${VAULT_INIT_FILE:-/opt/identity-lab/vault-init.json}"
LEAVE_UNREVOKED=false

for arg in "$@"; do
  if [ "$arg" = "--leave-unrevoked" ]; then
    LEAVE_UNREVOKED=true
  fi
done

if [ ! -f "$INIT_FILE" ]; then
  echo "[FAIL] Vault initialization file not found at $INIT_FILE" >&2
  exit 1
fi

ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
export VAULT_TOKEN="$ROOT_TOKEN"

v() {
  docker exec \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="${VAULT_TOKEN:-}" \
    vault-identity-lab vault "$@"
}

echo "=========================================================================="
echo "🎯 SIMULATING JUST-IN-TIME (JIT) AWS CREDENTIAL WORKFLOW"
echo "=========================================================================="

# ------------------------------------------------------------------------------
# Step 1: Generate dynamic IAM credentials for dev-jit-role
# ------------------------------------------------------------------------------
echo "[Step 1] Requesting dynamic credentials for dev-jit-role..."
CREDS_JSON=$(v read -format=json aws/creds/dev-jit-role)

ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r '.data.access_key')
SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.data.secret_key')
LEASE_ID=$(echo "$CREDS_JSON" | jq -r '.lease_id')
LEASE_DURATION=$(echo "$CREDS_JSON" | jq -r '.lease_duration')

echo "  Generated Access Key ID: ${ACCESS_KEY_ID}"
echo "  Lease ID: ${LEASE_ID}"
echo "  Lease Duration: ${LEASE_DURATION}s"

if [ "$LEASE_DURATION" -eq 900 ]; then
  echo "[PASS] Step 1: Successfully generated credentials with lease_duration=900s."
else
  echo "[FAIL] Step 1: Expected lease_duration 900s, got ${LEASE_DURATION}s."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Retry STS GetCallerIdentity for up to 30s
# ------------------------------------------------------------------------------
echo ""
echo "[Step 2] Verifying IAM propagation via STS GetCallerIdentity (up to 30s)..."
CALLER_IDENTITY=""
for i in $(seq 1 30); do
  if CALLER_IDENTITY=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" AWS_DEFAULT_REGION="us-east-1" aws sts get-caller-identity --output json 2>/dev/null); then
    break
  fi
  sleep 1
done

if [ -n "$CALLER_IDENTITY" ]; then
  USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
  IAM_USER_NAME=$(echo "$USER_ARN" | awk -F'/' '{print $NF}')
  echo "  Authenticated Principal ARN: ${USER_ARN}"
  echo "[PASS] Step 2: STS GetCallerIdentity succeeded."
else
  echo "[FAIL] Step 2: STS GetCallerIdentity timed out after 30s propagation delay."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 3: Least privilege verification (ec2:DescribeRegions vs iam:ListUsers)
# ------------------------------------------------------------------------------
echo ""
echo "[Step 3] Testing permission boundaries (least privilege verification)..."
EC2_OK=false
for i in $(seq 1 30); do
  if AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" AWS_DEFAULT_REGION="us-east-1" aws ec2 describe-regions --region us-east-1 >/dev/null 2>&1; then
    EC2_OK=true
    break
  fi
  sleep 1
done

if [ "$EC2_OK" = true ]; then
  IAM_CHECK=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" AWS_DEFAULT_REGION="us-east-1" aws iam list-users 2>&1 || true)
  if echo "$IAM_CHECK" | grep -qE "AccessDenied|is not authorized"; then
    echo "[PASS] Step 3: ec2:DescribeRegions succeeded and unauthorized iam:ListUsers failed with AccessDenied."
  else
    echo "[FAIL] Step 3: Expected iam:ListUsers to be denied, but got: $IAM_CHECK"
    exit 1
  fi
else
  echo "[FAIL] Step 3: Authorized action ec2:DescribeRegions failed after 30s policy propagation window."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 4: Token policy boundary check (dev-policy vs secops role)
# ------------------------------------------------------------------------------
echo ""
echo "[Step 4] Creating dev-policy token and verifying role access boundaries..."
DEV_TOKEN_JSON=$(v token create -policy=dev-policy -ttl=15m -format=json)
DEV_TOKEN=$(echo "$DEV_TOKEN_JSON" | jq -r '.auth.client_token')

CAN_READ_DEV=false
DEV_CREDS_TEST=$(docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$DEV_TOKEN" vault-identity-lab vault read -format=json aws/creds/dev-jit-role 2>/dev/null || true)
if echo "$DEV_CREDS_TEST" | jq -e '.data.access_key' >/dev/null 2>&1; then
  CAN_READ_DEV=true
  DEV_TEST_LEASE=$(echo "$DEV_CREDS_TEST" | jq -r '.lease_id')
  v lease revoke -sync "$DEV_TEST_LEASE" >/dev/null 2>&1 || true
fi

SECOPS_CHECK_ERR=$(docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$DEV_TOKEN" vault-identity-lab vault read aws/creds/secops-jit-role 2>&1 || true)

if [ "$CAN_READ_DEV" = true ] && echo "$SECOPS_CHECK_ERR" | grep -qi "permission denied"; then
  echo "[PASS] Step 4: dev-policy token can read aws/creds/dev-jit-role and is denied on aws/creds/secops-jit-role."
else
  echo "[FAIL] Step 4: dev-policy authorization boundary check failed."
  exit 1
fi

# ------------------------------------------------------------------------------
# Optional: Leave unrevoked for automated expiry verification
# ------------------------------------------------------------------------------
if [ "$LEAVE_UNREVOKED" = true ]; then
  echo ""
  echo "[*] --leave-unrevoked specified: Skipping immediate revocation steps 5 and 6."
  EXPIRY_FILE="/opt/identity-lab/expiry-test.txt"
  mkdir -p "$(dirname "$EXPIRY_FILE")"

  NOW_TS=$(date +%s)
  EXPIRE_TS=$((NOW_TS + 900))
  EXPIRE_DATE=$(date -d "@$EXPIRE_TS" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -r "$EXPIRE_TS" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$EXPIRE_TS")

  cat <<EOF > "$EXPIRY_FILE"
IAM_USERNAME=${IAM_USER_NAME}
LEASE_ID=${LEASE_ID}
EXPECTED_EXPIRY=${EXPIRE_DATE}
EXPIRY_TIMESTAMP=${EXPIRE_TS}
EOF
  chmod 600 "$EXPIRY_FILE"
  echo "  Saved test details to $EXPIRY_FILE for automated expiry check."
  echo "[PASS] JIT simulation completed with active credentials preserved."
  exit 0
fi

# ------------------------------------------------------------------------------
# Step 5: Revoke lease and verify STS failure (up to 60s)
# ------------------------------------------------------------------------------
echo ""
echo "[Step 5] Revoking Vault lease and confirming STS credential invalidation..."
v lease revoke -sync "$LEASE_ID"

STS_REVOKED=false
for i in $(seq 1 60); do
  STS_ERR=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" AWS_DEFAULT_REGION="us-east-1" aws sts get-caller-identity 2>&1 || true)
  if echo "$STS_ERR" | grep -qE "InvalidClientTokenId|The security token included in the request is invalid"; then
    STS_REVOKED=true
    break
  fi
  sleep 1
done

if [ "$STS_REVOKED" = true ]; then
  echo "[PASS] Step 5: Temporary credentials successfully invalidated in AWS (InvalidClientTokenId)."
else
  echo "[FAIL] Step 5: Credentials were not invalidated within 60s."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 6: Verify IAM user deletion via instance role
# ------------------------------------------------------------------------------
echo ""
echo "[Step 6] Verifying automated IAM user deletion via EC2 instance role (up to 30s)..."
USER_DELETED=false
USER_STATUS=""
for i in $(seq 1 30); do
  USER_STATUS=$(aws iam get-user --user-name "$IAM_USER_NAME" 2>&1 || true)
  if echo "$USER_STATUS" | grep -q "NoSuchEntity"; then
    USER_DELETED=true
    break
  fi
  sleep 1
done

if [ "$USER_DELETED" = true ]; then
  echo "[PASS] Step 6: IAM user $IAM_USER_NAME confirmed deleted (NoSuchEntity)."
else
  echo "[FAIL] Step 6: IAM user $IAM_USER_NAME still exists or unexpected error after 30s: $USER_STATUS"
  exit 1
fi

echo ""
echo "=========================================================================="
echo "✅ All Just-In-Time Credential Simulation Steps Passed!"
echo "=========================================================================="
