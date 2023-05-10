# output "tgw-id" {
#   value = aws_ec2_transit_gateway.this.id
# }

# output "tgw-resource-share-name" {
#   value = aws_ram_resource_share.tgw-resource-share.name
# }

# output "tgw-resource-share-arn" {
#   value = aws_ram_principal_association.tgw-resource-share-invite.resource_share_arn
# }

# output "cgw-publicip" {
#   value = aws_eip.vpn-gateway-eip.public_ip
# }

# output "shared-networking-vpc-id" {
#   value = module.shared-networking-vpc.vpc_id
# }

# output "shared-networking-vpc-cidr" {
#   value = module.shared-networking-vpc.vpc_cidr_block
# }

# output "vpn-gateway-tunnel1-psk" {
#   value = module.tunnel1-psk.stdout
# }

# output "vpn-gateway-tunnel2-psk" {
#   value = module.tunnel2-psk.stdout
# }

# output "vpn-gateway-cgw-config" {
#   sensitive = true
#   value     = module.vpn_gateway.vpn_connection_customer_gateway_configuration
# }

# output "vpn-gateway-tunnel1-vgw-outside-ip" {
#   value = module.vpn_gateway.vpn_connection_tunnel1_address
# }

# output "vpn-gateway-tunnel1-vgw-inside-ip" {
#   value = "${module.vpn_gateway.vpn_connection_tunnel1_vgw_inside_address}/30"
# }

# output "vpn-gateway-tunnel1-cgw-inside-ip" {
#   value = "${module.vpn_gateway.vpn_connection_tunnel1_cgw_inside_address}/30"
# }

# output "vpn-gateway-cgw-bgp-asn" {
#   value = module.cgw-bgp-asn.stdout
# }

# output "vpn-gateway-vgw-bgp-asn" {
#   value = module.vgw-bgp-asn.stdout
# }

# output "vpn-gateway-tunnel2-vgw-outside-ip" {
#   value = module.vpn_gateway.vpn_connection_tunnel2_address
# }

# output "vpn-gateway-tunnel2-vgw-inside-ip" {
#   value = "${module.vpn_gateway.vpn_connection_tunnel2_vgw_inside_address}/30"
# }

# output "vpn-gateway-tunnel2-cgw-inside-ip" {
#   value = "${module.vpn_gateway.vpn_connection_tunnel2_cgw_inside_address}/30"
# }

# output "shared-logging-s3-vpce-dns" {
#   value = module.shared-logging-vpc-endpoints.endpoints.s3.dns_entry[0].dns_name
# }

output "s3-vpce-over-vpn-test-command-ls" {
  value = "aws s3 ls s3://${local.bucket_name} --endpoint-url https://${replace(module.shared-logging-vpc-endpoints.endpoints.s3.dns_entry[0].dns_name, "*", "bucket")} --region eu-central-1"
}

output "s3-vpce-over-vpn-test-command-cp" {
  value = "aws s3 cp s3://${local.bucket_name}/${module.shared-logs-bucket-sample-object.s3_object_id} ~/ --endpoint-url https://${replace(module.shared-logging-vpc-endpoints.endpoints.s3.dns_entry[0].dns_name, "*", "bucket")} --region eu-central-1"
}

output "onprem-test-instance-ssm-connection" {
  value = "aws ssm start-session --target ${data.aws_instances.onprem-test-instance.ids[0]} --profile rxt2"
}
