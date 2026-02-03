# Data sources

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Derive email and hosted zone from AWS identity (for HashiCorp sandbox accounts)
locals {
  caller_user      = split(":", data.aws_caller_identity.current.user_id)
  email_address    = length(local.caller_user) > 1 ? local.caller_user[1] : "unknown@example.com"
  email_split      = split("@", local.email_address)
  hosted_zone_name = "${replace(local.email_split[0], ".", "-")}.sbx.hashidemos.io"
  aap_fqdn         = "aap.${local.hosted_zone_name}"

  # Default AAP AMIs from rts-aap-demo by region
  default_aap_amis = {
    "us-east-1"      = "ami-09758fd69558336ec"
    "eu-central-1"   = "ami-0f6536ad0b5a0a6a9"
    "ap-southeast-1" = "ami-0efd6a38242c8917e"
    "ap-south-1"     = "ami-076833edc1679a270"
  }

  # Use provided AMI or lookup default
  aap_ami = var.aap_ami_id != "" ? var.aap_ami_id : lookup(local.default_aap_amis, var.aws_region, "")

  # Common tags
  common_tags = merge(var.tags, {
    Terraform = "true"
    Project   = var.name_prefix
  })
}

# Find latest Amazon Linux 2023 AMI for target VMs
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Route53 zone for ALB DNS (only if creating ALB)
data "aws_route53_zone" "hashidemos" {
  count        = var.create_aap && var.create_alb ? 1 : 0
  name         = local.hosted_zone_name
  private_zone = false
}
