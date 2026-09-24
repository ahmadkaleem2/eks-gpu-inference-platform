resource "helm_release" "this" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  namespace        = var.namespace
  create_namespace = true
  cleanup_on_fail  = true

  set = [for k, v in merge(var.values, local.helm_set) : {
    name  = k
    value = v
  }]
  timeout = 600
  depends_on = [ aws_iam_role.this, aws_iam_role_policy_attachment.this, aws_iam_policy.this ]
}