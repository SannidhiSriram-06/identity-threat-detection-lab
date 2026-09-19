variable "aws_region" {
  description = "AWS region to deploy the lab"
  type        = "string"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for lab resources"
  type        = "string"
  default     = "identity-threat-lab"
}

variable "environment" {
  description = "Environment tag"
  type        = "string"
  default     = "lab"
}

variable "instance_type" {
  description = "EC2 instance type (t3.large has 2 vCPUs and 8 GiB RAM required for Wazuh + Vault)"
  type        = "string"
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "Size of EBS root volume in GB"
  type        = number
  default     = 40
}

variable "ssh_key_name" {
  description = "Optional existing EC2 key pair name for SSH access. If left empty, SSH access can be done via EC2 Instance Connect or SSM Session Manager"
  type        = "string"
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR block permitted to access Vault, Wazuh dashboard, and SSH (Restrict to your IP in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
