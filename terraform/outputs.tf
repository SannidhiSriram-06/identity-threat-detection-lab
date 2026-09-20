output "ec2_public_ip" {
  description = "Public IPv4 address of the EC2 threat detection host"
  value       = aws_instance.threat_lab_host.public_ip
}

output "ec2_instance_id" {
  description = "Instance ID of the threat detection host"
  value       = aws_instance.threat_lab_host.id
}

output "ssh_connection_command" {
  description = "SSH connection string to access the instance"
  value       = "ssh -i ~/.ssh/itdl-lab ubuntu@${aws_instance.threat_lab_host.public_ip}"
}

output "ssm_connect_command" {
  description = "AWS SSM Session Manager command (works without opening port 22 or SSH keys)"
  value       = "aws ssm start-session --target ${aws_instance.threat_lab_host.id} --region ${var.aws_region}"
}

output "vault_ui_url" {
  description = "HashiCorp Vault Web UI URL"
  value       = "http://${aws_instance.threat_lab_host.public_ip}:8200"
}

output "wazuh_dashboard_url" {
  description = "Wazuh Security Operations Dashboard URL"
  value       = "https://${aws_instance.threat_lab_host.public_ip}:443"
}

output "cloudtrail_bucket" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.trail.id
}
