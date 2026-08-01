resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

data "aws_iam_policy_document" "github_trust" {

  statement {

    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {

      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {

      test = "StringEquals"

      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {

      test = "StringLike"

      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:avengsum/secure-aws-photoshare:ref:refs/heads/main"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {

  name = "GitHubActionsDeployRole"

  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  description = "OIDC deployment role for GitHub Actions"
}