module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name               = "Ahmad-EKS"
  kubernetes_version = "1.36"

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {
      # Fixed Node not ready due to vpc cni not installed.
      resolve_conflicts_on_create = "OVERWRITE"
      before_compute              = true
    }
    metrics-server = {}
  }
  
  # Optional
  endpoint_public_access = true
  create_kms_key = true
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids               = data.terraform_remote_state.vpc.outputs.vpc_private_subnets
  control_plane_subnet_ids = concat(data.terraform_remote_state.vpc.outputs.vpc_public_subnets, data.terraform_remote_state.vpc.outputs.vpc_private_subnets)

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    eks-spot = {
      launch_template_tags = {
        "map-mig" = "mig000000000"
      }
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      # ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["t3a.large"]
      capacity_type  = "SPOT"
      min_size     = 1
      max_size     = 1
      desired_size = 1
      iam_role_additional_policies = {
        "ssm_agent": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
     }
    }
  }
  
  create_cloudwatch_log_group = false
}

resource "aws_security_group_rule" "allow_istio_ingress" {
  type              = "ingress"
  from_port         = 15017
  to_port           = 15017
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
  description       = "Allow Cluster API inbound to the node for istio webhook"
}