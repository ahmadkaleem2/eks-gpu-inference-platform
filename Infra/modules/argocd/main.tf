resource "helm_release" "this" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.4.2"
  namespace  = "argocd"
  create_namespace = true
  cleanup_on_fail = false
  
  set = [
    {
        name  = "server.service.type"
        value = "ClusterIP"
    }
  ]
}