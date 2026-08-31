variable "values" {
    type        = map(string)
    description = "A map of key-value pairs to set on the ALBC."
    default = {

    }
}

variable "namespace" {
  description = "Kubernetes namespace for KEDA"
  type        = string
  default     = "keda"
}

variable "keda_version" {
  description = "KEDA Helm chart version"
  type        = string
  default     = "2.20.1"
}

variable "cluster_oidc_issuer_url" {
    type        = string
    description = "The OIDC issuer URL for the EKS cluster."
}

variable "service_account_name" {
    type        = string
    description = "The name of the service account for the ALBC."
    default     = "keda-operator"
}

variable "eks_cluster_name" {
  type = string
  description = "Name of EKS Cluster"
}
