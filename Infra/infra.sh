#!/bin/bash
set -e

ACTION=$1

if [[ -z "$ACTION" ]]; then
  echo "Usage: ./infra.sh [create|destroy]"
  exit 1
fi

create_infra() {
  echo "Creating infrastructure..."

  cd networking
  terraform init
  terraform apply -auto-approve

  cd ../eks
  terraform init
  terraform apply -auto-approve

  aws eks update-kubeconfig --region us-east-1 --name Ahmad-EKS

  cd ../base_k8s_services
  terraform init
  terraform apply -auto-approve

  cd ../platform_config
  terraform init
  terraform apply -auto-approve

  cd ../app
  terraform init
  terraform apply -auto-approve

  echo "Infrastructure creation complete."
}

destroy_infra() {
  echo "Destroying infrastructure..."

  # NOTE: the app layer is deliberately NOT destroyed here.
  # It owns the stateful resources -- the S3 bucket (model + results) and the SQS
  # queue -- which are meant to survive cluster rebuilds. S3 bucket
  # names are globally unique and slow to recycle, so tearing the bucket down and
  # recreating it is not reliably repeatable.
  # To destroy it for real:  cd app && terraform destroy

  cd app
  terraform init
  terraform destroy -auto-approve -target=kubernetes_manifest.keda_trigger_authentication -target=kubernetes_manifest.inference_worker_scaled_object
  
  cd ../platform_config
  terraform init
  terraform destroy -auto-approve

  cd ../base_k8s_services
  terraform init
  terraform destroy -auto-approve

  cd ../eks
  terraform destroy -auto-approve

  cd ../networking
  terraform destroy -auto-approve

  echo "Infrastructure destroyed."
}

case "$ACTION" in
  create)
    create_infra
    ;;
  destroy)
    destroy_infra
    ;;
  *)
    echo "Invalid option: $ACTION"
    echo "Usage: ./infra.sh [create|destroy]"
    exit 1
    ;;
esac