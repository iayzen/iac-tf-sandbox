data "aws_ami" "amzn-linux-2023-ami" {
  provider    = aws.onprem
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "onprem-vpc-test-instance-sg" {
  provider    = aws.onprem
  name_prefix = "onprem-vpc-test-instance-sg"
  description = "Onprem Test Instance SG"
  vpc_id      = module.onprem-vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "onprem-vpc-test-instance-sg_TLS" {
  provider          = aws.onprem
  security_group_id = aws_security_group.onprem-vpc-test-instance-sg.id
  description       = "TLS from VPC"
  cidr_ipv4         = module.onprem-vpc.vpc_cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "onprem-vpc-test-instance-sg_ICMPfromInternal" {
  provider          = aws.onprem
  security_group_id = aws_security_group.onprem-vpc-test-instance-sg.id
  description       = "ICMP from internal networks"
  cidr_ipv4         = "10.0.0.0/8"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
}

data "aws_iam_policy_document" "assume_role" {
  provider = aws.onprem
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "test-instance-with-ssm" {
  provider           = aws.onprem
  name               = "test-instance-with-ssm"
  description        = "The role for developer test instances EC2"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "attach-ssm-policy-to-test-instance-role" {
  provider   = aws.onprem
  role       = aws_iam_role.test-instance-with-ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "attach-s3-admin-policy-to-test-instance-role" {
  provider   = aws.onprem
  role       = aws_iam_role.test-instance-with-ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "onprem-test-instance-iam-profile" {
  provider = aws.onprem
  name     = "onprem-test-instance-iam-profile"
  role     = aws_iam_role.test-instance-with-ssm.name
}

resource "aws_instance" "onprem-test-instance" {
  provider               = aws.onprem
  ami                    = data.aws_ami.amzn-linux-2023-ami.id
  instance_type          = "t3a.micro"
  subnet_id              = module.onprem-vpc.private_subnets[1]
  vpc_security_group_ids = [aws_security_group.onprem-vpc-test-instance-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.onprem-test-instance-iam-profile.id

  tags = {
    Name = "onprem-test-instance"
  }
}

data "aws_instances" "onprem-test-instance" {
  provider = aws.onprem
  instance_tags = {
    Name = "onprem-test-instance"
  }

  filter {
    name   = "instance.group-id"
    values = [aws_security_group.onprem-vpc-test-instance-sg.id]
  }

  instance_state_names = ["running"]
}
