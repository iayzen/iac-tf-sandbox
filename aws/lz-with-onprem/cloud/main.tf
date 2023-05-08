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

resource "aws_ec2_transit_gateway" "this" {
  description = "My TGW"
}

resource "aws_ram_resource_share" "tgw-resource-share" {
  name                      = "tgw-resource-share"
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

resource "aws_eip" "vpn-gateway-eip" {
  provider = aws.onprem
  tags = {
    Name = "vpn-gateway-eip"
  }
}

module "shared-networking-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "shared-networking-vpc"

  cidr = "10.20.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  customer_gateways = {
    IP1 = {
      bgp_asn    = 65000
      type       = "ipsec.1"
      ip_address = aws_eip.vpn-gateway-eip.public_ip
    }
  }
}

module "vpn_gateway" {
  source  = "terraform-aws-modules/vpn-gateway/aws"
  version = "~> 2.0"

  tags = {
    Name = "onprem-to-lz-vpn=gateway"
  }

  create_vpn_gateway_attachment = false
  connect_to_transit_gateway    = true

  vpc_id              = module.shared-networking-vpc.vpc_id
  transit_gateway_id  = aws_ec2_transit_gateway.this.id
  customer_gateway_id = module.shared-networking-vpc.cgw_ids[0]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  subnet_ids         = module.shared-networking-vpc.private_subnets
  vpc_id             = module.shared-networking-vpc.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

module "tunnel1-psk" {
  source       = "Invicton-Labs/shell-resource/external"
  command_unix = "echo $CGWCONFIG | yq -p xml '.vpn_connection.ipsec_tunnel[0].ike.pre_shared_key'"
  environment_sensitive = {
    CGWCONFIG = module.vpn_gateway.vpn_connection_customer_gateway_configuration
  }
}

resource "aws_secretsmanager_secret" "vpn-tunnel1-psk" {
  provider                = aws.onprem
  name                    = "vpngw-tunnel1-psk"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "vpn-tunnel1-psk-value" {
  provider      = aws.onprem
  secret_id     = aws_secretsmanager_secret.vpn-tunnel1-psk.id
  secret_string = jsonencode(tomap({ psk = module.tunnel1-psk.stdout }))
}

module "tunnel2-psk" {
  source       = "Invicton-Labs/shell-resource/external"
  command_unix = "echo $CGWCONFIG | yq -p xml '.vpn_connection.ipsec_tunnel[1].ike.pre_shared_key'"
  environment_sensitive = {
    CGWCONFIG = module.vpn_gateway.vpn_connection_customer_gateway_configuration
  }
}

resource "aws_secretsmanager_secret" "vpn-tunnel2-psk" {
  provider                = aws.onprem
  name                    = "vpngw-tunnel2-psk"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "vpn-tunnel2-psk-value" {
  provider      = aws.onprem
  secret_id     = aws_secretsmanager_secret.vpn-tunnel2-psk.id
  secret_string = jsonencode(tomap({ psk = module.tunnel2-psk.stdout }))
}

module "cgw-bgp-asn" {
  source       = "Invicton-Labs/shell-resource/external"
  command_unix = "echo $CGWCONFIG | yq -p xml '.vpn_connection.ipsec_tunnel[0].customer_gateway.bgp.asn'"
  environment_sensitive = {
    CGWCONFIG = module.vpn_gateway.vpn_connection_customer_gateway_configuration
  }
}

module "onprem-vpc" {
  providers = {
    aws = providers.onprem
  }

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

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw-attachment-onprem-vpc" {
  provider           = aws.onprem
  depends_on         = [aws_ram_principal_association.tgw-resource-share-invite]
  subnet_ids         = module.onprem-vpc.private_subnets
  vpc_id             = module.onprem-vpc.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_cloudformation_stack" "strongswan-vpn-gateway" {
  provider           = aws.onprem
  depends_on         = [aws_secretsmanager_secret_version.vpn-tunnel1-psk-value, aws_secretsmanager_secret_version.vpn-tunnel2-psk-value]
  name               = "strongswan-vpn-gateway"
  template_body      = file("${path.module}/vpn-gateway-strongswan.yml")
  capabilities       = ["CAPABILITY_NAMED_IAM"]
  timeout_in_minutes = 10

  parameters = {
    pOrg        = "home"
    pSystem     = "poc"
    pApp        = "vpngw"
    pEnvPurpose = "test"
    pAuthType   = "psk"

    pTunnel1PskSecretName        = aws_secretsmanager_secret.vpn-tunnel1-psk.name
    pTunnel1VgwOutsideIpAddress  = module.vpn_gateway.vpn_connection_tunnel1_address
    pTunnel1CgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel1_cgw_inside_address}/30"
    pTunnel1VgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel1_vgw_inside_address}/30"
    pTunnel1VgwBgpAsn            = module.cgw-bgp-asn.stdout
    pTunnel1BgpNeighborIpAddress = module.vpn_gateway.vpn_connection_tunnel1_vgw_inside_address

    pTunnel2PskSecretName        = aws_secretsmanager_secret.vpn-tunnel2-psk.name
    pTunnel2VgwOutsideIpAddress  = module.vpn_gateway.vpn_connection_tunnel2_address
    pTunnel2CgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel2_cgw_inside_address}/30"
    pTunnel2VgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address}/30"
    pTunnel2VgwBgpAsn            = module.cgw-bgp-asn.stdout
    pTunnel2BgpNeighborIpAddress = module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address

    pVpcId           = module.onprem-vpc.vpc_id
    pVpcCidr         = module.onprem-vpc.vpc_cidr_block
    pSubnetId        = module.onprem-vpc.public_subnets[0]
    pUseElasticIp    = "true"
    pEipAllocationId = aws_eip.vpn-gateway-eip.allocation_id
    pLocalBgpAsn     = module.cgw-bgp-asn.stdout
  }
}


output "tgw-id" {
  value = aws_ec2_transit_gateway.this.id
}

output "tgw-resource-share-name" {
  value = aws_ram_resource_share.tgw-resource-share.name
}

output "tgw-resource-share-arn" {
  value = aws_ram_principal_association.tgw-resource-share-invite.resource_share_arn
}

output "cgw-publicip" {
  value = aws_eip.vpn-gateway-eip.public_ip
}

output "shared-networking-vpc-id" {
  value = module.shared-networking-vpc.vpc_id
}

output "shared-networking-vpc-cidr" {
  value = module.shared-networking-vpc.vpc_cidr_block
}

output "vpn-gateway-tunnel1-psk" {
  value = module.tunnel1-psk.stdout
}

output "vpn-gateway-tunnel2-psk" {
  value = module.tunnel2-psk.stdout
}

output "vpn-gateway-cgw-config" {
  sensitive = true
  value     = module.vpn_gateway.vpn_connection_customer_gateway_configuration
}

output "vpn-gateway-tunnel1-vpg-outside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel1_address
}

output "vpn-gateway-tunnel1-vpg-inside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel1_vgw_inside_address
}

output "vpn-gateway-tunnel1-cgw-inside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel1_cgw_inside_address
}

output "vpn-gateway-cgw-bgp-asn" {
  value = module.cgw-bgp-asn.stdout
}

output "vpn-gateway-tunnel2-vpg-outside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel2_address
}

output "vpn-gateway-tunnel2-vpg-inside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address
}

output "vpn-gateway-tunnel2-cgw-inside-ip" {
  value = module.vpn_gateway.vpn_connection_tunnel2_cgw_inside_address
}