# onprem resources

resource "aws_eip" "vpn-gateway-eip" {
  provider = aws.onprem
  tags = {
    Name = "vpn-gateway-eip"
  }
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

module "vgw-bgp-asn" {
  source       = "Invicton-Labs/shell-resource/external"
  command_unix = "echo $CGWCONFIG | yq -p xml '.vpn_connection.ipsec_tunnel[0].vpn_gateway.bgp.asn'"
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
    pTunnel1VgwBgpAsn            = module.vgw-bgp-asn.stdout
    pTunnel1BgpNeighborIpAddress = module.vpn_gateway.vpn_connection_tunnel1_vgw_inside_address

    pTunnel2PskSecretName        = aws_secretsmanager_secret.vpn-tunnel2-psk.name
    pTunnel2VgwOutsideIpAddress  = module.vpn_gateway.vpn_connection_tunnel2_address
    pTunnel2CgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel2_cgw_inside_address}/30"
    pTunnel2VgwInsideIpAddress   = "${module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address}/30"
    pTunnel2VgwBgpAsn            = module.vgw-bgp-asn.stdout
    pTunnel2BgpNeighborIpAddress = module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address

    pVpcId           = module.onprem-vpc.vpc_id
    pVpcCidr         = module.onprem-vpc.vpc_cidr_block
    pSubnetId        = module.onprem-vpc.public_subnets[0]
    pUseElasticIp    = true
    pEipAllocationId = aws_eip.vpn-gateway-eip.allocation_id
    pLocalBgpAsn     = module.cgw-bgp-asn.stdout
  }
}

data "aws_instance" "strongswan-vpn-gateway" {
  provider   = aws.onprem
  depends_on = [aws_cloudformation_stack.strongswan-vpn-gateway]

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  filter {
    name   = "tag:Name"
    values = ["poc-vpngw-test"] # TODO this is a derivation from system + app + envpurpose in CloudFormation; this should be in locals
  }
}

resource "aws_route" "onprem-vpc-route-through-vpn" {
  provider               = aws.onprem
  route_table_id         = module.onprem-vpc.private_route_table_ids[0]
  destination_cidr_block = "10.0.0.0/8"
  network_interface_id   = data.aws_instance.strongswan-vpn-gateway.network_interface_id
}
