# shared-networking resources

resource "aws_ec2_transit_gateway" "this" {
  description                     = "My TGW"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
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

module "shared-networking-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "shared-networking-vpc"

  cidr = local.shared_networking_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.shared_networking_vpc_cidr, 8, k + 101)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.shared_networking_vpc_cidr, 8, k + 1)]

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
    Name = "onprem-to-lz-vpn-gateway"
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
