# Summary

In the "cloud" account, simulate

a) shared networking component, and
b) shared logging component of an AWS LZ.

# Generic

- Create an IAM role for SSM-managed EC2 hosts

# Shared Networking

- A single VPC spanning 2 AZs, no S3 or DynamoDB gateways
- 2 x public subnets, with a NAT in the first one
- 2 x private subnets, with a route to NAT in each
- Transit Gateway
- TGW attachment for the VPC for both private and public subnets
- RAM TGW share for the Shared Logging VPC

# Shared Logging

- A single VPC spanning 2 AZs, no S3 or DynamoDB gateways
- No public subnets
- 2 x private subnets
- Accept the TGW share
- Create a TGW VPC attachment to both private subnets
- Create a corresponding route to the TGW attachment in both private subnets
- Create a s3-endpoint-private-access-sg to allow all access from 10.0.0.0/8
- Create an S3 Endpoint Interface, using the SG from the previous step
- Create an S3 bucket, ensure no public access
- (Create a test text file to the S3 bucket?)
- Create a TGW VPN attachment (?)
- 