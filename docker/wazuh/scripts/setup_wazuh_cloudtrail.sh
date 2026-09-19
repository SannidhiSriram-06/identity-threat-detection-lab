#!/usr/bin/env bash
# ==============================================================================
# Wazuh CloudTrail Ingestion Helper
# Configures AWS credentials and enables the CloudTrail wodle in Wazuh Manager
# ==============================================================================

set -eo pipefail

BUCKET_NAME="${1:-}"

if [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 <cloudtrail-s3-bucket-name>"
  echo "Example: $0 my-company-cloudtrail-logs"
  exit 1
fi

echo "[*] Configuring Wazuh Manager to ingest from CloudTrail bucket: ${BUCKET_NAME}..."

docker exec -i wazuh-manager bash <<EOF
cat << 'CONFIG_EOF' >> /var/ossec/etc/ossec.conf
  <wodle name="aws-s3">
    <disabled>no</disabled>
    <interval>2m</interval>
    <run_on_start>yes</run_on_start>
    <skip_on_error>yes</skip_on_error>
    <service type="cloudtrail">
      <bucket>${BUCKET_NAME}</bucket>
    </service>
  </wodle>
CONFIG_EOF

/var/ossec/bin/wazuh-control restart
EOF

echo "[+] Wazuh CloudTrail wodle enabled and manager restarted!"
