locals {
  project_name      = "lz-with-onprem"
  region            = "eu-central-1"
  aws_profile1      = "rxt1"
  aws_profile2      = "rxt2"
  tf_s3_bucket      = "iac-sandbox-terraform-state-202305"
  tf_s3_key         = "${local.project_name}/terraform.tfstate"
  tf_dynamodb_table = "iac-sandbox-terraform-state"
  bucket_name       = "shared-logs-${random_id.bucket-id.hex}"

  azs                        = slice(data.aws_availability_zones.available.names, 0, 3)
  shared_networking_vpc_cidr = "10.20.0.0/16"
  onprem_vpc_cidr            = "10.100.0.0/16"
  shared_logging_vpc_cidr    = "10.30.0.0/16"
}

data "aws_availability_zones" "available" {}

resource "random_id" "bucket-id" {
  byte_length = 6
}
