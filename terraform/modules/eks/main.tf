variable "project_name"    {}
variable "vpc_id"          {}
variable "private_subnets" { type = list(string) }
variable "node_role_arn"   {}

resource "aws_eks_cluster" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = var.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_node_group" "gpu_spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gpu-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnets
  capacity_type   = "SPOT"
  instance_types  = ["g4dn.xlarge"]

  scaling_config {
    desired_size = 0
    min_size     = 0
    max_size     = 10
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    "node-type"                    = "gpu"
    "karpenter.sh/capacity-type"   = "spot"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_name"     { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_ca"       { value = aws_eks_cluster.main.certificate_authority[0].data }
output "oidc_url"         { value = aws_eks_cluster.main.identity[0].oidc[0].issuer }
output "oidc_arn"         { value = aws_iam_openid_connect_provider.eks.arn }
