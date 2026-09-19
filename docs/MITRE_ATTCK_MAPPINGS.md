# MITRE ATT&CK Framework Mappings

This document maps all simulated attack vectors, telemetry sources, and custom Wazuh detection rules implemented in this lab to the **MITRE ATT&CK® Matrix for Enterprise & Cloud (IaaS)**.

---

## 🎯 Threat Detection Mapping Matrix

| Scenario / Threat Vector | MITRE ATT&CK Tactic | Technique ID & Name | Telemetry Source | Wazuh Rule ID & Description | Alert Severity |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **SSH Credential Guessing** | **Credential Access** | [T1110.001](https://attack.mitre.org/techniques/T1110/001/)<br>Password Guessing | Linux `/var/log/auth.log` | **Rule 100100**<br>Single SSH authentication failure | Level 5 (Low) |
| **SSH Rapid Dictionary Spray** | **Credential Access** | [T1110.003](https://attack.mitre.org/techniques/T1110/003/)<br>Password Spraying | Linux `/var/log/auth.log` | **Rule 100101**<br>Possible SSH Brute Force Attack (>5 failures / 60s) | Level 10 (High) |
| **Unauthorized Sudo Invocation** | **Privilege Escalation** | [T1548.003](https://attack.mitre.org/techniques/T1548/003/)<br>Sudo and Sudo Caching | Linux Syslog / `sudo` | **Rule 100200**<br>User NOT in sudoers or bad sudo password | Level 7 (Medium) |
| **Repeated Privilege Escalation** | **Privilege Escalation** | [T1548.003](https://attack.mitre.org/techniques/T1548/003/)<br>Sudo Abuse | Linux Syslog / `sudo` | **Rule 100201**<br>Multiple Privilege Escalation attempts in 60s | Level 12 (Critical) |
| **Shadow / Sensitive Credential Access** | **Credential Access** | [T1003.008](https://attack.mitre.org/techniques/T1003/008/)<br>/etc/passwd and /etc/shadow | Linux Auditd / Syscheck / Auth | **Rule 100202**<br>Suspicious file access or SUID permission modification | Level 10 (High) |
| **Permanent IAM Key Creation** | **Persistence** | [T1098](https://attack.mitre.org/techniques/T1098/)<br>Account Manipulation | AWS CloudTrail (`CreateAccessKey`) | **Rule 100300**<br>CloudTrail: Permanent IAM Access Key created | Level 8 (High) |
| **Console Login Without MFA** | **Initial Access** | [T1078.004](https://attack.mitre.org/techniques/T1078/004/)<br>Valid Cloud Accounts | AWS CloudTrail (`ConsoleLogin`) | **Rule 100301**<br>AWS Management Console login without MFA | Level 9 (High) |
| **Role Assumption / Pivot** | **Lateral Movement** | [T1550.001](https://attack.mitre.org/techniques/T1550/001/)<br>Application Access Token | AWS CloudTrail (`AssumeRole`) | Wazuh Core AWS Ruleset | Level 6 (Medium) |

---

## 🔍 Detailed Technique Breakdown

### 1. T1110.001 & T1110.003 - Brute Force (Password Guessing & Spraying)
- **Adversary Goal:** Gain initial access to the Linux host by exhausting common usernames and default password dictionaries against the OpenSSH daemon on port 22.
- **Detection Mechanism:** Wazuh analyzes `/var/log/auth.log` for `Failed password for invalid user <name>` patterns. When the composite frequency rule `100101` evaluates 5 failed attempts from the identical source IP within a 60-second window, it fires an alert and triggers active response (fail2ban / iptables drop).

### 2. T1548.003 - Abuse Elevation Control Mechanism: Sudo and Sudo Caching
- **Adversary Goal:** After obtaining unprivileged user access (`lab_contractor`), elevate to `root` by exploiting misconfigured sudo rules, password caching, or brute-forcing the user password via `sudo -S`.
- **Detection Mechanism:** Syslog captures entries matching `NOT in sudoers` or `pam_unix(sudo:auth): authentication failure`. Wazuh rule `100200` catches the initial error, while rule `100201` triggers high-priority incident escalation upon repeated failures.

### 3. T1003.008 - OS Credential Dumping: `/etc/passwd` and `/etc/shadow`
- **Adversary Goal:** Extract hashed Linux passwords from `/etc/shadow` for offline hash cracking using Hashcat or John the Ripper.
- **Detection Mechanism:** Wazuh File Integrity Monitoring (FIM) and Linux Auditd monitoring audit rules on access calls to `/etc/shadow`.

### 4. T1078.004 - Valid Accounts: Cloud Accounts & Just-in-Time Mitigations
- **Adversary Goal:** Maintain persistence by provisioning unmonitored permanent IAM credentials or bypassing MFA.
- **Mitigation Architecture:** Using **HashiCorp Vault AWS Secrets Engine**, developers and services never receive permanent IAM access keys. Vault issues short-lived, just-in-time STS tokens with a 15-minute TTL, rendering credential dumping obsolete.
- **Detection Mechanism:** Wazuh ingests AWS CloudTrail logs via the AWS-S3 wodle and fires alerts on unapproved `CreateUser` or `CreateAccessKey` actions outside of the Vault control plane.
