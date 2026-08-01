data "aws_region" "current" {}

resource "aws_iam_role" "ec2_role" {
  name = "photoshare-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_policy" {
  name = "photoshare-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListPhotoPrefixes"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          var.bucket_arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "uploads/*"
            ]
          }
        }
      },
      {
        Sid    = "PhotoObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${var.bucket_arn}/uploads/*"
        ]
      },
      {
        Sid    = "QuarantineWriteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${var.quarantine_bucket_arn}/rejected/*"
        ]
      },
      {
        Sid    = "ReadApplicationSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.secret_arn,
          var.flask_session_secret_arn
        ]
      },
      {
        Sid    = "KMSForAppData"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          var.kms_key_arn
        ]
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "s3.${data.aws_region.current.region}.amazonaws.com",
              "secretsmanager.${data.aws_region.current.region}.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          var.ecr_repository_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

resource "aws_iam_role_policy" "ecr_auth" {
  name = "photoshare-ecr-auth"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.region
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "profile" {
  name = "photoshare-profile"
  role = aws_iam_role.ec2_role.name
}
