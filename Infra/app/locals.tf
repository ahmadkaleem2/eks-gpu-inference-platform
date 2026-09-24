locals {

  namespace                      = "gpu-inference"
  upload_api_base_k8s_name       = "upload-api"
  inference_worker_base_k8s_name = "inference-worker"

  cluster_oidc_issuer_url = replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")

  folder_array = split("/", abspath("."))

  created_by = join("/", ["https://github.com/ahmadkaleem2/EKS-GPU-Inference-Platform"], slice(local.folder_array, index(local.folder_array, "Infra"), length(local.folder_array)))
}