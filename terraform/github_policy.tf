data "aws_iam_policy_document" "github_permissions" {

  statement {

    sid = "ECR"

    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
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
      "arn:aws:ssm:*:*:document/AWS-RunShellScript",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
  }

  statement {
    sid    = "SSMReadCommandResult"
    effect = "Allow"

    actions = [
      "ssm:GetCommandInvocation",
      "ssm:DescribeInstanceInformation"
    ]

    # GetCommandInvocation does not support resource-level authorization;
    # this is read-only access used to retrieve the result of SendCommand.
    resources = ["*"]
  }

  statement {

    sid    = "DeploymentDiscovery"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth"
    ]

    resources = ["*"]
  }

  statement {

    sid    = "ECRPush"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      aws_ecr_repository.app.arn
    ]
  }
}

resource "aws_iam_policy" "github_actions" {

  name = "GitHubActionsPolicy"

  policy = data.aws_iam_policy_document.github_permissions.json
}


resource "aws_iam_role_policy_attachment" "github_actions" {

  role = aws_iam_role.github_actions.name

  policy_arn = aws_iam_policy.github_actions.arn

}
