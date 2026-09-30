resource "helm_release" "prometheus_crds" {
  name       = "prometheus-operator-crds"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  version    = "32.0.1"
  namespace  = "kube-prom-stack"
  create_namespace = true
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "91.8.2"
  namespace  = "kube-prom-stack"
  skip_crds  = true
  timeout    = 900
  atomic     = true

  values = [file("${path.module}/values/kube_prom_stack.yaml")]

  depends_on = [helm_release.prometheus_crds]
}