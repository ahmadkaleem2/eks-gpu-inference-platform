resource "helm_release" "this" {
  name       = "karpenter"
  chart      = "oci://public.ecr.aws/karpenter/karpenter"
  version    =  var.karpenter_version
  namespace  = var.namespace
  create_namespace = true
  cleanup_on_fail = false

  set = [for k,v in merge(var.values,local.helm_set) : {
    name  = k
    value = v
  }]
}


resource "kubernetes_manifest" "gpu_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "gpu"
    }

    spec = {
      template = {
        spec = {
          taints = [
            {
              key    = "nvidia.com/gpu"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64", "arm64"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["g4dn.xlarge"]#"g5g.xlarge", "g5g.2xlarge"]
            }
          ]

          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "gpu"
          }


          expireAfter = "720h"
        }
      }

      limits = {
        cpu = "4"
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  }

  depends_on = [
    kubernetes_manifest.gpu_ec2_node_class, helm_release.this
  ]
}


resource "kubernetes_manifest" "gpu_ec2_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"

    metadata = {
      name = "gpu"
    }

    spec = {
      amiFamily = "AL2023"

      amiSelectorTerms = [
        {
          id = "ami-0ec20d5fad1326c34" # x86
          # id = "ami-08bd9fc5b27a5f984" # arm

        }
      ]

      subnetSelectorTerms = [
        {
          tags = {
            "kubernetes.io/cluster/Ahmad-EKS" = "owned"
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "kubernetes.io/cluster/Ahmad-EKS" = "owned"
          }
        }
      ]
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = "50Gi"
            volumeType = "gp3"
          }
        }
      ]

      role = var.node_iam_role_name

      tags = {
        instance_type = "spot"
      }

      associatePublicIPAddress = false

      kubelet = {
        systemReserved = {
          cpu               = "50m"
          memory            = "100Mi"
          "ephemeral-storage" = "1Gi"
        }

        kubeReserved = {
          cpu               = "50m"
          memory            = "100Mi"
          "ephemeral-storage" = "3Gi"
        }

        evictionHard = {
          "memory.available" = "5%"
          "nodefs.available" = "10%"
          "nodefs.inodesFree" = "10%"
        }

        evictionSoft = {
          "memory.available" = "500Mi"
          "nodefs.available" = "15%"
          "nodefs.inodesFree" = "15%"
        }

        evictionSoftGracePeriod = {
          "memory.available" = "1m"
          "nodefs.available" = "1m30s"
          "nodefs.inodesFree" = "2m"
        }

        evictionMaxPodGracePeriod    = 60
        imageGCHighThresholdPercent  = 85
        imageGCLowThresholdPercent   = 80
        cpuCFSQuota                  = true
      }
    }
  }
  depends_on = [ helm_release.this ]
}