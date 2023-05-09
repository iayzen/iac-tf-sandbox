terraform {
  backend "s3" {
    profile        = "rxt1"
    bucket         = "iac-sandbox-terraform-state-202305"
    key            = "lz-with-onprem/cloud/terraform.tfstate"
    encrypt        = true
    dynamodb_table = "iac-sandbox-terraform-state"
    region         = "eu-central-1"
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
  profile = "rxt1"
}

provider "aws" {
  profile = "rxt2"
  alias   = "onprem"
}

data "aws_caller_identity" "onprem" {
  provider = aws.onprem
}

data "aws_caller_identity" "cloud" {}
