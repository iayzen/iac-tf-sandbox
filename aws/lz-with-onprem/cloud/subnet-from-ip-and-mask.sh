#!/bin/bash -
# This script will create a subnet from an IP address and a mask
subnet_from_ip_and_netmask() {
  IFS=. read -r i1 i2 i3 i4 <<< "$1"
  IFS=. read -r m1 m2 m3 m4 <<< "$2"
  printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

config=$(cat)

# tunnel1

t1_psk=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].ike.pre_shared_key')

echo "Tunnel 1 PSK:${t1_psk}"

t1_cgw_ipaddress=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].customer_gateway.tunnel_inside_address.ip_address')
t1_cgw_netmask=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].customer_gateway.tunnel_inside_address.network_mask')
t1_cgw_cidr=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].customer_gateway.tunnel_inside_address.network_cidr')

echo "Tunnel 1 CGW Inside IP:$(subnet_from_ip_and_netmask "${t1_cgw_ipaddress}" "${t1_cgw_netmask}")/${t1_cgw_cidr}"

t1_vgw_ipaddress=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].vpn_gateway.tunnel_inside_address.ip_address')
t1_vgw_netmask=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].vpn_gateway.tunnel_inside_address.network_mask')
t1_vgw_cidr=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[0].vpn_gateway.tunnel_inside_address.network_cidr')

echo "Tunnel 1 VGW Inside IP:$(subnet_from_ip_and_netmask "${t1_vgw_ipaddress}" "${t1_vgw_netmask}")/${t1_vgw_cidr}"

# tunnel2

t2_psk=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].ike.pre_shared_key')

echo "Tunnel 2 PSK:${t2_psk}"

t2_cgw_ipaddress=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].customer_gateway.tunnel_inside_address.ip_address')
t2_cgw_netmask=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].customer_gateway.tunnel_inside_address.network_mask')
t2_cgw_cidr=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].customer_gateway.tunnel_inside_address.network_cidr')

echo "Tunnel 2 CGW Inside IP:$(subnet_from_ip_and_netmask "${t2_cgw_ipaddress}" "${t2_cgw_netmask}")/${t2_cgw_cidr}"

t2_vgw_ipaddress=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].vpn_gateway.tunnel_inside_address.ip_address')
t2_vgw_netmask=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].vpn_gateway.tunnel_inside_address.network_mask')
t2_vgw_cidr=$(echo "$config" | yq -p xml '.vpn_connection.ipsec_tunnel[1].vpn_gateway.tunnel_inside_address.network_cidr')

echo "Tunnel 2 VGW Inside IP:$(subnet_from_ip_and_netmask "${t2_vgw_ipaddress}" "${t2_vgw_netmask}")/${t2_vgw_cidr}"