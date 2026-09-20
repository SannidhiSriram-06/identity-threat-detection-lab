#!/usr/bin/env bash
set -u

OVERALL_STATUS=0

pass() {
  echo "[PASS] $*"
}

fail() {
  echo "[FAIL] $*"
  OVERALL_STATUS=1
}

echo "=== Identity Threat Detection Lab Stack Verification ==="
echo

# 1. Check all 4 containers running
REQUIRED_CONTAINERS=("vault-identity-lab" "wazuh-indexer" "wazuh-manager" "wazuh-dashboard")
ALL_CONTAINERS_RUNNING=true
for c in "${REQUIRED_CONTAINERS[@]}"; do
  RUNNING=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo "false")
  if [ "$RUNNING" = "true" ]; then
    pass "Container running: $c"
  else
    fail "Container not running or not found: $c"
    ALL_CONTAINERS_RUNNING=false
  fi
done

# 2. Vault status (initialized and unsealed)
if [ "$(docker inspect -f '{{.State.Running}}' vault-identity-lab 2>/dev/null || echo false)" = "true" ]; then
  VAULT_STATUS_OUT=$(docker exec vault-identity-lab vault status 2>&1 || true)
  if echo "$VAULT_STATUS_OUT" | grep -q "Initialized.*true" && echo "$VAULT_STATUS_OUT" | grep -q "Sealed.*false"; then
    pass "Vault is initialized and unsealed"
  else
    fail "Vault is not initialized/unsealed (Output: $(echo "$VAULT_STATUS_OUT" | tr '\n' ' '))"
  fi
else
  fail "Vault container is not running, skipping status check"
fi

# 3. Indexer cluster health (green or yellow)
INDEXER_HEALTH=$(curl -sk -u admin:SecretPassword https://localhost:9200/_cluster/health 2>/dev/null || true)
if echo "$INDEXER_HEALTH" | grep -qE '"status":"(green|yellow)"'; then
  STATUS=$(echo "$INDEXER_HEALTH" | grep -oE '"status":"(green|yellow)"' | cut -d'"' -f4)
  pass "Wazuh Indexer cluster health status is: $STATUS"
else
  fail "Wazuh Indexer cluster health check failed (Response: $INDEXER_HEALTH)"
fi

# 4. Dashboard HTTP status
DASHBOARD_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:443 2>/dev/null || true)
if [ "$DASHBOARD_CODE" = "200" ] || [ "$DASHBOARD_CODE" = "302" ]; then
  pass "Wazuh Dashboard is accessible on https://localhost:443 (HTTP $DASHBOARD_CODE)"
else
  fail "Wazuh Dashboard HTTP check failed with code: $DASHBOARD_CODE"
fi

# 5. Manager daemons status
REQUIRED_DAEMONS=("wazuh-analysisd" "wazuh-remoted" "wazuh-modulesd" "wazuh-db" "wazuh-logcollector" "wazuh-apid")
if [ "$(docker inspect -f '{{.State.Running}}' wazuh-manager 2>/dev/null || echo false)" = "true" ]; then
  CONTROL_OUT=$(docker exec wazuh-manager /var/ossec/bin/wazuh-control status 2>&1 || true)
  for d in "${REQUIRED_DAEMONS[@]}"; do
    if echo "$CONTROL_OUT" | grep -q "$d is running"; then
      pass "Wazuh daemon is running: $d"
    else
      fail "Wazuh daemon is not running: $d"
    fi
  done
else
  fail "Wazuh Manager container is not running, skipping daemons check"
fi

# 6. Logcollector monitoring /host-var-log/auth.log
if [ "$(docker inspect -f '{{.State.Running}}' wazuh-manager 2>/dev/null || echo false)" = "true" ]; then
  if docker exec wazuh-manager grep -i "/host-var-log/auth.log" /var/ossec/logs/ossec.log 2>/dev/null | grep -q "Analyzing file"; then
    pass "Wazuh logcollector confirmed monitoring /host-var-log/auth.log"
  else
    fail "No logcollector 'Analyzing file' entry for /host-var-log/auth.log found in /var/ossec/logs/ossec.log"
  fi
else
  fail "Wazuh Manager container is not running, skipping logcollector check"
fi

# 7. AWS-S3 wodle enabled in ossec.log
if [ "$(docker inspect -f '{{.State.Running}}' wazuh-manager 2>/dev/null || echo false)" = "true" ]; then
  if docker exec wazuh-manager grep -iE "wazuh-modulesd:aws-s3|Starting AWS-S3|aws-s3" /var/ossec/logs/ossec.log 2>/dev/null | grep -qv "^$"; then
    pass "Wazuh aws-s3 wodle is enabled and registered in ossec.log"
  else
    fail "No aws-s3 wodle initialization entries found in /var/ossec/logs/ossec.log"
  fi
else
  fail "Wazuh Manager container is not running, skipping aws-s3 wodle check"
fi

# 8. IMDSv2 reachable from inside a container
IMDS_CODE=$(docker run --rm curlimages/curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token 2>/dev/null || echo "000")
if [ "$IMDS_CODE" = "200" ]; then
  pass "IMDSv2 endpoint is reachable from container (HTTP 200 token response)"
else
  fail "IMDSv2 check returned HTTP code $IMDS_CODE (expected 200; verify hop limit >= 2)"
fi

echo
# 9. Docker stats memory table
echo "=== Container Memory and Resource Utilization ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" || true
echo

if [ "$OVERALL_STATUS" -eq 0 ]; then
  echo "All stack checks passed successfully!"
else
  echo "One or more stack verification checks failed."
fi

exit "$OVERALL_STATUS"
