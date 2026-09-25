locals {
  cluster_name = var.eks_cluster_name
  helm_set = {
    "serviceAccount.annotations.\\eks\\.amazonaws\\.com\\/role-arn" = aws_iam_role.this.arn

    # No default operator Exists
    # Inference-worker's container logs never reach CloudWatch.

    "tolerations[0].operator" = "Exists"

  }
}