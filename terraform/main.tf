terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25" }
  }
  backend "s3" {
    bucket = "opti-inference-tfstate"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

module "vpc" {
  source = "./modules/vpc"
  name   = var.project_name
  region = var.region
}

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  oidc_url     = module.eks.oidc_url
  oidc_arn     = module.eks.oidc_arn
}

module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}

module "eks" {
  source          = "./modules/eks"
  project_name    = var.project_name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  node_role_arn   = module.iam.node_role_arn
}

# NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.14.5"
  namespace  = "kube-system"
  depends_on = [module.eks]
}

# KEDA
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.13.0"
  namespace        = "keda"
  create_namespace = true
  depends_on       = [module.eks]
}

# AWS Load Balancer Controller
resource "helm_release" "aws_lbc" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam.lbc_role_arn
  }
  depends_on = [module.eks]
}
