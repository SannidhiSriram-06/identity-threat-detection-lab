# MITRE ATT&CK Framework Mappings

This document maps the custom Wazuh detection rules implemented and verified in this lab to the MITRE ATT&CK Enterprise matrix.

## Verified Custom Detection Rules

| Rule ID | Level | MITRE Tactic | Technique ID & Name | Telemetry Source | Live Alert Count |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **100100** | 5 | Credential Access | [T1110.001](https://attack.mitre.org/techniques/T1110/001/) Password Guessing | Linux `/var/log/auth.log` (sshd) | 10 |
| **100101** | 10 | Credential Access | [T1110.001](https://attack.mitre.org/techniques/T1110/001/) Password Guessing<br>[T1110.003](https://attack.mitre.org/techniques/T1110/003/) Password Spraying | Linux `/var/log/auth.log` (composite: 5 failures in 60s from same IP) | 3 |
| **100200** | 7 | Privilege Escalation<br>Initial Access | [T1548.003](https://attack.mitre.org/techniques/T1548/003/) Sudo and Sudo Caching<br>[T1078](https://attack.mitre.org/techniques/T1078/) Valid Accounts | Linux `/var/log/auth.log` (sudo failure / command not allowed) | 3 |
| **100201** | 12 | Privilege Escalation | [T1548.003](https://attack.mitre.org/techniques/T1548/003/) Sudo and Sudo Caching | Linux `/var/log/auth.log` (composite: 3 sudo failures in 60s) | 1 |
| **100300** | 8 | Persistence<br>Defense Evasion | [T1078.004](https://attack.mitre.org/techniques/T1078/004/) Cloud Accounts<br>[T1098](https://attack.mitre.org/techniques/T1098/) Account Manipulation | AWS CloudTrail (`CreateUser` / `CreateAccessKey`) | 16 |

Total verified custom alerts: 33.

## Detection Engineering & Parent Rule Hierarchy

Custom rules extend built-in parent rules rather than parsing raw strings from scratch:

- **Rule 100100** extends built-in `sshd` failure rules `5710` and `5716` to capture individual authentication failures and invalid user attempts.
- **Rule 100101** aggregates events from rule `100100`, firing when 5 failures occur within 60 seconds from the same source IP.
- **Rule 100200** extends built-in `sudo` failure rules `5401`, `5405`, and `5406` ("command not allowed") to detect unauthorized privilege escalation attempts.
- **Rule 100201** aggregates events from rule `100200`, firing at level 12 when 3 unauthorized sudo attempts occur within 60 seconds.
- **Rule 100300** extends built-in CloudTrail rule `80202` (generic AWS CloudTrail API event rule (one alert per CloudTrail event, e.g. 'AWS Cloudtrail: iam.amazonaws.com - DeleteUser')) to alert on IAM user creation and access key provisioning.

## Observed Built-in Wazuh Rules

During live simulation testing, the following built-in Wazuh rules were also observed firing in response to system, container, and AWS CloudTrail activity:

- `5402`: Successful sudo to ROOT executed
- `5406`: Command not allowed (parent for 100200)
- `5501`: PAM: Login session opened
- `5502`: PAM: Login session closed
- `5503`: PAM: User login failed
- `5901`: New group added to the system
- `5902`: New user added to the system
- `80202`: AWS Cloudtrail API event (parent for 100300)
- `80250`: AWS Cloudtrail API call failed with AccessDenied (observed for iam:ListUsers denied to a Vault-issued user)
