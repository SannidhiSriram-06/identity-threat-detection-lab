# IAM Role & Instance Profile for EC2 Lab Host
resource "aws_iam_role" "ec2_lab_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach SSM Core for easy console access without SSH keys
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_lab_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Permissions enabling HashiCorp Vault AWS Secrets Engine and Wazuh CloudTrail ingestion
resource "aws_iam_role_policy" "vault_and_wazuh_policy" {
  name = "${var.project_name}-vault-wazuh-policy"
  role = aws_iam_role.ec2_lab_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultDynamicIAMGeneration"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "sts:AssumeRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "WazuhCloudTrailIngestion"
        Effect = "Allow"
        Action = [
          "cloudtrail:LookupEvents",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_lab_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_lab_role.name
}
