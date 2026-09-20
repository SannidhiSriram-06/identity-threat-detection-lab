# Find latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# SSH Key Pair
resource "aws_key_pair" "lab_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${var.project_name}-key"
  }
}

# EC2 Instance
resource "aws_instance" "threat_lab_host" {
  ami                                  = data.aws_ami.ubuntu.id
  instance_type                        = var.instance_type
  subnet_id                            = aws_subnet.lab_public_subnet.id
  vpc_security_group_ids               = [aws_security_group.lab_sg.id]
  iam_instance_profile                 = aws_iam_instance_profile.ec2_lab_profile.name
  key_name                             = aws_key_pair.lab_key.key_name
  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  user_data = <<EOF
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Dead-man switch: auto-terminate after configured maximum runtime (minutes after boot)
shutdown -P +${var.max_runtime_minutes}

# System Updates & Essential Tools
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git unzip jq htop hydra

# Configure 4GB Swap Space
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  sysctl vm.swappiness=30
  echo "vm.swappiness=30" >> /etc/sysctl.conf
fi

# Set vm.max_map_count for Wazuh Indexer (OpenSearch engine requires >= 262144)
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Install Docker CE & Compose Plugin
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Clone lab repository
rm -rf /opt/identity-lab
git clone https://github.com/SannidhiSriram-06/identity-threat-detection-lab.git /opt/identity-lab
chown -R ubuntu:ubuntu /opt/identity-lab

# Write environment configuration
cat <<ENV > /opt/identity-lab/lab.env
CLOUDTRAIL_BUCKET=${aws_s3_bucket.trail.id}
AWS_REGION=${var.aws_region}
ENV
chown ubuntu:ubuntu /opt/identity-lab/lab.env

# Execute bootstrap script (non-fatal)
bash /opt/identity-lab/scripts/bootstrap_stack.sh >> /var/log/lab-bootstrap.log 2>&1 || true

echo "Identity Threat Detection Host Initialized Successfully" > /var/log/lab-init.log
EOF

  tags = {
    Name = "${var.project_name}-host"
  }
}
