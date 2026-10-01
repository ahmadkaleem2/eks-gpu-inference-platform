locals {
  helm_set = {

    "config.name" = kubernetes_config_map_v1.nvidia_device_plugin.metadata[0].name

  }
}

resource "helm_release" "this" {
  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  cleanup_on_fail  = false

  set = [
    for k, v in merge(var.values, local.helm_set) : {
      name  = k
      value = v
    }
  ]
}

resource "kubernetes_namespace_v1" "namespace" {
  metadata {
    name = var.namespace
  }
}


resource "kubernetes_config_map_v1" "nvidia_device_plugin" {
  metadata {
    name      = "nvidia-device-plugin-config"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }

  data = {
    "config.yaml" = yamlencode({
      version = "v1"
      sharing = {
        timeSlicing = {
          renameByDefault = false

          resources = [
            {
              name     = "nvidia.com/gpu"
              replicas = 4
            }
          ]
        }
      }
    })
  }
}

resource "helm_release" "dcgm" {
  name             = "dcgm-exporter"
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = "4.8.4"
  namespace        = var.namespace
  create_namespace = false
  cleanup_on_fail  = false

  values = [yamlencode({
    # Time-slicing makes per-pod GPU series duplicates of the same physical GPU.
    arguments    = ["--kubernetes=false"]
    nodeSelector = { "karpenter.sh/nodepool" = "gpu" }
    tolerations = [{
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
    serviceMonitor = {
      additionalLabels = { release = "kube-prometheus-stack" }
    }
  })]
}