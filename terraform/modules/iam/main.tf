variable "project_name" {}
variable "oidc_url"     {}
variable "oidc_arn"     {}

locals {
  oidc_sub = replace(var.oidc_url, "https://", "")
}

# Node IAM Role
resource "aws_iam_role" "node" {
  name = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# SQS Queue for inference requests
resource "aws_sqs_queue" "inference" {
  name                       = "${var.project_name}-inference-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
}

# KEDA SQS Service Account Role
resource "aws_iam_role" "keda_sqs" {
  name = "${var.project_name}-keda-sqs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:inference:keda-sqs-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "keda_sqs" {
  role = aws_iam_role.keda_sqs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:GetQueueAttributes", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
      Resource = aws_sqs_queue.inference.arn
    }]
  })
}

# AWS Load Balancer Controller Role
resource "aws_iam_role" "lbc" {
  name = "${var.project_name}-lbc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

data "aws_iam_policy_document" "lbc" {
  statement {
    effect    = "Allow"
    actions   = ["elasticloadbalancing:*", "ec2:Describe*", "ec2:AuthorizeSecurityGroupIngress",
                 "ec2:RevokeSecurityGroupIngress", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
                 "ec2:CreateTags", "ec2:DeleteTags", "iam:CreateServiceLinkedRole",
                 "cognito-idp:DescribeUserPoolClient", "acm:ListCertificates",
                 "acm:DescribeCertificate", "waf-regional:*", "wafv2:*", "shield:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lbc" {
  role   = aws_iam_role.lbc.id
  policy = data.aws_iam_policy_document.lbc.json
}

output "node_role_arn"  { value = aws_iam_role.node.arn }
output "keda_role_arn"  { value = aws_iam_role.keda_sqs.arn }
output "lbc_role_arn"   { value = aws_iam_role.lbc.arn }
output "sqs_queue_url"  { value = aws_sqs_queue.inference.url }
output "sqs_queue_arn"  { value = aws_sqs_queue.inference.arn }
