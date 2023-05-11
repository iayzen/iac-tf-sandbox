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

  cidr = local.onprem_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.onprem_vpc_cidr, 8, k + 101)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.onprem_vpc_cidr, 8, k + 1)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

data "aws_security_group" "onprem-vpc-default-sg" {
  provider   = aws.onprem
  depends_on = [module.onprem-vpc]
  name       = "default"
  vpc_id     = module.onprem-vpc.vpc_id
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

# resource "aws_security_group" "onprem-vpc-endpoint-sg" {
#   provider    = aws.onprem
#   name_prefix = "onprem-vpc-endpoint-sg"
#   description = "Endpoint Security Group"
#   vpc_id      = module.onprem-vpc.vpc_id
# }

# resource "aws_vpc_security_group_ingress_rule" "onprem-vpc-endpoint-sg_TLS" {
#   provider          = aws.onprem
#   security_group_id = aws_security_group.onprem-vpc-endpoint-sg.id
#   description       = "TLS from VPC"
#   cidr_ipv4         = module.onprem-vpc.vpc_cidr_block
#   from_port         = 443
#   ip_protocol       = "tcp"
#   to_port           = 443
# }

# resource "aws_vpc_security_group_ingress_rule" "onprem-vpc-endpoint-sg_InternalNetworks" {
#   provider          = aws.onprem
#   security_group_id = aws_security_group.onprem-vpc-endpoint-sg.id
#   description       = "All traffic from internal networks"
#   cidr_ipv4         = "10.0.0.0/8"
#   ip_protocol       = "-1"
# }

# module "onprem-vpc-endpoints" {
#   providers = {
#     aws = aws.onprem
#   }

#   create = false

#   source             = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
#   vpc_id             = module.onprem-vpc.vpc_id
#   subnet_ids = module.onprem-vpc.private_subnets
#   security_group_ids = [aws_security_group.onprem-vpc-s3-endpoint-sg.id, data.aws_security_group.onprem-vpc-default-sg.id]

#   endpoints = {
#     s3 = {
#       service = "s3"
#       # private_dns_enabled = true
#       tags       = { Name = "s3-vpc-endpoint" }
#       # subnet_ids = module.onprem-vpc.private_subnets
#     },
#     s3gateway = {
#       service             = "s3"
#       vpc_endpoint_type   = "gateway"
#       tags                = { Name = "s3gateway-vpc-endpoint" }
#       subnet_ids          = module.onprem-vpc.private_subnets
#       route_table_ids     = module.onprem-vpc.private_route_table_ids
#     },
#     ssm = {
#       service    = "ssm"
#       tags       = { Name = "ssm-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     },
#     ssmmessages = {
#       service    = "ssmmessages"
#       tags       = { Name = "ssmmessages-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     },
#     ec2messages = {
#       service    = "ec2messages"
#       tags       = { Name = "ec2messages-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     },
#     ec2 = {
#       service    = "ec2"
#       tags       = { Name = "ec2-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     },
#     kms = {
#       service    = "kms"
#       tags       = { Name = "kms-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     },
#     logs = {
#       service    = "logs"
#       tags       = { Name = "logs-vpc-endpoint" }
#       subnet_ids = module.onprem-vpc.private_subnets
#     }
#   }
# }