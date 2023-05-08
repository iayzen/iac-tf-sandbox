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
  profile = "rxt2"
}

provider "aws" {
  profile = "rxt1"
  alias   = "cloud"
}

data "aws_caller_identity" "onprem" {}

data "aws_caller_identity" "cloud" {
  provider = aws.cloud
}

module "cloud-config" {
  source = "../cloud"
}

# data "aws_ram_resource_share" "tgw-share" {
#   name           = 
#   resource_owner = "OTHER-ACCOUNTS"
# }

# resource "aws_ram_resource_share_accepter" "receiver_accept" {
#   share_arn = module.cloud-config.tgw-resource-share-arn

#   timeouts {
#     create = "5m"
#     delete = "5m"
#   }
# }

module "onprem-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "onprem-vpc"

  cidr = "10.100.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.100.101.0/24", "10.100.102.0/24", "10.100.103.0/24"]
  public_subnets  = ["10.100.1.0/24", "10.100.2.0/24", "10.100.3.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  subnet_ids         = module.onprem-vpc.private_subnets
  vpc_id             = module.onprem-vpc.vpc_id
  transit_gateway_id = module.cloud-config.tgw-id
}

resource "aws_secretsmanager_secret" "vpn-tunnel1-psk" {
  name = "vpn-tunnel1-psk"
}

resource "aws_secretsmanager_secret_version" "vpn-tunnel1-psk-value" {
  secret_id     = aws_secretsmanager_secret.vpn-tunnel1-psk.id
  secret_string = jsonencode(tomap({ psk = "$(module.cloud-config.vpn-gateway-tunnel1-psk)" }))
}

resource "aws_secretsmanager_secret" "vpn-tunnel2-psk" {
  name = "vpn-tunnel2-psk"
}

resource "aws_secretsmanager_secret_version" "vpn-tunnel2-psk-value" {
  secret_id     = aws_secretsmanager_secret.vpn-tunnel2-psk.id
  secret_string = jsonencode(tomap({ psk = "$(module.cloud-config.vpn-gateway-tunnel2-psk)" }))
}

