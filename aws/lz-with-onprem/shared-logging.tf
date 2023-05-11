# Setup shared-logging resources

module "shared-logging-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "shared-logging-vpc"

  cidr = local.shared_logging_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.shared_logging_vpc_cidr, 8, k + 101)]

  enable_nat_gateway     = false
  single_nat_gateway     = false
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw-attachment-shared-logging-vpc" {
  subnet_ids         = module.shared-logging-vpc.private_subnets
  vpc_id             = module.shared-logging-vpc.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "shared-logging-route-through-tgw" {
  route_table_id         = module.shared-logging-vpc.private_route_table_ids[0]
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_security_group" "shared-logging-vpc-s3-endpoint-sg" {
  name_prefix = "shared-logging-vpc-s3-endpoint-sg"
  description = "S3 Endpoint Security Group"
  vpc_id      = module.shared-logging-vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "shared-logging-vpc-s3-endpoint-sg_TLS" {
  security_group_id = aws_security_group.shared-logging-vpc-s3-endpoint-sg.id
  description       = "TLS from VPC"
  cidr_ipv4         = module.shared-logging-vpc.vpc_cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "shared-logging-vpc-s3-endpoint-sg_InternalNetworks" {
  security_group_id = aws_security_group.shared-logging-vpc-s3-endpoint-sg.id
  description       = "All traffic from internal networks"
  cidr_ipv4         = "10.0.0.0/8"
  ip_protocol       = "-1"
}

module "shared-logging-vpc-endpoints" {
  source             = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id             = module.shared-logging-vpc.vpc_id
  security_group_ids = [aws_security_group.shared-logging-vpc-s3-endpoint-sg.id]

  endpoints = {
    s3 = {
      service = "s3"
      # private_dns_enabled = true
      tags       = { Name = "s3-vpc-endpoint" }
      subnet_ids = module.shared-logging-vpc.private_subnets
    }
  }
}

module "shared-logs-bucket" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  bucket        = local.bucket_name
  force_destroy = true
  attach_policy = true
  policy = templatefile("${path.module}/shared-logging-bucket-policy.json", {
    account_id  = data.aws_caller_identity.cloud.account_id,
    bucket_name = local.bucket_name,
    vpce_s3_id  = module.shared-logging-vpc-endpoints.endpoints.s3.id
  })

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

module "shared-logs-bucket-sample-object" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/object"
  version = "~> 3.10.1"
  bucket  = module.shared-logs-bucket.s3_bucket_id
  key     = "logs-file-${random_id.bucket-id.dec}"

  content = jsonencode({ data : formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp()) })

  # acl           = "private"
  storage_class = "STANDARD"
  force_destroy = true
}
