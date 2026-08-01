data "aws_iam_policy_document" "github_permissions" {

  statement {

    sid = "ECR"

    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage"
    ]

    resources = [
      "*"
    ]
  }

  statement {

    sid = "SSM"

    effect = "Allow"

    actions = [
      "ssm:SendCommand"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "github_actions" {

  name = "GitHubActionsPolicy"

  policy = data.aws_iam_policy_document.github_permissions.json
}