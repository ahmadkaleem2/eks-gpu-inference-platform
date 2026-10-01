locals {

  helm_set = {
    "serviceAccount.annotations.\\eks\\.amazonaws\\.com\\/role-arn" = aws_iam_role.this.arn
    "serviceAccount.create"                                         = "true",
    "replicaCount"                                                  = "1",
    "serviceAccount.name"                                           = "aws-lbc",
    "clusterName"                                                   = var.eks_cluster_name
  }
}