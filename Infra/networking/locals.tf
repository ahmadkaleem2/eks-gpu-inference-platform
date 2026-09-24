locals {
  folder_array = split("/", abspath("."))
  created_by = join("/", ["https://github.com/ahmadkaleem2/EKS-GPU-Inference-Platform"], slice(local.folder_array, index(local.folder_array, "Infra"), length(local.folder_array)))
}