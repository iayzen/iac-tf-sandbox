terraform {
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

resource "aws_ec2_transit_gateway" "this" {
  description = "My TGW"
}

resource "aws_ram_resource_share" "tgw-resource-share" {
  name                      = "tgw-resource-share"
  allow_external_principals = true
}

data "aws_caller_identity" "onprem" {
  provider = aws.onprem
}

data "aws_caller_identity" "cloud" { }

resource "aws_ram_principal_association" "tgw-resource-share-invite" {
  principal          = data.aws_caller_identity.onprem.account_id
  resource_share_arn = aws_ram_resource_share.tgw-resource-share.arn
}

resource "aws_ram_resource_association" "example" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw-resource-share.arn
}

resource "aws_ram_resource_share_accepter" "receiver_accept" {
  provider  = aws.onprem
  share_arn = aws_ram_principal_association.tgw-resource-share-invite.resource_share_arn
}

resource "aws_eip" "vpn-gateway-eip" { }


module "shared-networking-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "shared-networking-vpc"

  cidr = "10.20.0.0/16"

  azs = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = []
  public_subnets = []
  
}

# module "vpn_gateway" {
#   source  = "terraform-aws-modules/vpn-gateway/aws"
#   version = "~> 2.0"

#   create_vpn_gateway_attachment = false
#   connect_to_transit_gateway    = true

#   vpc_id                     = module.vpc.vpc_id
#   transit_gateway_id         = aws_ec2_transit_gateway.this.id
#   customer_gateway_id        = module.vpc.cgw_ids[0]

#   # tunnel inside cidr & preshared keys (optional)
#   tunnel1_inside_cidr   = var.custom_tunnel1_inside_cidr
#   tunnel2_inside_cidr   = var.custom_tunnel2_inside_cidr
#   tunnel1_preshared_key = var.custom_tunnel1_preshared_key
#   tunnel2_preshared_key = var.custom_tunnel2_preshared_key
# }

# resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
#   subnet_ids         = module.vpc.private_subnets
#   vpc_id             = module.vpc.vpc_id
#   transit_gateway_id = aws_ec2_transit_gateway.this.id
# }