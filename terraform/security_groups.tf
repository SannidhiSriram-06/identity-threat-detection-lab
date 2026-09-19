resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for Identity Threat Detection EC2 (Vault, Wazuh, SSH)"
  vpc_id      = aws_vpc.lab_vpc.id

  # SSH Access
  ingress {
    description = "SSH administrative access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HashiCorp Vault API & Web UI
  ingress {
    description = "HashiCorp Vault UI / API"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Wazuh Dashboard (HTTPS)
  ingress {
    description = "Wazuh Dashboard HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Wazuh Agent registration and communication
  ingress {
    description = "Wazuh Agent events"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
  }

  ingress {
    description = "Wazuh Agent registration"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
  }

  # Wazuh API
  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound rule
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}
