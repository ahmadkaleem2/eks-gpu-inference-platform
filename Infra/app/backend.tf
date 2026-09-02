terraform {
  
  backend "s3" {
    bucket = "terraform-backend-ahmad"
    key    = "Infra/app.tfstate"
    region = "us-east-1"
  }
  
  required_providers {
    aws = {
      source = "hashicorp/aws"

      version = "6.58.0"

    }
    helm = {
      source  = "hashicorp/helm"
      # version = "3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      # version = "2.0"
    }
  }
  
}


provider "aws" {
  region = "us-east-1"


  default_tags {
    tags = {
      # created_by = local.created_by
      
    }
  } 
}


provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}