module "albc" {
  source                  = "../modules/albc"
  values                  = local.albc_values
  cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
  eks_cluster_name        = data.terraform_remote_state.eks.outputs.cluster_name
}

module "keda" {
  source                  = "../modules/keda"
  values                  = {}
  cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
  eks_cluster_name        = data.terraform_remote_state.eks.outputs.cluster_name
  depends_on              = [module.albc]
}

module "karpenter" {
  source                  = "../modules/karpenter"
  values                  = {}
  cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
  eks_cluster_name        = data.terraform_remote_state.eks.outputs.cluster_name
  depends_on              = [module.albc]

}

module "fluent-bit" {
  source                  = "../modules/fluent-bit"
  values                  = {}
  cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
  eks_cluster_name        = data.terraform_remote_state.eks.outputs.cluster_name
}

module "istio" {
  source = "../modules/istio"

  eks_cluster_name       = data.terraform_remote_state.eks.outputs.cluster_name
  vpc_id                 = data.terraform_remote_state.vpc.outputs.vpc_id
  node_security_group_id = data.terraform_remote_state.eks.outputs.node_security_group_id

  depends_on = [
    module.albc
  ]

}

module "k8s-gpu-plugin" {
  source = "../modules/k8s-gpu-plugin"

  depends_on = [
    module.karpenter
  ]
}

module "github_actions_access" {
  source = "../modules/eks_access_entry"

  role_name        = "ahmad-github-oidc-role"
  eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}
