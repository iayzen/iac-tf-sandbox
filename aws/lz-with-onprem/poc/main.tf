terraform {
  backend "s3" {
    profile        = "rxt1"
    bucket         = "iac-sandbox-terraform-state-202305"
    key            = "lz-with-onprem/onprem/terraform.tfstate"
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

resource "aws_ec2_transit_gateway" "this" {
  description = "My TGW"
  tags = {
    Name = "tgw-poc-20230507"
  }
}

resource "aws_ram_resource_share" "tgw-resource-share" {
  name                      = "tgw-resource-share-20230507"
  allow_external_principals = true
}

resource "aws_ram_principal_association" "tgw-resource-share-invite" {
  principal          = data.aws_caller_identity.onprem.account_id
  resource_share_arn = aws_ram_resource_share.tgw-resource-share.arn
}

resource "aws_ram_resource_association" "example" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw-resource-share.arn
}