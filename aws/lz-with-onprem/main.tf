# TODO terragrunt???

terraform {
  backend "s3" {
    profile        = "rxt1" # local.aws_profile1
    bucket         = "iac-sandbox-terraform-state-202305" # local.tf_s3_bucket
    key            = "lz-with-onprem/terraform.tfstate" # local.tf_s3_key
    encrypt        = true
    dynamodb_table = "iac-sandbox-terraform-state" # local.tf_dynamodb_table
    region         = "eu-central-1" # local.region
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  profile = local.aws_profile1
}

provider "aws" {
  profile = local.aws_profile2
  alias   = "onprem"
}

data "aws_caller_identity" "onprem" {
  provider = aws.onprem
}

data "aws_caller_identity" "cloud" {}
