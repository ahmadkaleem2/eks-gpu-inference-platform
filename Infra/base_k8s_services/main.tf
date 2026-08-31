module "albc" {
    source = "../modules/albc"
    values = local.albc_values
    cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
    eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}

module "keda" {
    source = "../modules/keda"
    values = {}
    cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
    eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
    depends_on = [module.albc]
}

module "karpenter" {
    source = "../modules/karpenter"
    values = {}
    cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
    eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
    node_iam_role_name = data.terraform_remote_state.eks.outputs.eks_managed_node_groups_iam_role_name

}

# module "fluent-bit" {
#     source = "../modules/fluent-bit"
#     values = {}
#     cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
#     eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

# }

module "istio" {
    source = "../modules/istio"

    eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

}

module "k8s-gpu-plugin" {
    source = "../modules/k8s-gpu-plugin"
}
