variable "aws_region" {
  description = "AWS region to deploy the lab"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for lab resources"
  type        = string
  default     = "identity-threat-lab"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "lab"
}

variable "instance_type" {
  description = "EC2 instance type for running Vault and Wazuh SIEM stack"
  type        = string
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "Size of EBS root volume in GB"
  type        = number
  default     = 40
}

variable "ssh_public_key_path" {
  description = "Local path to SSH public key used for EC2 key pair creation"
  type        = string
  default     = "~/.ssh/itdl-lab.pub"
}

variable "max_runtime_minutes" {
  description = "Maximum runtime in minutes after boot before the EC2 host initiates termination"
  type        = number
  default     = 300
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks permitted to access Vault, Wazuh dashboard, and SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
