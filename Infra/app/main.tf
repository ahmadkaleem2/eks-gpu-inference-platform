resource "kubernetes_namespace_v1" "namespace" {
  metadata {
    name = local.namespace
    labels = {
      istio-injection = "enabled"
    }
  }
}

resource "kubernetes_deployment_v1" "upload-api" {
  metadata {
    name      = local.upload_api_base_k8s_name
    namespace = local.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.upload_api_base_k8s_name
      }
    }

    template {

      metadata {
        labels = {
          app = local.upload_api_base_k8s_name
        }
      }

      spec {

        service_account_name = kubernetes_service_account_v1.upload-api.metadata[0].name
        container {
          name  = local.upload_api_base_k8s_name
          image = "680688655542.dkr.ecr.us-east-1.amazonaws.com/ahmad/eks-gpu-inference-platform:upload-api-283db45"

          port {
            container_port = 8000
          }
          env {
            name  = "S3_IMAGE_BUCKET"
            value = module.s3_bucket.s3_bucket_id
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "150Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "250Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
          }
        }
      }
    }
  }

  lifecycle {
    # CI deploys new images with `kubectl set image`, so the running tag is
    # expected to drift from the one in this file. Without this, the next
    # terraform apply would roll the deployment back to the pinned tag.
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image,
    ]
  }
  depends_on = [kubernetes_namespace_v1.namespace]
}

resource "kubernetes_service_v1" "upload-api" {
  depends_on = [kubernetes_namespace_v1.namespace]
  metadata {
    name      = local.upload_api_base_k8s_name
    namespace = local.namespace
  }

  spec {
    selector = {
      app = local.upload_api_base_k8s_name
    }

    port {
      port        = 80
      target_port = 8000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service_account_v1" "upload-api" {
  depends_on = [kubernetes_namespace_v1.namespace]
  metadata {
    name      = local.upload_api_base_k8s_name
    namespace = local.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.upload_api_service_account_role.arn
    }
  }
}

resource "kubernetes_manifest" "upload_api_virtualservice" {
  manifest = {
    apiVersion = "networking.istio.io/v1"
    kind       = "VirtualService"
    metadata = {
      name      = local.upload_api_base_k8s_name
      namespace = local.namespace
    }
    spec = {
      hosts    = ["upload.ahmadk.link"]
      gateways = ["istio-system/platform-gateway"]
      http = [
        {
          route = [
            {
              destination = {
                host = "${local.upload_api_base_k8s_name}.${local.namespace}.svc.cluster.local"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_service_v1.upload-api]
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.15.4"

  bucket = lower("Ahmad-GPU-Inference-Bucket-${data.terraform_remote_state.eks.outputs.cluster_name}")

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = {
    enabled = false
  }
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = false
  restrict_public_buckets = true

}

data "aws_partition" "current" {}
module "sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "5.2.2"

  name       = "GPU-Inference-Queue-${data.terraform_remote_state.eks.outputs.cluster_name}"
  fifo_queue = false

  create_dlq = true
  redrive_policy = {
    maxReceiveCount = 5
  }

  create_queue_policy = true

  queue_policy_statements = {
    s3_send_message = {
      sid    = "AllowS3SendMessage"
      effect = "Allow"

      actions   = ["sqs:SendMessage"]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["s3.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "ArnEquals"
          variable = "aws:SourceArn"
          values   = [module.s3_bucket.s3_bucket_arn]
        },
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      ]
    }
  }
}

resource "aws_s3_bucket_notification" "this" {
  bucket = module.s3_bucket.s3_bucket_id


  queue {
    queue_arn     = module.sqs.queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".jpg"
  }

  depends_on = [
    module.sqs
  ]
}

resource "kubernetes_deployment_v1" "inference_worker" {
  depends_on = [kubernetes_namespace_v1.namespace]
  metadata {
    name      = local.inference_worker_base_k8s_name
    namespace = local.namespace
  }

  spec {
    replicas = 0

    strategy {
      rolling_update {
        max_unavailable = "100%"
        max_surge       = "0"
      }
    }

    selector {
      match_labels = {
        app = local.inference_worker_base_k8s_name
      }
    }


    template {

      metadata {
        labels = {
          app = local.inference_worker_base_k8s_name
        }
      }

      spec {


        service_account_name = kubernetes_service_account_v1.inference_worker.metadata[0].name

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {

          name  = local.inference_worker_base_k8s_name
          image = "680688655542.dkr.ecr.us-east-1.amazonaws.com/ahmad/eks-gpu-inference-platform:inference-worker-accf108"

          resources {
            limits = {
              "nvidia.com/gpu" = "1"
            }
          }

          env {
            name  = "MODEL_PATH"
            value = "yolo11x.pt"
          }
          env {
            name  = "IMG_SIZE"
            value = "1280"
          }
          env {
            name  = "BATCH_SIZE"
            value = "8"
          }
          env {
            name  = "MODEL_BUCKET"
            value = module.s3_bucket.s3_bucket_id
          }
          env {
            name  = "RESULTS_BUCKET"
            value = module.s3_bucket.s3_bucket_id
          }
          env {
            name  = "SQS_QUEUE_URL"
            value = module.sqs.queue_url
          }
        }
      }
    }
  }

  lifecycle {
    # CI deploys new images with `kubectl set image`, so the running tag is
    # expected to drift from the one in this file. Without this, the next
    # terraform apply would roll the deployment back to the pinned tag.
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image,
    ]
  }
}

resource "kubernetes_service_account_v1" "inference_worker" {
  depends_on = [kubernetes_namespace_v1.namespace]
  metadata {
    name      = local.inference_worker_base_k8s_name
    namespace = local.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.inference_worker_service_account_role.arn
    }
  }
}

resource "kubernetes_manifest" "inference_worker_scaled_object" {
  depends_on = [kubernetes_namespace_v1.namespace]
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = local.inference_worker_base_k8s_name
      namespace = local.namespace
    }
    spec = {
      scaleTargetRef = { name = local.inference_worker_base_k8s_name }

      minReplicaCount = 0
      maxReplicaCount = 10

      pollingInterval = 60
      cooldownPeriod  = 180

      triggers = [
        {
          type              = "aws-sqs-queue"
          authenticationRef = { name = "aws-sqs-auth" }
          metadata = {
            queueURL              = module.sqs.queue_url
            awsRegion             = "us-east-1"
            queueLength           = "80" # 1 replica per 80 messages once active
            activationQueueLength = "50" # don't scale from 0 until 50+ messages exist
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "keda_trigger_authentication" {
  depends_on = [kubernetes_namespace_v1.namespace]
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"

    metadata = {
      name      = "aws-sqs-auth"
      namespace = local.namespace
    }

    spec = {
      podIdentity = {
        provider      = "aws"
        roleArn       = data.terraform_remote_state.base_k8s_services.outputs.keda_role_arn
        identityOwner = "keda"
      }
    }
  }
}