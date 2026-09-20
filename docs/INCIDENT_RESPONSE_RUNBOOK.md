# Incident Response Runbook

## Scenario 1: SSH Failed-Login Spray (Alert 100101)

### Detect
- Alert 100101 triggers at Level 10 when 5 or more authentication failures occur from one source within 60s.
- Inspect `/var/log/auth.log` for invalid usernames and source IP addresses.
- Verify active connections with `ss -tna '( dport = :22 )'`.

### Contain
- Block the attacking source IP at host level with `iptables -I INPUT -s <IP> -p tcp --dport 22 -j DROP`.
- Restrict AWS security group port 22 ingress to trusted administrator CIDRs.
- Terminate any active sessions established by the offending source IP.

### Eradicate
- Confirm password authentication remains disabled in `/etc/ssh/sshd_config`.
- Inspect `~/.ssh/authorized_keys` across local accounts for unauthorized keys.
- Rotate administrative SSH key pairs if any account was compromised.

---

## Scenario 2: Repeated Sudo Violations (Alert 100201)

### Detect
- Alert 100201 triggers at Level 12 when 3 or more sudo violations occur within 60s.
- Inspect `/var/log/auth.log` for rejected commands and unauthorized user attempts.
- Identify the offending account and active processes with `ps -u <user> -f`.

### Contain
- Immediately lock the offending user account using `passwd -l <user>`.
- Terminate all user processes with `pkill -KILL -u <user>`.
- Isolate the host from internal networks if unauthorized binaries were executed.

### Eradicate
- Audit `/etc/sudoers` and `/etc/sudoers.d/` for unauthorized privileges or syntax tampering.
- Search for unauthorized setuid binaries using `find / -perm -4000 -type f`.
- Remove unauthorized or temporary user accounts created during the incident.

---

## Scenario 3: Unexpected IAM User or Key Creation (Alert 100300)

### Detect
- Alert 100300 triggers at Level 8 on CloudTrail `CreateUser` or `CreateAccessKey` events.
- Query CloudTrail event history to identify the requesting principal and source IP.
- Check if created IAM entities match expected dynamic patterns like `vault-*`.

### Contain
- Deactivate the access key with `aws iam update-access-key --user-name <user> --access-key-id <key-id> --status Inactive`.
- If generated via Vault, revoke the active lease tree with `vault lease revoke -prefix aws/creds/`.
- Attach an inline deny policy to the IAM user to block all further actions.

### Eradicate
- Delete the unauthorized IAM user, access keys, and policies via AWS CLI.
- Rotate credentials of the compromised principal that provisioned the resources.
- Review Vault audit logs and CloudTrail history to confirm eradication.
