# ─────────────────────────────────────────────────────────────────────────────
# Provider & backend.
#
# Backend is intentionally PARTIAL: the bucket/key/region are supplied at
# `terraform init` time from config.yaml via -backend-config, so no account
# specifics are hardcoded. For a local run, init with -backend=false or use the
# commented local backend below.
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Remote state (default). Values injected at init:
  #   terraform init \
  #     -backend-config="bucket=$BUCKET" \
  #     -backend-config="key=vmware2aws/terraform.tfstate" \
  #     -backend-config="region=eu-west-2"
  # For local state instead, run: terraform init -backend=false
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.default_tags
  }
}
