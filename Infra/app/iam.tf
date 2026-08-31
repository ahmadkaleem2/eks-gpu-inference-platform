resource "aws_iam_policy" "upload_api_policy" {                                                                                                       
  
  name = "${local.upload_api_base_k8s_name}-policy-${data.terraform_remote_state.eks.outputs.cluster_name}"   
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [module.s3_bucket.s3_bucket_arn, "${module.s3_bucket.s3_bucket_arn}/*"]
      },
    ]
  })  
     
}

resource "aws_iam_role_policy_attachment" "upload_api_role_policy_attachment" {
  role       = aws_iam_role.upload_api_service_account_role.name
  policy_arn = aws_iam_policy.upload_api_policy.arn
}

resource "aws_iam_role" "upload_api_service_account_role" {
    name = "${local.upload_api_base_k8s_name}-irsa-${data.terraform_remote_state.eks.outputs.cluster_name}"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.cluster_oidc_issuer_url}"
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "${local.cluster_oidc_issuer_url}:sub" = "system:serviceaccount:${local.namespace}:${local.upload_api_base_k8s_name}"
                    }
                }
            }
        ]
    })
}

resource "aws_iam_policy" "inference_worker_policy" {                                                                                                       
  
  name = "${local.inference_worker_base_k8s_name}-policy-${data.terraform_remote_state.eks.outputs.cluster_name}"   
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [module.s3_bucket.s3_bucket_arn, "${module.s3_bucket.s3_bucket_arn}/*"]
      },
            {
        Action = [

          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = [
          module.sqs.queue_arn
            ]
      }
    ]
  })  
     
}

resource "aws_iam_role_policy_attachment" "inference_worker_role_policy_attachment" {
  role       = aws_iam_role.inference_worker_service_account_role.name
  policy_arn = aws_iam_policy.inference_worker_policy.arn
}

resource "aws_iam_role" "inference_worker_service_account_role" {
    name = "${local.inference_worker_base_k8s_name}-irsa-${data.terraform_remote_state.eks.outputs.cluster_name}"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.cluster_oidc_issuer_url}"
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "${local.cluster_oidc_issuer_url}:sub" = "system:serviceaccount:${local.namespace}:${local.inference_worker_base_k8s_name}"
                    }
                }
            }
        ]
    })
}
